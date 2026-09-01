# =============================================================================
# R/diagnose.R
# Docker infrastructure diagnostics for any project (R, JS, web, mixed).
#
# ROBUSTNESS: every Docker call goes through .docker_command(), which uses
# processx::run() with a timeout so an unresponsive daemon can't hang the
# whole diagnosis. Resource checks are cross-platform (Windows/Linux/macOS).
# Security checks verify .dockerignore actually covers sensitive files rather
# than assuming its mere existence protects them.
# =============================================================================

#' Diagnose Docker Infrastructure
#'
#' Runs a comprehensive diagnostic assessment of the Docker infrastructure
#' associated with a project (R, JavaScript/web, or mixed). The report
#' examines the local environment, Docker installation and Engine
#' availability, containers, networking, system resources, and common
#' project security risks.
#'
#' Container names are optional. When omitted, `diagnose()` discovers the
#' containers currently visible to Docker.
#'
#' @param portal_container Optional name of the container running the web portal.
#' @param api_container Optional name of the container running the API.
#' @param db_container Optional name of the container running the database.
#' @param project_path Path to the project being diagnosed. Defaults to the
#'   current working directory.
#' @param timeout Numeric. Seconds before any single Docker call is abandoned
#'   (guards against an unresponsive daemon). Default `15`.
#'
#' @return An object of class `dockrinfra_diagnosis` (also printed).
#'
#' @examples
#' \dontrun{
#' diagnose()
#' diagnose(portal_container = "my-portal", api_container = "my-api")
#' diagnose(project_path = "C:/projects/my-project")
#' }
#'
#' @export
diagnose <- function(
    portal_container = NULL,
    api_container    = NULL,
    db_container     = NULL,
    project_path     = getwd(),
    timeout          = 15
) {
  if (!dir.exists(project_path)) {
    stop("Project path does not exist: ", project_path, call. = FALSE)
  }
  project_path <- normalizePath(project_path, mustWork = TRUE)

  message("Running dockrinfra infrastructure diagnostics...")

  environment <- .diagnose_environment(timeout = timeout)
  containers  <- .diagnose_containers(
    portal_container = portal_container,
    api_container    = api_container,
    db_container     = db_container,
    docker_running   = environment$docker_running,
    timeout          = timeout
  )
  networking <- .diagnose_networking(
    portal_container = portal_container,
    api_container    = api_container,
    project_path     = project_path,
    docker_running   = environment$docker_running,
    timeout          = timeout
  )
  resources <- .diagnose_resources()
  security  <- .diagnose_security(project_path = project_path)

  overall <- .diagnose_overall_status(
    environment = environment,
    containers  = containers,
    networking  = networking,
    resources   = resources,
    security    = security
  )

  result <- list(
    environment = environment,
    containers  = containers,
    networking  = networking,
    resources   = resources,
    security    = security,
    overall     = overall
  )
  class(result) <- "dockrinfra_diagnosis"
  print(result)
  invisible(result)
}


#' Execute a Docker command safely, with a timeout
#'
#' Wraps the Docker CLI via processx so an unresponsive daemon cannot block
#' the diagnosis. stdout/stderr are captured separately; connection failures
#' never raise R warnings.
#'
#' @param args Character vector of arguments passed to Docker.
#' @param timeout Numeric. Seconds before the call is killed.
#'
#' @return list(output, error, status, success)
#' @noRd
.docker_command <- function(args, timeout = 15) {
  docker_path <- Sys.which("docker")
  if (!nzchar(docker_path)) {
    return(list(
      output  = character(),
      error   = "Docker CLI was not found.",
      status  = 127L,
      success = FALSE
    ))
  }

  res <- tryCatch(
    processx::run(
      command         = unname(docker_path),
      args            = args,
      timeout         = if (is.infinite(timeout)) NULL else timeout,
      error_on_status = FALSE
    ),
    # A timeout or spawn failure lands here.
    error = function(e) {
      structure(list(message = conditionMessage(e)), class = "dockrinfra_cmd_error")
    }
  )

  if (inherits(res, "dockrinfra_cmd_error")) {
    return(list(
      output  = character(),
      error   = res$message,
      status  = 124L,          # 124 = conventional timeout exit code
      success = FALSE
    ))
  }

  # Defensive integer coercion (processx can return exotic status types).
  safe_status <- tryCatch({
    s <- as.integer(res$status)
    if (length(s) == 0L || is.na(s)) -1L else s
  }, error = function(e) -1L, warning = function(w) -1L)

  list(
    output  = .split_lines(res$stdout),
    error   = .split_lines(res$stderr),
    status  = safe_status,
    success = identical(safe_status, 0L)
  )
}

