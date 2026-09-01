# =============================================================================
# R/docker_ops.R
# Docker maintenance and troubleshooting operations.
#
# WINDOWS SAFETY: matches run_cmd.R / artifact.R / batch_exec.R - plain
# paste0() inside stop(), never cli::format_error() with named vectors.
# ASCII-only throughout: no smart quotes, em-dashes, arrows, or emoji.
#
# Docker CLI is cross-platform, so docker calls go through processx directly
# (no PowerShell wrapper). Only free_docker_port() needs PowerShell, because
# Get-NetTCPConnection is Windows-specific.
#
# Public API:
#   clean_docker_storage()          - prune unused Docker resources
#   free_docker_port(port)          - kill the process holding a TCP port (Win)
#   check_docker_oom()              - list containers that exited with 137
#   force_remove_container(name)    - docker rm -f a container
# =============================================================================

# ---- Internal: bounded, structured docker call ------------------------------
# Returns list(ok, status, stdout, stderr). Never throws on command failure.
.docker_run <- function(args, timeout = 60) {
  exe <- Sys.which("docker")
  if (!nzchar(exe)) {
    stop("docker was not found on PATH. Install Docker or add it to PATH.",
         call. = FALSE)
  }

  proc <- tryCatch(
    processx::run(
      command        = "docker",
      args           = args,
      timeout        = timeout,
      error_on_status = FALSE
    ),
    error = function(e) list(status = 124L, stdout = "",
                             stderr = conditionMessage(e))
  )

  # processx can return a RAWSXP status on Windows; coerce defensively.
  safe_status <- tryCatch(
    {
      s <- as.integer(proc$status)
      if (length(s) == 0L || is.na(s)) -1L else s
    },
    error   = function(e) -1L,
    warning = function(w) -1L
  )

  list(
    ok     = identical(safe_status, 0L),
    status = safe_status,
    stdout = .split_lines(proc$stdout),
    stderr = .split_lines(proc$stderr)
  )
}

# ---- Internal: split process text output into a character vector ------------
.split_lines <- function(x) {
  if (is.null(x) || !nzchar(x)) return(character())
  strsplit(x, "\r?\n")[[1]]
}

# ---- Internal: OS guard ------------------------------------------------------
.require_windows <- function(what) {
  if (.Platform$OS.type != "windows") {
    stop(what, " is only supported on Windows.", call. = FALSE)
  }
  invisible(TRUE)
}


