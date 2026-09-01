# =============================================================================
# R/repair.R
# Windows-only recovery helpers for a stuck Docker Desktop / WSL backend.
#
# WINDOWS SAFETY: matches run_cmd.R / diagnose.R conventions — processx with
# a bounded timeout, defensive as.integer() status coercion, plain paste0()
# inside stop(), and a structured result instead of a raw character vector.
# =============================================================================

# ── Internal: hard-require Windows ────────────────────────────────────────────
.require_windows <- function(fn) {
  if (.Platform$OS.type != "windows") {
    stop(
      paste0(fn, "() is Windows-only (it drives Docker Desktop + WSL via ",
             "PowerShell). Detected OS type: '", .Platform$OS.type, "'."),
      call. = FALSE
    )
  }
  invisible(TRUE)
}

# ── Internal: run a PowerShell script via a temp .ps1 file ────────────────────
# Using -File with a temp script avoids the -Command quoting minefield for
# multi-statement scripts, and processx gives us a real timeout + clean
# stdout/stderr separation.
.run_powershell <- function(script, timeout = 120) {
  ps <- Sys.which("powershell")
  if (!nzchar(ps)) ps <- Sys.which("pwsh")        # PowerShell 7 fallback
  if (!nzchar(ps)) {
    return(list(ok = FALSE, status = 127L, stdout = character(),
                stderr = "PowerShell (powershell/pwsh) not found on PATH."))
  }

  tmp <- tempfile(fileext = ".ps1")
  on.exit(unlink(tmp), add = TRUE)
  writeLines(script, tmp)

  proc <- tryCatch(
    processx::run(
      command = unname(ps),
      args = c("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", tmp),
      timeout = if (is.infinite(timeout)) NULL else timeout,
      error_on_status = FALSE
    ),
    error = function(e) NULL
  )

  if (is.null(proc)) {
    return(list(ok = FALSE, status = 124L, stdout = character(),
                stderr = "PowerShell call failed or timed out."))
  }

  status <- tryCatch({
    s <- as.integer(proc$status)
    if (length(s) == 0L || is.na(s)) -1L else s
  }, error = function(e) -1L, warning = function(w) -1L)

  list(
    ok     = (status == 0L),
    status = status,
    stdout = if (nzchar(proc$stdout)) strsplit(proc$stdout, "\r?\n")[[1]] else character(),
    stderr = if (nzchar(proc$stderr)) strsplit(proc$stderr, "\r?\n")[[1]] else character()
  )
}

# ── Internal: locate Docker Desktop.exe ───────────────────────────────────────
.docker_desktop_exe <- function() {
  candidates <- c(
    file.path(Sys.getenv("ProgramFiles", "C:/Program Files"),
              "Docker", "Docker", "Docker Desktop.exe"),
    file.path(Sys.getenv("ProgramW6432", "C:/Program Files"),
              "Docker", "Docker", "Docker Desktop.exe"),
    file.path(Sys.getenv("LOCALAPPDATA", ""),
              "Docker", "Docker Desktop.exe")
  )
  hit <- candidates[file.exists(candidates)]
  if (length(hit)) hit[1] else NA_character_
}


