# ==============================================================================
# orchrd: R/watchers.R
# Core watcher registry and user-facing watch_* functions.
#
# Internal state lives in a private environment (.tw_state) so it persists for
# the lifetime of the R session without leaking into the global namespace.
#
# ASCII-only.
# ==============================================================================

# ------------------------------------------------------------------------------
# Internal state - do NOT export
# ------------------------------------------------------------------------------
.tw_state <- new.env(parent = emptyenv())
.tw_state$watchers  <- list()   # id -> watcher metadata list
.tw_state$log       <- list()   # chronological event log (capped)
.tw_state$counter   <- 0L       # monotonic ID counter
.tw_state$log_limit <- 1000L

# Quote an id for messages without relying on non-ASCII smart quotes.
#' @noRd
.q <- function(x) paste0("'", x, "'")

#' @noRd
.tw_next_id <- function() {
  .tw_state$counter <- .tw_state$counter + 1L
  paste0("tw_", .tw_state$counter)
}

#' @noRd
.tw_log <- function(id, event, path) {
  entry <- list(id = id, event = event, path = path, timestamp = Sys.time())
  .tw_state$log <- c(.tw_state$log, list(entry))
  n <- length(.tw_state$log)
  if (n > .tw_state$log_limit) {
    .tw_state$log <- .tw_state$log[(n - .tw_state$log_limit + 1L):n]
  }
  invisible(entry)
}

.tw_valid_events <- c("created", "modified", "deleted", "renamed")

#' @noRd
.tw_check_events <- function(events) {
  bad <- setdiff(events, .tw_valid_events)
  if (length(bad)) {
    stop("Unknown event type(s): ", paste(bad, collapse = ", "), "\n",
         "  Allowed: ", paste(.tw_valid_events, collapse = ", "),
         call. = FALSE)
  }
  invisible(events)
}

# Escape a literal string for safe use inside a regex.
#' @noRd
.tw_regex_escape <- function(x) {
  gsub("([.\\\\+*?\\[^\\]$(){}=!<>|:#/-])", "\\\\\\1", x, perl = TRUE)
}

#' Watch a directory for filesystem events
#'
#' Registers a native OS-level watcher (inotify on Linux,
#' ReadDirectoryChangesW on Windows, kqueue on macOS) that fires `callback`
#' whenever a matching file event occurs inside `path`.
#'
#' @param path       Character. Directory to watch. Normalised; must exist.
#' @param pattern    Optional regex applied to the filename (basename only).
#'                   NULL matches all files.
#' @param events     Character vector: any of "created", "modified",
#'                   "deleted", "renamed".
#' @param callback   A function accepting (event, path).
#' @param recursive  Logical. Watch subdirectories? Default FALSE.
#' @param debounce   Integer. Milliseconds debounce window. Default 500L.
#' @param id         Optional character ID. Auto-generated if NULL.
#'
#' @return Invisibly returns the watcher ID.
#' @seealso [watch_file()], [unwatch()], [fire_on()]
#'
#' @examples
#' \dontrun{
#' id <- watch_dir("~/nbs_drops/", pattern = "\\.xlsx$", events = "created",
#'   callback = function(event, path) message("New file: ", path))
#' }
#'
#' @export
watch_dir <- function(path,
                      pattern   = NULL,
                      events    = c("created", "modified"),
                      callback,
                      recursive = FALSE,
                      debounce  = 500L,
                      id        = NULL) {

  path <- normalizePath(path, mustWork = TRUE)
  .tw_check_events(events)

  if (missing(callback) || !is.function(callback)) {
    stop("`callback` must be a function with arguments (event, path).",
         call. = FALSE)
  }
  if (!is.null(pattern)) {
    tryCatch(
      grepl(pattern, ""),
      error = function(e) stop("Invalid `pattern` regex: ", conditionMessage(e),
                               call. = FALSE)
    )
  }

  id <- if (is.null(id)) .tw_next_id() else as.character(id)
  if (id %in% names(.tw_state$watchers)) {
    stop("A watcher with id ", .q(id), " already exists. ",
         "Use unwatch(", .q(id), ") first.", call. = FALSE)
  }

  debounce <- as.integer(debounce)

  # Gap 5: isolate callback errors from the C++ thread before registering.
  safe_cb <- .tw_safe_callback(id, callback)

  .tw_start_watcher(
    id = id, path = path, recursive = recursive, events = events,
    debounce = debounce, callback = safe_cb, pattern = pattern
  )

  .tw_state$watchers[[id]] <- list(
    id = id, type = "dir", path = path, pattern = pattern, events = events,
    recursive = recursive, debounce = debounce, callback = safe_cb,
    status = "active", created = Sys.time(), n_fired = 0L
  )

  message("[orchrd] Watching directory: ", path,
          if (!is.null(pattern)) paste0(" (pattern: ", pattern, ")"))
  invisible(id)
}