#' Clean Docker Storage Bloat
#'
#' Removes unused Docker resources to reclaim disk space by running
#' `docker system prune`. Cross-platform (Windows, Linux, macOS).
#'
#' By default this removes stopped containers, unused networks, and
#' dangling images only. Set `all = TRUE` to also remove unused images not
#' associated with any container, and `volumes = TRUE` to also remove
#' unused volumes. Because volumes may contain application data, volume
#' pruning requires an explicit opt-in.
#'
#' @param all Logical. Also remove all unused images, not just dangling
#'   ones (`--all`). Default `FALSE`.
#' @param volumes Logical. Also remove unused volumes (`--volumes`). This
#'   can permanently delete data. Default `FALSE`.
#' @param dry_run Logical. If `TRUE`, report what would be removed via
#'   `docker system df` without deleting anything. Default `FALSE`.
#' @param confirm Logical. Must be `TRUE` to actually prune when
#'   `volumes = TRUE`. A guardrail against accidental data loss.
#'   Default `TRUE` (interactive sessions still proceed; set to `FALSE`
#'   in scripts to force an explicit re-check).
#' @param timeout Numeric. Seconds before the command is killed. Default
#'   `300` (pruning large caches can be slow).
#' @param verbose Logical. Print progress and reclaimed-space output
#'   (default `TRUE`).
#'
#' @return Invisibly, a list with `ok`, `status`, `stdout`, `stderr`.
#'
#' @export
#' @examples
#' \dontrun{
#' # Safe default: stopped containers, unused networks, dangling images
#' clean_docker_storage()
#'
#' # Aggressive: also remove all unused images and volumes
#' clean_docker_storage(all = TRUE, volumes = TRUE)
#'
#' # Preview only
#' clean_docker_storage(dry_run = TRUE)
#' }
clean_docker_storage <- function(all      = FALSE,
                                 volumes  = FALSE,
                                 dry_run  = FALSE,
                                 confirm  = TRUE,
                                 timeout  = 300,
                                 verbose  = TRUE) {
  if (dry_run) {
    if (verbose) message("Dry run: reporting Docker disk usage (nothing removed).")
    res <- .docker_run(c("system", "df"), timeout = timeout)
    if (verbose) cat(res$stdout, sep = "\n")
    return(invisible(res))
  }

  if (volumes && !isTRUE(confirm)) {
    stop("volumes = TRUE can permanently delete data. ",
         "Re-run with confirm = TRUE to proceed.", call. = FALSE)
  }

  args <- c("system", "prune", "--force")
  if (all)     args <- c(args, "--all")
  if (volumes) args <- c(args, "--volumes")

  if (verbose) {
    message("Pruning unused Docker assets",
            if (all) " (including all unused images)" else "",
            if (volumes) " and unused volumes" else "", " ...")
  }

  res <- .docker_run(args, timeout = timeout)

  if (verbose) {
    if (res$ok) {
      cat(res$stdout, sep = "\n")
    } else {
      message("docker system prune failed (status ", res$status, ").",
              if (length(res$stderr)) paste0(" Detail: ", res$stderr[1]) else "")
    }
  }
  invisible(res)
}


#' Free Up a Blocked Port (Windows)
#'
#' Finds and terminates the Windows process(es) holding a TCP port, using
#' PowerShell's `Get-NetTCPConnection`. Useful when Docker cannot bind a
#' host port because another application is already listening on it.
#'
#' Terminating a process can cause unsaved work to be lost. System PIDs
#' (0 and 4) are never touched.
#'
#' @param port Integer TCP port to clear (1-65535).
#' @param timeout Numeric. Seconds before the command is killed. Default `30`.
#' @param verbose Logical. Print what was found and killed (default `TRUE`).
#'
#' @return Invisibly, a list with `ok`, `status`, `stdout`, `stderr`.
#'
#' @export
#' @examples
#' \dontrun{
#' free_docker_port(8000)
#' free_docker_port(5432)
#' }
free_docker_port <- function(port, timeout = 30, verbose = TRUE) {
  if (!is.numeric(port) || length(port) != 1L || is.na(port) ||
      port < 1 || port > 65535 || port != as.integer(port)) {
    stop("port must be a single integer between 1 and 65535.", call. = FALSE)
  }
  .require_windows("free_docker_port()")

  port <- as.integer(port)
  if (verbose) message("Finding and terminating processes on port ", port, " ...")

  # Enumerate distinct owning PIDs, skip system PIDs (0, 4), then stop each.
  ps_cmd <- paste0(
    "$pids = Get-NetTCPConnection -LocalPort ", port,
    " -ErrorAction SilentlyContinue | ",
    "Select-Object -ExpandProperty OwningProcess -Unique; ",
    "if (-not $pids) { Write-Output 'NO_PROCESS'; exit 0 }; ",
    "foreach ($p in $pids) { ",
    "  if ($p -eq 0 -or $p -eq 4) { continue }; ",
    "  try { Stop-Process -Id $p -Force -ErrorAction Stop; ",
    "        Write-Output ('KILLED ' + $p) } ",
    "  catch { Write-Output ('FAILED ' + $p + ' ' + $_.Exception.Message) } ",
    "}"
  )

  res <- .run_powershell(ps_cmd, timeout = timeout)

  if (verbose) {
    if (any(grepl("NO_PROCESS", res$stdout))) {
      message("No process is listening on port ", port, ".")
    } else if (res$ok) {
      killed <- grep("^KILLED ", res$stdout, value = TRUE)
      failed <- grep("^FAILED ", res$stdout, value = TRUE)
      if (length(killed)) message("Terminated PID(s): ",
                                  paste(sub("^KILLED ", "", killed), collapse = ", "))
      if (length(failed)) message("Could not terminate: ",
                                  paste(failed, collapse = "; "),
                                  " (try running R as Administrator).")
    } else {
      message("free_docker_port() failed (status ", res$status, ").")
    }
  }
  invisible(res)
}


