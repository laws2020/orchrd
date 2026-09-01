# =============================================================================
# R/metrics.R
# Pipeline performance metrics.
#
# One function: pipeline_summary().
# Reads the NDJSON log file written by log_config(file=...) and/or the
# JSON run logs written by pipe_exec(.log_file=...) and aggregates
# performance across multiple runs.
#
# ASCII-only throughout: no smart quotes, em-dashes, arrows, or emoji.
# Brace-safe cli: all interpolation of paths/values/errors goes through
# {.path}/{.val} data slots so literal braces cannot re-trigger glue.
#
# Public API:
#   pipeline_summary(log_file, ...) - aggregate metrics across pipeline runs
# =============================================================================

# Local null-coalescing helper (delete if orchrd already exports one).
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a


#' Summarise pipeline performance across multiple runs
#'
#' Reads the log file(s) produced by [log_config()] and/or
#' [pipe_exec()] and returns a tidy summary of performance metrics
#' across runs: success rate, mean and total elapsed time, step-level
#' timing, and failure patterns.
#'
#' This is the function to call after a week of scheduled pipeline runs
#' to understand where time is spent and which steps fail most often.
#'
#' @param log_file Character. Path to an NDJSON session log written by
#'   [log_config()] with `file=`, OR a pipe_exec JSON run log written by
#'   [pipe_exec()] with `.log_file=`, OR a directory containing multiple
#'   such files. Multiple paths can be supplied as a character vector.
#' @param type Character. `"auto"` (default) detects each file's format;
#'   `"session"` forces NDJSON session logs; `"pipeline"` forces pipe_exec
#'   JSON run logs.
#' @param verbose Logical. Print summary to console (default `TRUE`).
#'
#' @return A named list with a stable shape (keys always present):
#'   `$runs`, `$success_rate`, `$elapsed`, `$steps`, `$errors`, `$raw`.
#'
#' @export
#' @examples
#' \dontrun{
#' pipeline_summary("logs/")
#' pipeline_summary(c("logs/run_2026_04_01.json", "logs/run_2026_04_02.json"),
#'                  type = "pipeline")
#' pipeline_summary("logs/session.json", type = "session")
#' }
pipeline_summary <- function(
    log_file,
    type    = c("auto", "session", "pipeline"),
    verbose = TRUE
) {
  type <- match.arg(type)

  # ---- Collect files ---------------------------------------------------------
  all_files <- character()
  for (path in log_file) {
    path <- normalizePath(path, mustWork = FALSE)
    if (dir.exists(path)) {
      found <- list.files(path, pattern = "\\.json$", full.names = TRUE)
      all_files <- c(all_files, found)
    } else if (file.exists(path)) {
      all_files <- c(all_files, path)
    } else {
      cli::cli_warn("File not found: {.path {path}}")   # brace-safe
    }
  }
  all_files <- unique(all_files)

  if (length(all_files) == 0L) {
    message("No log files found.")
    return(.empty_summary())
  }

  # ---- Classify and read files (read each file exactly once) -----------------
  pipeline_logs <- list()
  session_rows  <- list()

  for (f in all_files) {
    lines <- tryCatch(readLines(f, warn = FALSE), error = function(e) character())
    lines <- lines[nzchar(trimws(lines))]
    if (length(lines) == 0L) next

    detected <- .detect_log_type(lines)  # "pipeline", "session", or "unknown"

    want_pipeline <- (type == "auto" || type == "pipeline")
    want_session  <- (type == "auto" || type == "session")

    if (want_pipeline && detected == "pipeline") {
      parsed <- tryCatch(
        jsonlite::fromJSON(paste(lines, collapse = "\n"),
                           simplifyDataFrame = TRUE),
        error = function(e) NULL
      )
      if (!is.null(parsed)) pipeline_logs <- c(pipeline_logs, list(parsed))

    } else if (want_session && detected == "session") {
      rows <- lapply(lines, function(l) {
        tryCatch(jsonlite::fromJSON(l, simplifyDataFrame = TRUE),
                 error = function(e) NULL)
      })
      rows <- Filter(Negate(is.null), rows)
      if (length(rows) > 0L) session_rows <- c(session_rows, rows)
    }
  }

  # ---- Summarise pipeline run logs (preferred if present) --------------------
  if (length(pipeline_logs) > 0L) {
    return(.summarise_pipeline(pipeline_logs, verbose = verbose))
  }

  # ---- Summarise session NDJSON logs -----------------------------------------
  if (length(session_rows) > 0L) {
    return(.summarise_session(session_rows, verbose = verbose))
  }

  message("No readable log entries found in the supplied files.")
  .empty_summary()
}


# ---- Internal: stable empty return -----------------------------------------
#' @noRd
.empty_summary <- function() {
  invisible(list(
    runs         = 0L,
    success_rate = NA_real_,
    elapsed      = NULL,
    steps        = NULL,
    errors       = data.frame(error = character(), count = integer(),
                              stringsAsFactors = FALSE),
    raw          = NULL
  ))
}


# ---- Internal: structural format detection ---------------------------------
# Parse rather than string-match on key order. A pipe_exec run log is a single
# JSON object containing a "steps" element; a session log is one JSON object
# per line, each with "timestamp"/"level"/"message".
#' @noRd
.detect_log_type <- function(lines) {
  # Single-object pipeline run log?
  whole <- tryCatch(
    jsonlite::fromJSON(paste(lines, collapse = "\n"), simplifyVector = FALSE),
    error = function(e) NULL
  )
  if (!is.null(whole) && is.list(whole) && !is.null(whole[["steps"]])) {
    return("pipeline")
  }

  # NDJSON: first non-empty line parses to an object with session-y fields.
  first <- tryCatch(
    jsonlite::fromJSON(lines[[1]], simplifyVector = FALSE),
    error = function(e) NULL
  )
  if (!is.null(first) && is.list(first) &&
      any(c("timestamp", "level", "message") %in% names(first))) {
    return("session")
  }

  "unknown"
}