#' Watch a single file for filesystem events
#'
#' Convenience wrapper around [watch_dir()] that targets a specific file rather
#' than an entire directory.
#'
#' @param path      Character. Full path to the file to watch.
#' @param events    Character vector of event types. Default "modified".
#' @param callback  A function accepting (event, path).
#' @param debounce  Integer. Milliseconds debounce window. Default 500L.
#' @param id        Optional watcher ID.
#'
#' @return Invisibly returns the watcher ID.
#' @seealso [watch_dir()], [unwatch()]
#'
#' @examples
#' \dontrun{
#' watch_file("~/configs/pipeline.yml",
#'   callback = function(event, path) message("Config changed: ", path))
#' }
#'
#' @export
watch_file <- function(path,
                       events   = "modified",
                       callback,
                       debounce = 500L,
                       id       = NULL) {

  path     <- normalizePath(path, mustWork = TRUE)
  dir_path <- dirname(path)
  filename <- basename(path)
  # Match the filename literally.
  pattern  <- paste0("^", .tw_regex_escape(filename), "$")

  watch_dir(
    path = dir_path, pattern = pattern, events = events,
    callback = callback, recursive = FALSE, debounce = debounce, id = id
  )
}

#' Stop a watcher
#'
#' Terminates the background C++ thread associated with `id` and removes the
#' watcher from the registry.
#'
#' @param id Character. Watcher ID from [watch_dir()] or [watch_file()].
#' @return Invisibly TRUE on success, FALSE if no such watcher.
#' @seealso [unwatch_all()]
#' @export
unwatch <- function(id) {
  id <- as.character(id)
  if (!id %in% names(.tw_state$watchers)) {
    warning("No active watcher with id ", .q(id), ".", call. = FALSE)
    return(invisible(FALSE))
  }
  .tw_stop_watcher(id)
  .tw_state$watchers[[id]] <- NULL
  message("[orchrd] Stopped watcher: ", id)
  invisible(TRUE)
}

#' @noRd
.tw_cleanup_watchers <- function() {
  ids <- names(.tw_state$watchers)

  if (!length(ids)) {
    return(invisible(0L))
  }

  for (id in ids) {
    tryCatch(
      .tw_stop_watcher(id),
      error = function(e) invisible(NULL)
    )
  }

  .tw_state$watchers <- list()

  invisible(length(ids))
}


#' Stop all active watchers
#'
#' Stops every active watcher and removes all watcher registrations.
#'
#' @return Invisibly returns the number of watchers stopped.
#' @seealso [unwatch()]
#' @export
unwatch_all <- function() {
  ids <- names(.tw_state$watchers)

  if (!length(ids)) {
    message("[orchrd] No active watchers.")
    return(invisible(0L))
  }

  n <- .tw_cleanup_watchers()

  message("[orchrd] Stopped ", n, " watcher(s).")

  invisible(n)
}