#' Detect Out-of-Memory (OOM) Crashes
#'
#' Lists stopped containers that exited with status code 137 (SIGKILL),
#' which commonly - but not always - indicates an out-of-memory kill.
#' Cross-platform.
#'
#' @param timeout Numeric. Seconds before the command is killed. Default `60`.
#' @param verbose Logical. Print the result table (default `TRUE`).
#'
#' @return Invisibly, a data frame with columns `id`, `name`, `status`.
#'   Empty data frame if no such containers exist.
#'
#' @export
#' @examples
#' \dontrun{
#' check_docker_oom()
#' }
check_docker_oom <- function(timeout = 60, verbose = TRUE) {
  if (verbose) message("Scanning for containers that exited with status 137 ...")

  # Tab-delimited, no "table" header, so parsing is deterministic.
  res <- .docker_run(
    c("ps", "-a", "--filter", "exited=137",
      "--format", "{{.ID}}\t{{.Names}}\t{{.Status}}"),
    timeout = timeout
  )

  empty <- data.frame(id = character(), name = character(),
                      status = character(), stringsAsFactors = FALSE)

  if (!res$ok) {
    if (verbose) message("docker ps failed (status ", res$status, ").")
    return(invisible(empty))
  }
  if (length(res$stdout) == 0L) {
    if (verbose) message("No containers found with exit status 137.")
    return(invisible(empty))
  }

  parts <- strsplit(res$stdout, "\t", fixed = TRUE)
  df <- data.frame(
    id     = vapply(parts, function(p) if (length(p) >= 1L) p[1] else NA_character_, ""),
    name   = vapply(parts, function(p) if (length(p) >= 2L) p[2] else NA_character_, ""),
    status = vapply(parts, function(p) if (length(p) >= 3L) p[3] else NA_character_, ""),
    stringsAsFactors = FALSE
  )
  if (verbose) print(df, row.names = FALSE)
  invisible(df)
}


#' Force Delete a Stuck Container
#'
#' Forcefully removes a Docker container by name or ID via `docker rm -f`.
#' Cross-platform. Persistent volumes are not removed.
#'
#' @param container_name Name or ID of the container to remove.
#' @param timeout Numeric. Seconds before the command is killed. Default `60`.
#' @param verbose Logical. Print progress (default `TRUE`).
#'
#' @return Invisibly, a list with `ok`, `status`, `stdout`, `stderr`.
#'
#' @export
#' @examples
#' \dontrun{
#' force_remove_container("trsbs-api")
#' force_remove_container("a1b2c3d4e5f6")
#' }
force_remove_container <- function(container_name, timeout = 60, verbose = TRUE) {
  if (!is.character(container_name) || length(container_name) != 1L ||
      is.na(container_name) || !nzchar(trimws(container_name))) {
    stop("container_name must be a single non-empty character value.",
         call. = FALSE)
  }
  container_name <- trimws(container_name)

  if (verbose) message("Force removing container: ", container_name, " ...")

  res <- .docker_run(c("rm", "-f", container_name), timeout = timeout)

  if (verbose) {
    if (res$ok) {
      message("Removed: ", paste(res$stdout, collapse = ", "))
    } else {
      message("Failed to remove '", container_name, "' (status ", res$status, ").",
              if (length(res$stderr)) paste0(" Detail: ", res$stderr[1]) else "")
    }
  }
  invisible(res)
}
