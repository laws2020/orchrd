# =============================================================================
# R/log_step.R
# Make any workflow observable.
# log_step(), with_log(), log_config(), get_log()
#
# ASCII-ONLY: no smart quotes, em-dashes, arrows, or emoji in any comment,
# message, or string.
#
# BRACE-SAFE: message text is interpolated exactly once. Dynamic text
# (error messages, labels) is escaped so a literal { or } cannot be
# re-evaluated as a cli/glue template and crash the logger.
# =============================================================================

# ---- Session logger state ---------------------------------------------------
.orchrd_log         <- new.env(parent = emptyenv())
.orchrd_log$entries <- list()
.orchrd_log$level   <- "info"
.orchrd_log$sink    <- NULL
.orchrd_log$session <- NULL   # set by .new_session_id() below

.log_rank <- c(debug = 1L, info = 2L, warn = 3L, error = 4L)

# Double any { or } so cli/glue treats the text as literal.
.escape_braces <- function(x) gsub("([{}])", "\\1\\1", x)

# Unique-ish session id: time to the second plus pid + random suffix.
.new_session_id <- function() {
  paste0(
    format(Sys.time(), "%Y%m%d_%H%M%S"), "_",
    Sys.getpid(), "_",
    sprintf("%04d", sample.int(9999L, 1L))
  )
}

# Current minimum level, guarded against an invalid stored value.
.current_level <- function() {
  lvl <- .orchrd_log$level
  if (length(lvl) != 1L || is.na(lvl) || is.null(.log_rank[[lvl]])) "info" else lvl
}

# Initialize the session id on load.
.orchrd_log$session <- .new_session_id()


#' Log a workflow step
#'
#' Logs a message at a given severity level. Printed to the console via
#' `cli` and optionally written to an NDJSON log file configured by
#' [log_config()].
#'
#' Works anywhere: standalone in a script, inside [pipe_exec()] steps, or
#' inside any function you want to make observable.
#'
#' @param msg Character. The message. Supports cli inline markup and
#'   interpolation, e.g. `"Loaded {nrow(df)} rows"`. Interpolation happens
#'   exactly once, against the calling environment.
#' @param level Character. One of `"debug"`, `"info"` (default),
#'   `"warn"`, or `"error"`.
#' @param .data List. Optional structured data attached to the log entry.
#'   Written to the JSON file only, not printed to the console.
#'
#' @return Invisibly returns the log entry as a list.
#' @seealso [with_log()] to auto-log an entire block of code.
#'
#' @export
#' @examples
#' \dontrun{
#' log_step("Starting data fetch")
#' log_step("Cache miss - downloading fresh data", level = "warn")
#' log_step("Connection timed out", level = "error")
#' log_step("Loaded {nrow(df)} rows from {source}")
#' log_step("Fetch complete",
#'          .data = list(source = "endpoint_a", rows = nrow(df)))
#' }
log_step <- function(msg, level = "info", .data = NULL) {
  level <- match.arg(level, c("debug", "info", "warn", "error"))

  if (.log_rank[[level]] < .log_rank[[.current_level()]]) {
    return(invisible(NULL))
  }

  envir <- parent.frame()

  # Resolve interpolation ONCE. This is the single canonical message used
  # for both the console and the stored/entry text.
  resolved_msg <- tryCatch(
    {
      raw <- cli::cli_fmt(cli::cli_text(msg, .envir = envir))
      paste(raw, collapse = " ")
    },
    error = function(e) as.character(msg)
  )

  entry <- list(
    timestamp = format(Sys.time(), "%Y-%m-%dT%H:%M:%S"),
    session   = .orchrd_log$session,
    level     = level,
    message   = resolved_msg,
    data      = .data
  )

  # Print the already-resolved text as a literal (braces escaped) so cli
  # does NOT interpolate a second time.
  safe <- .escape_braces(resolved_msg)
  switch(
    level,
    debug = cli::cli_inform(c("*" = cli::col_grey(paste0("[debug] ", safe)))),
    info  = cli::cli_inform(c("i" = safe)),
    warn  = cli::cli_warn(safe),
    error = cli::cli_alert_danger(safe)
  )

  .orchrd_log$entries <- c(.orchrd_log$entries, list(entry))

  if (!is.null(.orchrd_log$sink)) {
    .append_log_line(entry, .orchrd_log$sink)
  }

  invisible(entry)
}