# Split a processx output blob into lines, dropping a trailing empty element.
#' @noRd
.split_lines <- function(x) {
  if (is.null(x) || !nzchar(x)) return(character())
  out <- strsplit(x, "\r?\n")[[1]]
  if (length(out) && !nzchar(out[length(out)])) out <- out[-length(out)]
  out
}


#' Diagnose the local Docker environment
#' @noRd
.diagnose_environment <- function(timeout = 15) {
  os_name    <- Sys.info()[["sysname"]]
  os_release <- Sys.info()[["release"]]
  r_version  <- paste(R.version$major, R.version$minor, sep = ".")

  docker_available <- nzchar(Sys.which("docker"))
  docker_version   <- NA_character_
  docker_running   <- FALSE
  docker_error     <- NULL

  if (docker_available) {
    v <- .docker_command(c("--version"), timeout = timeout)
    if (v$success && length(v$output) > 0) {
      docker_version <- trimws(v$output[[1]])
    }
    # `docker info` is the true daemon liveness check; keep it cheap+bounded.
    info <- .docker_command(c("info", "--format", "{{.ServerVersion}}"),
                            timeout = timeout)
    docker_running <- info$success
    if (!docker_running) {
      docker_error <- trimws(paste(c(info$error, info$output), collapse = " "))
      if (!nzchar(docker_error)) docker_error <- NULL
    }
  }

  wsl_available <- FALSE
  wsl_running   <- FALSE
  if (identical(os_name, "Windows")) {
    wsl_available <- nzchar(Sys.which("wsl"))
    if (wsl_available) {
      wsl_result <- tryCatch(
        suppressWarnings(system2("wsl", c("--status"),
                                 stdout = TRUE, stderr = TRUE)),
        error = function(e) character()
      )
      wsl_running <- length(wsl_result) > 0 &&
        !any(grepl("not installed|not running|failed|error",
                   wsl_result, ignore.case = TRUE))
    }
  }

  list(
    os = os_name, os_release = os_release, r_version = r_version,
    docker_available = docker_available, docker_version = docker_version,
    docker_running = docker_running, docker_error = docker_error,
    wsl_available = wsl_available, wsl_running = wsl_running
  )
}


#' Diagnose Docker containers
#' @noRd
.diagnose_containers <- function(
    portal_container = NULL,
    api_container    = NULL,
    db_container     = NULL,
    docker_running   = TRUE,
    timeout          = 15
) {
  if (!docker_running) {
    return(list(unavailable = list(
      name = NA_character_, status = "Docker Engine unavailable",
      running = NA, unavailable = TRUE
    )))
  }

  named <- c(portal = portal_container, api = api_container, database = db_container)
  named <- named[!is.na(named) & nzchar(trimws(named))]
  result <- list()

  # ── Specific containers supplied ────────────────────────────────────────────
  if (length(named) > 0) {
    for (role in names(named)) {
      cname <- trimws(named[[role]])
      insp  <- .docker_command(
        c("inspect", "--format", "{{.State.Status}}", cname),
        timeout = timeout
      )
      if (!insp$success) {
        result[[role]] <- list(name = cname, status = "Not found",
                               running = FALSE, unavailable = FALSE)
        next
      }
      status <- if (length(insp$output) > 0) trimws(insp$output[[1]]) else "Unknown"
      result[[role]] <- list(
        name = cname, status = status,
        running = identical(tolower(status), "running"), unavailable = FALSE
      )
    }
    return(result)
  }

  # ── Discover all containers (unit-separator delimiter avoids collisions) ────
  SEP <- "\x1f"
  fmt <- paste0("{{.ID}}", SEP, "{{.Image}}", SEP, "{{.Status}}", SEP, "{{.Names}}")
  ps  <- .docker_command(c("ps", "-a", "--format", fmt), timeout = timeout)

  if (!ps$success) {
    return(list(unavailable = list(
      name = NA_character_, status = "Unable to inspect Docker containers",
      running = NA, unavailable = TRUE
    )))
  }
  if (length(ps$output) == 0) return(result)

  for (row in ps$output) {
    row <- trimws(row)
    if (!nzchar(row)) next
    parts <- strsplit(row, SEP, fixed = TRUE)[[1]]
    if (length(parts) < 4) next
    result[[parts[[4]]]] <- list(
      name    = parts[[4]],
      id      = parts[[1]],
      image   = parts[[2]],
      status  = parts[[3]],
      running = grepl("^Up\\b", parts[[3]], ignore.case = TRUE),
      unavailable = FALSE
    )
  }
  result
}


