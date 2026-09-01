# =============================================================================
# R/orchrd-package.R
# Package-level documentation, global imports, and shared utilities.
#
# WINDOWS SAFETY: matches run_cmd.R / artifact.R / batch_exec.R - plain
# paste0() / string concatenation inside stop(), never cli::format_error()
# with named vectors. ASCII-only throughout: no smart quotes, em-dashes,
# arrows, box-drawing characters, or emoji.
#
# This file is the canonical home for cross-cutting internal helpers that
# multiple source files use: .which_exe(), .split_lines(), .split_cmd(),
# .cache_dir(), .run_powershell(). Keep exactly one copy of each here.
# =============================================================================

#' orchrd: PowerShell-Inspired Workflow Orchestration for R
#'
#' @description
#' `orchrd` brings PowerShell's workflow philosophy into R:
#' simple commands, clean outputs, pipeline thinking, retry logic,
#' and automation-friendly logging.
#'
#' Designed as infrastructure for the openafrR ecosystem but useful
#' for any R developer orchestrating scripts, APIs, and system processes.
#'
#' ## Core functions
#'
#' | Function | What it does |
#' |---|---|
#' | [run_cmd()] | Run any system command, get structured output |
#' | [run_script()] | Run R / Python / PowerShell / bash scripts |
#' | [pipe_exec()] | Chain steps into a named, logged pipeline |
#' | [retry()] | Retry any expression with backoff and jitter |
#' | [log_step()] | Log a workflow step with level and timing |
#' | [with_log()] | Auto-log entry, exit, and elapsed for any block |
#' | [log_config()] | Configure log level and output file |
#' | [get_log()] | Retrieve the in-memory session log |
#' | `inspect_file()` | See full structure of Excel/CSV/PDF before reading |
#' | `read_tabs()` | Smart multi-tab Excel reader |
#' | `sniff_csv()` | Detect encoding, delimiter, skip rows before reading |
#' | `scan_pdf()` | Classify PDF as digital or scanned, detect tables |
#' | `read_clean()` | One-shot smart reader for any file type |
#' | `warm_cache()` | Parallel cache warming via PowerShell |
#' | `cache_status()` | Report on the local dataset cache |
#' | `cache_clear()` | Remove stale or all cached files |
#' | `ps_available()` | Check if PowerShell 7 plus is installed |
#' | `validate_article()` | Validate an article before submission |
#' | `submit_article()` | Submit an article via git and GitHub PR |
#' | `article_status()` | Poll PR approval state |
#' | `list_articles()` | List all your article submissions |
#' | `retract_article()` | Close a PR and delete the remote branch |
#'
#' ## Quick start
#'
#' ```r
#' library(orchrd)
#'
#' # Run a system command and get structured output
#' result <- run_cmd("git status")
#' result$ok
#' result$stdout
#'
#' # Full pipeline with logging and retry
#' log_config(file = "logs/session.json")
#'
#' pipe_exec(
#'   fetch  = ~ retry(some_api_call()),
#'   clean  = ~ dplyr::filter(.x, !is.na(value)),
#'   export = ~ arrow::write_parquet(.x, "data/output.parquet")
#' )
#' ```
#'
#' @keywords internal
"_PACKAGE"

# ---- Global imports ----------------------------------------------------------
# NOTE: cli::format_error / format_warning are intentionally NOT imported.
# The package uses plain paste0() inside stop() to avoid the recursive RAWSXP
# crash on Windows during error unwinding. cli_progress_done replaces the older
# cli_process_done / cli_process_failed pairing used in earlier drafts.
#' @importFrom rlang `%||%` is_formula as_function list2
#' @importFrom cli cli_inform cli_alert_success cli_alert_warning cli_alert_danger cli_rule cli_progress_step cli_progress_done col_green col_red col_grey style_bold cli_warn cli_text
#' @importFrom jsonlite fromJSON toJSON write_json
#' @importFrom processx run
NULL

# ---- Package-level shared utilities ------------------------------------------

#' Resolve the default orchrd cache directory
#'
#' Respects the ORCHRD_CACHE environment variable; otherwise uses the
#' cross-platform user cache directory (tools::R_user_dir), which is reliable
#' on Windows unlike Sys.getenv("HOME").
#' @noRd
.cache_dir <- function() {
  base <- Sys.getenv("ORCHRD_CACHE", unset = "")
  if (nzchar(base)) {
    return(normalizePath(base, mustWork = FALSE))
  }
  normalizePath(
    file.path(tools::R_user_dir("orchrd", which = "cache"), "raw"),
    mustWork = FALSE
  )
}