# ---- Internal: pipeline run-log summary ------------------------------------
#' @noRd
.summarise_pipeline <- function(pipeline_logs, verbose = TRUE) {
  n_runs    <- length(pipeline_logs)
  successes <- vapply(pipeline_logs, function(r) isTRUE(r$ok), logical(1))
  ok_rate   <- round(mean(successes) * 100, 1)

  elapsed_per_run <- vapply(pipeline_logs, function(r) {
    steps <- r$steps
    if (is.data.frame(steps) && "elapsed_sec" %in% names(steps)) {
      sum(steps$elapsed_sec, na.rm = TRUE)
    } else NA_real_
  }, numeric(1))
  elapsed_per_run <- elapsed_per_run[!is.na(elapsed_per_run)]

  elapsed_df <- if (length(elapsed_per_run)) {
    data.frame(
      mean_sec = round(mean(elapsed_per_run), 2),
      min_sec  = round(min(elapsed_per_run), 2),
      max_sec  = round(max(elapsed_per_run), 2)
    )
  } else {
    data.frame(mean_sec = NA_real_, min_sec = NA_real_, max_sec = NA_real_)
  }

  all_steps <- do.call(rbind, lapply(pipeline_logs, function(r) {
    steps <- r$steps
    if (is.data.frame(steps) && nrow(steps) > 0L) {
      steps$run_ok <- isTRUE(r$ok)
      steps
    } else NULL
  }))

  steps_summary <- if (!is.null(all_steps) && nrow(all_steps) > 0L &&
                       "step" %in% names(all_steps)) {
    has_status  <- "status" %in% names(all_steps)
    has_elapsed <- "elapsed_sec" %in% names(all_steps)
    step_names  <- unique(all_steps$step)
    do.call(rbind, lapply(step_names, function(s) {
      rows <- all_steps[all_steps$step == s, , drop = FALSE]
      data.frame(
        step         = s,
        runs         = nrow(rows),
        success_rate = if (has_status) {
          paste0(round(mean(rows$status == "ok", na.rm = TRUE) * 100, 0), "%")
        } else NA_character_,
        mean_sec     = if (has_elapsed) {
          round(mean(rows$elapsed_sec, na.rm = TRUE), 3)
        } else NA_real_,
        stringsAsFactors = FALSE
      )
    }))
  } else NULL

  all_errors <- unlist(lapply(pipeline_logs, function(r) {
    steps <- r$steps
    if (is.data.frame(steps) && "error" %in% names(steps)) {
      steps$error[!is.na(steps$error) & nzchar(steps$error)]
    } else character()
  }))

  errors_df <- if (length(all_errors) > 0L) {
    tbl <- sort(table(all_errors), decreasing = TRUE)
    data.frame(error = names(tbl), count = as.integer(tbl),
               stringsAsFactors = FALSE)
  } else {
    data.frame(error = character(), count = integer(), stringsAsFactors = FALSE)
  }

  if (verbose) {
    cli::cli_rule(left = cli::style_bold("Pipeline performance summary"))
    cli::cli_text(
      "Runs: {.val {n_runs}}  |  Success rate: {.val {ok_rate}}%  |  Mean elapsed: {.val {elapsed_df$mean_sec}}s"
    )
    if (!is.null(steps_summary)) {
      cli::cli_text("")
      cli::cli_text(cli::style_bold("Step timing:"))
      print(steps_summary, row.names = FALSE)
    }
    if (nrow(errors_df) > 0L) {
      cli::cli_text("")
      cli::cli_text(cli::style_bold("Top errors:"))
      print(utils::head(errors_df, 5), row.names = FALSE)
    }
  }

  invisible(list(
    runs         = n_runs,
    success_rate = ok_rate / 100,
    elapsed      = elapsed_df,
    steps        = steps_summary,
    errors       = errors_df,
    raw          = all_steps
  ))
}


# ---- Internal: session NDJSON summary --------------------------------------
#' @noRd
.summarise_session <- function(session_rows, verbose = TRUE) {
  df <- data.frame(
    timestamp = vapply(session_rows, function(r) r$timestamp %||% "", character(1)),
    level     = vapply(session_rows, function(r) r$level     %||% "", character(1)),
    message   = vapply(session_rows, function(r) r$message   %||% "", character(1)),
    session   = vapply(session_rows, function(r) r$session   %||% "", character(1)),
    stringsAsFactors = FALSE
  )

  level_counts <- table(df$level)
  n_sessions   <- length(unique(df$session[nzchar(df$session)]))
  if (n_sessions == 0L) n_sessions <- 1L
  n_err  <- as.integer(level_counts["error"] %||% 0L)
  n_warn <- as.integer(level_counts["warn"]  %||% 0L)

  if (verbose) {
    cli::cli_rule(left = cli::style_bold("Session log summary"))
    cli::cli_text(
      "Entries: {.val {nrow(df)}}  |  Sessions: {.val {n_sessions}}  |  Errors: {.val {n_err}}  |  Warnings: {.val {n_warn}}"
    )
  }

  invisible(list(
    runs         = n_sessions,
    success_rate = NA_real_,
    elapsed      = NULL,
    steps        = NULL,
    errors       = df[df$level %in% c("warn", "error"), , drop = FALSE],
    raw          = df
  ))
}