#' Diagnose Docker networking (and scan web assets for localhost refs)
#' @noRd
.diagnose_networking <- function(
    portal_container = NULL,
    api_container    = NULL,
    project_path,
    docker_running   = TRUE,
    timeout          = 15
) {
  # ── Scan common web-asset types anywhere in the project, not just js/ ───────
  localhost_refs <- 0L
  web_files <- list.files(
    project_path,
    pattern    = "\\.(js|jsx|ts|tsx|mjs|cjs|html?|vue|svelte)$",
    full.names = TRUE, recursive = TRUE, ignore.case = TRUE
  )
  # Prune dependency/build dirs so we don't scan (or false-positive on) vendored code.
  web_files <- web_files[!grepl(
    "(^|/)(node_modules|\\.git|dist|build|\\.next|\\.cache|renv)/",
    web_files
  )]
  for (f in web_files) {
    lines <- tryCatch(readLines(f, warn = FALSE, encoding = "UTF-8"),
                      error = function(e) character())
    localhost_refs <- localhost_refs +
      sum(grepl("localhost:|127\\.0\\.0\\.1:", lines))
  }

  if (!docker_running) {
    return(list(
      portal_network = NA_character_, api_reachable = NA,
      localhost_refs = localhost_refs, docker_unavailable = TRUE
    ))
  }

  portal_network <- NA_character_
  if (!is.null(portal_container)) {
    insp <- .docker_command(
      c("inspect", "--format",
        "{{range $k, $v := .NetworkSettings.Networks}}{{$k}} {{end}}",
        portal_container),
      timeout = timeout
    )
    if (insp$success && length(insp$output) > 0) {
      nv <- trimws(insp$output[[1]])
      if (nzchar(nv)) portal_network <- nv
    }
  }

  api_reachable <- NA
  if (!is.null(api_container)) {
    insp <- .docker_command(
      c("inspect", "--format", "{{.State.Status}}", api_container),
      timeout = timeout
    )
    if (insp$success && length(insp$output) > 0) {
      api_reachable <- identical(tolower(trimws(insp$output[[1]])), "running")
    }
  }

  list(
    portal_network = portal_network, api_reachable = api_reachable,
    localhost_refs = localhost_refs, docker_unavailable = FALSE
  )
}


#' Diagnose system resources (cross-platform)
#' @noRd
.diagnose_resources <- function() {
  cpu_count <- tryCatch(parallel::detectCores(logical = TRUE),
                        error = function(e) NA_integer_)
  if (is.na(cpu_count)) cpu_count <- 1L      # conservative fallback

  os_name        <- Sys.info()[["sysname"]]
  free_memory_mb <- NA_real_
  free_disk_gb   <- NA_real_

  run_ok <- function(cmd, args) {
    tryCatch(suppressWarnings(system2(cmd, args, stdout = TRUE, stderr = TRUE)),
             error = function(e) character())
  }

  if (identical(os_name, "Windows")) {
    mem <- run_ok("powershell", c("-NoProfile", "-Command",
                                  "(Get-CimInstance Win32_OperatingSystem).FreePhysicalMemory"))
    kb <- suppressWarnings(as.numeric(trimws(mem[1])))
    if (length(kb) && !is.na(kb)) free_memory_mb <- kb / 1024

    disk <- run_ok("powershell", c("-NoProfile", "-Command", "(Get-PSDrive C).Free"))
    b <- suppressWarnings(as.numeric(trimws(disk[1])))
    if (length(b) && !is.na(b)) free_disk_gb <- b / 1024^3

  } else if (identical(os_name, "Linux")) {
    # /proc/meminfo reports MemAvailable in kB.
    mi <- run_ok("sh", c("-c", "grep MemAvailable /proc/meminfo"))
    if (length(mi)) {
      kb <- suppressWarnings(as.numeric(gsub("[^0-9]", "", mi[1])))
      if (!is.na(kb)) free_memory_mb <- kb / 1024
    }
    df <- run_ok("sh", c("-c", "df -k . | tail -1 | awk '{print $4}'"))
    kb <- suppressWarnings(as.numeric(trimws(df[1])))
    if (length(kb) && !is.na(kb)) free_disk_gb <- kb / 1024^2

  } else if (identical(os_name, "Darwin")) {
    # Free pages * page size via vm_stat; page size is 4096 bytes on macOS.
    vm <- run_ok("sh", c("-c", "vm_stat | awk '/Pages free/ {gsub(\".\",\"\",$3); print $3}'"))
    pages <- suppressWarnings(as.numeric(trimws(vm[1])))
    if (length(pages) && !is.na(pages)) free_memory_mb <- pages * 4096 / 1024^2
    df <- run_ok("sh", c("-c", "df -k . | tail -1 | awk '{print $4}'"))
    kb <- suppressWarnings(as.numeric(trimws(df[1])))
    if (length(kb) && !is.na(kb)) free_disk_gb <- kb / 1024^2
  }

  list(
    cpu    = list(count = cpu_count, status = "OK"),
    memory = list(
      free_mb = free_memory_mb,
      status  = if (!is.na(free_memory_mb) && free_memory_mb < 1024) "WARNING" else "OK"
    ),
    disk = list(
      free_gb = free_disk_gb,
      status  = if (!is.na(free_disk_gb) && free_disk_gb < 10) "WARNING" else "OK"
    )
  )
}