#' Resolve an executable, retrying Windows wrappers (.exe/.cmd/.bat)
#'
#' Canonical copy for the whole package. Sys.which() alone can miss .cmd/.bat
#' wrappers (npm, aws, gh, pwsh shims) on Windows. Returns "" if not found.
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

#' Locate a usable PowerShell executable
#'
#' Prefers Windows PowerShell 5.1 (powershell), falling back to PowerShell 7+
#' (pwsh). Returns "" if neither is available.
#' @noRd
.find_powershell <- function() {
  for (exe in c("powershell", "pwsh")) {
    path <- .which_exe(exe)
    if (nzchar(path)) return(path)
  }
  ""
}

#' Resolve a PowerShell script bundled in inst/ps/
#'
#' system.file() already covers both the installed package and
#' devtools::load_all() development trees, so a single lookup suffices.
#' @param script_name Filename of the .ps1 script (e.g. "openafrR-fetch.ps1")
#' @noRd
.ps_script <- function(script_name) {
  pkg_path <- system.file("ps", script_name, package = "orchrd")
  if (nzchar(pkg_path) && file.exists(pkg_path)) return(pkg_path)

  stop(
    paste0(
      script_name, " not found.\n",
      "  Expected at inst/ps/", script_name, " in the orchrd package."
    ),
    call. = FALSE
  )
}

#' Run a PowerShell script from inst/ps/ and return parsed JSON result
#'
#' Uses processx::run() with a bounded timeout and defensive status coercion
#' (matching run_cmd.R), so a hung script cannot freeze the R session.
#' @param script_name Filename of the .ps1 script.
#' @param ... Additional arguments passed to the script.
#' @param timeout Numeric. Seconds before the script is killed. Default 300.
#' @param verbose Logical. Stream output to the console.
#' @noRd
.run_ps <- function(script_name, ..., timeout = 300, verbose = TRUE) {
  ps_exe <- .find_powershell()
  if (!nzchar(ps_exe)) {
    stop(
      paste0(
        "PowerShell not found on PATH.\n",
        "  Install PowerShell 7+: https://aka.ms/powershell"
      ),
      call. = FALSE
    )
  }

  tmp_json <- tempfile(fileext = ".json")
  on.exit(unlink(tmp_json), add = TRUE)

  # processx passes args directly (no shell), so do NOT shQuote them here.
  ps_args <- c(
    "-NoProfile",
    "-NonInteractive",
    "-ExecutionPolicy", "Bypass",
    "-File",       .ps_script(script_name),
    ...,
    "-OutputJson", tmp_json
  )

  proc <- tryCatch(
    processx::run(
      command        = ps_exe,
      args           = ps_args,
      echo           = isTRUE(verbose),
      error_on_status = FALSE,
      timeout        = timeout
    ),
    error = function(e) {
      list(status = 124L, stdout = "", stderr = conditionMessage(e))
    }
  )

  status <- suppressWarnings(as.integer(proc$status))
  if (is.na(status)) status <- 1L

  if (!file.exists(tmp_json)) {
    return(NULL)
  }

  tryCatch(
    jsonlite::fromJSON(tmp_json, simplifyDataFrame = FALSE),
    error = function(e) NULL
  )
}

#' Split a command string on whitespace (simple, not full POSIX quoting)
#'
#' Intended only for commands with no quoted arguments. run_cmd() refuses
#' quoted strings and directs callers to the args= form; this helper does not
#' attempt to honor quotes.
#' @noRd
.split_cmd <- function(cmd) {
  parts <- trimws(strsplit(cmd, "\\s+")[[1]])
  parts[nzchar(parts)]
}

#' Split a raw string on newlines, dropping empty lines
#'
#' Canonical copy for the whole package. Handles CRLF and CR line endings.
#' @noRd
.split_lines <- function(x) {
  x <- x %||% ""
  if (!nzchar(x)) return(character(0))
  lines <- strsplit(x, "\r\n|\r|\n")[[1]]
  lines[nzchar(lines)]
}

#' Clean a data frame read from Excel
#'
#' Drops all-NA rows and columns and trims whitespace in character columns.
#' Uses a vectorized NA test rather than apply(df, 1, ...), which would coerce
#' the whole frame to a character matrix.
#' @noRd
.clean_excel_df <- function(df) {
  if (!is.data.frame(df) || nrow(df) == 0L || ncol(df) == 0L) return(df)

  keep_rows <- rowSums(!is.na(df)) > 0L
  df <- df[keep_rows, , drop = FALSE]

  keep_cols <- vapply(df, function(col) !all(is.na(col)), logical(1))
  df <- df[, keep_cols, drop = FALSE]

  df[] <- lapply(df, function(col) if (is.character(col)) trimws(col) else col)
  df
}
