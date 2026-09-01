# =============================================================================
# R/need.R
# Pre-flight environment validation.
# Assert everything a pipeline needs before a single step runs.
#
# WINDOWS SAFETY: matches run_cmd.R / artifact.R - plain paste0() inside
# stop(), never cli::format_error() with named vectors.
# ASCII-only throughout: no smart quotes, em-dashes, arrows, or emoji.
# =============================================================================

#' Assert that a pipeline's environment is ready
#'
#' Checks that required system commands, environment variables, files,
#' directories, and R packages all exist before a pipeline starts. If
#' anything is missing it stops with a clear, actionable error message
#' listing every missing item, not just the first one.
#'
#' Call `need()` at the top of any script that will run unattended or in
#' CI. It is far better to fail loudly at the start than to fail silently
#' halfway through a pipeline after 10 minutes of work.
#'
#' @param cmd Character vector. System commands that must be on PATH
#'   (e.g. `c("git", "pwsh", "gh")`). Windows `.cmd`/`.bat`/`.exe`
#'   wrappers are resolved the same way as in [run_cmd()].
#' @param env Character vector. Environment variable names that must be
#'   set and non-empty (e.g. `c("AZURE_KEY", "OPENAFRR_REPO")`).
#' @param file Character vector. File paths that must exist (a directory
#'   at that path does not satisfy a `file` requirement).
#' @param dir Character vector. Directory paths that must exist.
#' @param pkg Character vector. R package names that must be installed.
#' @param r_version Character. Minimum R version required, e.g. `"4.2.0"`.
#'   `NULL` (default) skips this check.
#' @param verbose Logical. Print a success message if all checks pass
#'   (default `TRUE`).
#'
#' @return Invisibly returns `TRUE` if all checks pass. Throws a
#'   descriptive error listing every missing item if any check fails.
#'
#' @export
#' @examples
#' \dontrun{
#' need(
#'   cmd  = c("git", "pwsh", "gh"),
#'   env  = c("OPENAFRR_REPO", "AZURE_KEY"),
#'   file = "inst/ps/fetch.ps1",
#'   pkg  = c("arrow", "readxl")
#' )
#' need(r_version = "4.2.0")
#' }
need <- function(
    cmd       = character(),
    env       = character(),
    file      = character(),
    dir       = character(),
    pkg       = character(),
    r_version = NULL,
    verbose   = TRUE
) {
  failures <- character()

  # ---- Command checks --------------------------------------------------------
  for (cmd_i in cmd) {
    if (!nzchar(.which_exe(cmd_i))) {
      hint <- .need_cmd_hint(cmd_i)
      failures <- c(
        failures,
        paste0("Command not found: '", cmd_i, "'",
               if (nzchar(hint)) paste0(" - ", hint) else "")
      )
    }
  }

  # ---- Environment variable checks -------------------------------------------
  for (env_i in env) {
    if (!nzchar(Sys.getenv(env_i, unset = ""))) {
      failures <- c(
        failures,
        paste0("Environment variable not set: '", env_i, "'",
               " - set with Sys.setenv(", env_i, " = \"...\")")
      )
    }
  }

  # ---- File checks -----------------------------------------------------------
  for (file_i in file) {
    if (!file.exists(file_i) || dir.exists(file_i)) {
      failures <- c(
        failures,
        paste0("File not found: '", file_i, "'")
      )
    }
  }

  # ---- Directory checks ------------------------------------------------------
  for (dir_i in dir) {
    if (!dir.exists(dir_i)) {
      failures <- c(
        failures,
        paste0("Directory not found: '", dir_i, "'")
      )
    }
  }

  # ---- R package checks ------------------------------------------------------
  for (pkg_i in pkg) {
    if (!requireNamespace(pkg_i, quietly = TRUE)) {
      failures <- c(
        failures,
        paste0("R package not installed: '", pkg_i, "'",
               " - install with install.packages(\"", pkg_i, "\")")
      )
    }
  }

  # ---- R version check -------------------------------------------------------
  if (!is.null(r_version)) {
    current <- as.character(getRversion())
    if (utils::compareVersion(current, r_version) < 0L) {
      failures <- c(
        failures,
        paste0("R version too old: need >= ", r_version,
               ", have ", current,
               " - upgrade at https://cran.r-project.org")
      )
    }
  }

  # ---- Report ----------------------------------------------------------------
  if (length(failures) > 0L) {
    fail_lines <- c(
      paste0("need() found ", length(failures),
             " missing requirement(s):"),
      paste0("  x ", failures)
    )
    stop(paste(fail_lines, collapse = "\n"), call. = FALSE)
  }

  n_checks <- length(cmd) + length(env) + length(file) +
    length(dir) + length(pkg) +
    if (!is.null(r_version)) 1L else 0L

  if (verbose && n_checks > 0L) {
    cli::cli_alert_success(
      "All {.val {n_checks}} requirement(s) satisfied. Pipeline is ready."
    )
  }

  invisible(TRUE)
}

# ---- Internal: install hints for common commands ----------------------------
#' @noRd
.need_cmd_hint <- function(cmd) {
  switch(cmd,
         git     = "install from https://git-scm.com",
         gh      = "install from https://cli.github.com",
         pwsh    = "install PowerShell 7+ from https://aka.ms/powershell",
         python  = "install from https://python.org",
         python3 = "install from https://python.org",
         quarto  = "install from https://quarto.org",
         node    = "install from https://nodejs.org",
         npm     = "install from https://nodejs.org",
         docker  = "install from https://docker.com",
         aws     = "install from https://aws.amazon.com/cli",
         ""
  )
}

# ---- Internal: Windows-aware executable resolution --------------------------
# Same helper introduced in run_cmd.R. Keep a single canonical copy in orchrd.
#' @noRd
.which_exe <- function(exe) {
  path <- Sys.which(exe)
  if (nzchar(path)) return(unname(path))
  if (.Platform$OS.type == "windows") {
    for (ext in c(".exe", ".cmd", ".bat")) {
      path <- Sys.which(paste0(exe, ext))
      if (nzchar(path)) return(unname(path))
    }
  }
  ""
}