#' Diagnose project security (real .dockerignore coverage checks)
#' @noRd
.diagnose_security <- function(project_path) {
  di_path         <- file.path(project_path, ".dockerignore")
  dockerignore_exists <- file.exists(di_path)
  di_entries <- if (dockerignore_exists) {
    tryCatch(trimws(readLines(di_path, warn = FALSE)), error = function(e) character())
  } else character()
  di_entries <- di_entries[nzchar(di_entries) & !grepl("^#", di_entries)]

  # A file is "covered" if an exact entry or a glob that matches it is present.
  covered <- function(target) {
    if (!length(di_entries)) return(FALSE)
    any(vapply(di_entries, function(rule) {
      rule <- sub("^/", "", rule)
      identical(rule, target) ||
        isTRUE(tryCatch(grepl(utils::glob2rx(rule), target), error = function(e) FALSE))
    }, logical(1)))
  }

  renviron_exists <- file.exists(file.path(project_path, ".Renviron"))
  git_exists      <- dir.exists(file.path(project_path, ".git"))

  # Prune noise dirs so the secret scan is fast and low false-positive.
  all_files <- list.files(project_path, recursive = TRUE, full.names = TRUE,
                          ignore.case = TRUE)
  all_files <- all_files[!grepl(
    "(^|/)(node_modules|\\.git|dist|build|\\.next|\\.cache|renv)/", all_files
  )]
  secret_files <- all_files[grepl("(secret|password|credential|token)",
                                  basename(all_files), ignore.case = TRUE)]
  # A detected secret file is only a real risk if it isn't excluded from the build.
  unprotected_secrets <- Filter(
    function(f) !covered(sub(paste0("^", project_path, "/?"), "", f)), secret_files
  )

  list(
    renviron = list(
      exists    = renviron_exists,
      protected = if (renviron_exists) covered(".Renviron") else TRUE
    ),
    git = list(
      exists    = git_exists,
      protected = if (git_exists) covered(".git") else TRUE
    ),
    secrets = list(
      detected  = length(unprotected_secrets) > 0,
      count     = length(unprotected_secrets),
      protected = length(unprotected_secrets) == 0
    ),
    dockerignore = list(exists = dockerignore_exists)
  )
}


#' Determine overall diagnostic status
#' @noRd
.diagnose_overall_status <- function(environment, containers, networking,
                                     resources, security) {
  issues <- character()

  if (!environment$docker_available) {
    issues <- c(issues, "Docker CLI was not found.")
  }
  if (environment$docker_available && !environment$docker_running) {
    issues <- c(issues, "Docker Engine is not running.")
  }
  if (environment$docker_running && length(containers) > 0) {
    for (container in containers) {
      if (isTRUE(container$unavailable)) next
      if (identical(container$running, FALSE)) {
        issues <- c(issues, paste("Container", container$name, "is not running."))
      }
    }
  }
  if (environment$docker_running && !is.na(networking$api_reachable) &&
      !networking$api_reachable) {
    issues <- c(issues, "Specified API container is not reachable.")
  }
  if (networking$localhost_refs > 0) {
    issues <- c(issues, paste(networking$localhost_refs,
                              "localhost API reference(s) detected."))
  }
  if (resources$memory$status == "WARNING") issues <- c(issues, "Available memory is low.")
  if (resources$disk$status   == "WARNING") issues <- c(issues, "Available disk space is low.")
  if (security$secrets$detected) issues <- c(issues, "Unprotected secret files detected.")

  list(
    status      = if (length(issues) == 0) "OK" else "WARNING",
    issue_count = length(issues),
    issues      = issues
  )
}