#' Execute an expression with automatic entry and exit logging
#'
#' Wraps a block of code with start and completion log messages, including
#' elapsed time. On error, logs the failure message before re-throwing.
#'
#' Drop `with_log("label", { ... })` around any block and it becomes fully
#' observable: timestamped, timed, and failure-safe, without touching the
#' logic inside.
#'
#' @param label Character. Description of the step shown in log messages.
#' @param expr An R expression or block `{ ... }`.
#' @param level Character. Log level for the start and done messages
#'   (default `"info"`).
#' @param .data List. Extra structured data attached to the log entries.
#'
#' @return The value of `expr`. Side effect: two log entries written,
#'   start and done (or failure) with elapsed time.
#' @seealso [log_step()] for single messages, [log_config()] to configure
#'   file output.
#'
#' @export
#' @examples
#' \dontrun{
#' df <- with_log("Fetch source data", {
#'   get_data("source")
#' })
#' }
with_log <- function(label = "step", expr, level = "info", .data = NULL) {
  expr_q <- substitute(expr)

  # label may contain braces; escape so it is treated as literal text.
  safe_label <- .escape_braces(as.character(label))

  log_step(
    paste0(safe_label, " - starting ..."),
    level = level,
    .data = .data
  )
  start <- proc.time()[["elapsed"]]

  result <- tryCatch(
    eval(expr_q, envir = parent.frame()),
    error = function(e) {
      elapsed <- round(proc.time()[["elapsed"]] - start, 3)
      # conditionMessage often contains braces -> escape before logging.
      log_step(
        paste0(safe_label, " - FAILED after ", elapsed, "s: ",
               .escape_braces(conditionMessage(e))),
        level = "error",
        .data = .data
      )
      stop(e)
    }
  )

  elapsed <- round(proc.time()[["elapsed"]] - start, 3)
  log_step(
    paste0(safe_label, " - done (", elapsed, "s)"),
    level = level,
    .data = .data
  )

  invisible(result)
}


#' Configure session-wide logging
#'
#' Sets the minimum log level and output file for the current session.
#' Call once at the top of a script or in `.Rprofile`.
#'
#' The log file format is NDJSON (newline-delimited JSON): one JSON object
#' per line, appended across the session. Readable by DuckDB, pandas, `jq`,
#' or any log aggregation tool.
#'
#' @param level Character. Minimum level to output. Messages below this
#'   level are silently dropped. One of `"debug"`, `"info"` (default),
#'   `"warn"`, `"error"`.
#' @param file Character. Path to the NDJSON log file. `NULL` = console
#'   only (default). The file is appended, not overwritten, unless
#'   `reset = TRUE`.
#' @param reset Logical. Clear the in-memory log and start a new session
#'   ID (default `FALSE`).
#'
#' @return Invisibly returns a list with the previous `level` and `file`.
#' @seealso [get_log()] to retrieve the in-memory log.
#'
#' @export
#' @examples
#' \dontrun{
#' log_config(level = "debug")
#' log_config(level = "info", file = "logs/session.json")
#' log_config(reset = TRUE, file = "logs/run_002.json")
#' }
log_config <- function(level = "info", file = NULL, reset = FALSE) {
  prev <- list(level = .orchrd_log$level, file = .orchrd_log$sink)

  .orchrd_log$level <- match.arg(level, c("debug", "info", "warn", "error"))

  if (!is.null(file)) {
    dir <- dirname(file)
    ok <- tryCatch(
      {
        if (nzchar(dir) && !dir.exists(dir)) {
          dir.create(dir, showWarnings = FALSE, recursive = TRUE)
        }
        TRUE
      },
      error = function(e) FALSE
    )
    if (!ok || (nzchar(dir) && !dir.exists(dir))) {
      stop(paste0("Cannot create log directory: ", dir), call. = FALSE)
    }
    .orchrd_log$sink <- file
  }

  if (reset) {
    .orchrd_log$entries <- list()
    .orchrd_log$session <- .new_session_id()
  }

  invisible(prev)
}


#' Retrieve the in-memory session log
#'
#' Returns all log entries written since the session started (or since the
#' last [log_config()] call with `reset = TRUE`) as a tidy data frame.
#'
#' @return A data frame with columns `timestamp`, `session`, `level`,
#'   `message`. Returns an empty (0-row) data frame with the same columns
#'   if nothing has been logged yet.
#' @seealso [log_config()] to write logs to a file.
#'
#' @export
#' @examples
#' \dontrun{
#' log_step("step one")
#' log_step("something suspicious", level = "warn")
#' df <- get_log()
#' df[df$level %in% c("warn", "error"), ]
#' }
get_log <- function() {
  empty <- data.frame(
    timestamp = character(),
    session   = character(),
    level     = character(),
    message   = character(),
    stringsAsFactors = FALSE
  )

  entries <- .orchrd_log$entries
  if (!length(entries)) return(empty)

  data.frame(
    timestamp = vapply(entries, function(e) e$timestamp %||% NA_character_, ""),
    session   = vapply(entries, function(e) e$session   %||% NA_character_, ""),
    level     = vapply(entries, function(e) e$level     %||% NA_character_, ""),
    message   = vapply(entries, function(e) e$message   %||% NA_character_, ""),
    stringsAsFactors = FALSE
  )
}

# ---- Internal ---------------------------------------------------------------

#' @noRd
.append_log_line <- function(entry, path) {
  line <- tryCatch(
    jsonlite::toJSON(entry, auto_unbox = TRUE, null = "null"),
    error = function(e) NULL
  )
  if (is.null(line)) return(invisible(NULL))

  # A failing sink must never abort the workflow it is observing.
  ok <- tryCatch(
    {
      cat(line, "\n", file = path, append = TRUE, sep = "")
      TRUE
    },
    error = function(e) FALSE
  )
  if (!ok) {
    # Warn once-ish; disable the sink so we do not spam on every call.
    .orchrd_log$sink <- NULL
    warning("Log sink write failed; file logging disabled for this session: ",
            path, call. = FALSE)
  }
  invisible(NULL)
}

# Local null-coalescing helper (avoids depending on rlang's %||% in scope).
`%||%` <- function(a, b) if (is.null(a)) b else a