#' Repair a Stuck Docker Engine (Windows)
#'
#' Attempts to recover a Docker Desktop installation that is stuck or
#' unresponsive on Windows by stopping the Docker Desktop and backend
#' processes, shutting down WSL, restarting the WSL service, and relaunching
#' Docker Desktop.
#'
#' Windows-only. Some operations (restarting the WSL service) may require an
#' elevated (Administrator) R session; when not elevated, those steps are
#' skipped by PowerShell and reported in the result's `stderr`.
#'
#' @param timeout Numeric. Seconds before the PowerShell recovery script is
#'   killed. Default `120`. Use `Inf` to wait indefinitely.
#' @param verbose Logical. Print progress (default `TRUE`).
#'
#' @return Invisibly, a list with `ok`, `status`, `stdout`, and `stderr`.
#'
#' @examples
#' \dontrun{
#' res <- repair_docker()
#' res$ok
#' }
#'
#' @export
repair_docker <- function(timeout = 120, verbose = TRUE) {
  .require_windows("repair_docker")
  if (verbose) message("Attempting to unstick Docker Engine via PowerShell...")

  exe <- .docker_desktop_exe()
  start_line <- if (!is.na(exe)) {
    paste0('Start-Process "', exe, '"')
  } else {
    # Best effort via Start Menu shortcut resolution.
    'Start-Process "Docker Desktop" -ErrorAction SilentlyContinue'
  }

  # Handle both WslService (Win11/recent) and LxssManager (older) service names.
  script <- c(
    'Stop-Process -Name "Docker Desktop" -Force -ErrorAction SilentlyContinue',
    'Stop-Process -Name "com.docker.backend" -Force -ErrorAction SilentlyContinue',
    'wsl --shutdown',
    '$svc = Get-Service -Name "WslService","LxssManager" -ErrorAction SilentlyContinue |',
    '  Where-Object { $_.Status -ne $null } | Select-Object -First 1',
    'if ($svc) { Restart-Service -Name $svc.Name -Force -ErrorAction SilentlyContinue }',
    start_line
  )

  res <- .run_powershell(script, timeout = timeout)

  if (verbose) {
    if (res$ok) {
      message("Docker Desktop restart sequence issued. Give the engine a moment to come up.")
    } else {
      message("Recovery script exited with status ", res$status,
              if (length(res$stderr)) paste0(": ", res$stderr[1]) else ".")
    }
    if (is.na(exe)) {
      message("Note: Docker Desktop.exe was not found in the usual locations; ",
              "attempted launch by name.")
    }
  }

  invisible(res)
}


#' Fix Docker Named Pipe Permissions (Windows)
#'
#' Adds the current Windows user to the local `docker-users` security group so
#' Docker Desktop can be used without per-operation elevation.
#'
#' Windows-only, and **requires an elevated (Administrator) R session** —
#' modifying local groups is an administrative operation. Unlike the original,
#' this reports failure instead of silently swallowing a permission error.
#'
#' @param user Character. Windows username to add. Defaults to the current
#'   user (`USERNAME` env var).
#' @param timeout Numeric. Seconds before the PowerShell call is killed.
#'   Default `60`.
#' @param verbose Logical. Print progress (default `TRUE`).
#'
#' @return Invisibly, a list with `ok`, `status`, `stdout`, and `stderr`.
#'
#' @examples
#' \dontrun{
#' res <- fix_docker_permissions()
#' res$ok
#' }
#'
#' @export
fix_docker_permissions <- function(user = Sys.getenv("USERNAME"),
                                   timeout = 60, verbose = TRUE) {
  .require_windows("fix_docker_permissions")

  if (!nzchar(user)) {
    stop("Could not determine the Windows username (USERNAME is unset). ",
         "Pass `user = \"...\"` explicitly.", call. = FALSE)
  }

  if (verbose) {
    message("Adding '", user, "' to the docker-users security group...")
  }

  # No -ErrorAction SilentlyContinue: we WANT the error surfaced. Treat
  # "already a member" as success; everything else (esp. access denied) fails.
  script <- c(
    'try {',
    paste0('  Add-LocalGroupMember -Group "docker-users" -Member "', user, '" -ErrorAction Stop'),
    '  Write-Output "ADDED"',
    '} catch {',
    '  if ($_.Exception.Message -match "already a member") {',
    '    Write-Output "ALREADY_MEMBER"',
    '  } else {',
    '    Write-Error $_.Exception.Message',
    '    exit 1',
    '  }',
    '}'
  )

  res <- .run_powershell(script, timeout = timeout)

  if (verbose) {
    if (res$ok && any(grepl("ALREADY_MEMBER", res$stdout))) {
      message("'", user, "' is already in docker-users. Nothing to do.")
    } else if (res$ok) {
      message("Success. Sign out and back in for the change to take effect.")
    } else {
      message("Failed (status ", res$status, "). This usually means the R ",
              "session is not elevated. Re-run R as Administrator.",
              if (length(res$stderr)) paste0(" Detail: ", res$stderr[1]) else "")
    }
  }

  invisible(res)
}
