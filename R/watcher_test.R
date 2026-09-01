# ==============================================================================
# orchrd: R/watcher_test.R
# Dry-run / simulate a filesystem event on a watcher.
#
# watcher_test() directly invokes the watcher's current callback (including any
# guards and throttles composed on top of it) with a synthetic event and path,
# exactly as the C++ layer would - without touching the filesystem.
#
# ASCII-only.
# ==============================================================================

#' Simulate a filesystem event on a watcher (dry-run)
#'
#' Directly invokes the watcher's current callback with a synthetic event and
#' path, bypassing the C++ filesystem layer. All guards and throttles attached
#' to the watcher are evaluated as normal.
#'
#' @param id     Character. Watcher ID to test.
#' @param event  Character. Event type to simulate: "arrive"/"created",
#'               "change"/"modified", "leave"/"deleted", "rename"/"renamed".
#'               Default "created".
#' @param path   Character. Synthetic file path passed to the callback.
#'               Defaults to "<watcher_path>/test_event.tmp".
#' @param silent Logical. If TRUE, suppress the informational message printed
#'               before firing. Useful in testthat. Default FALSE.
#'
#' @return Invisibly returns the value returned by the callback, or NULL if the
#'   callback was blocked by a guard or raised an error.
#'
#' @seealso [schedule_test()], [fire_on()]
#'
#' @examples
#' \dontrun{
#' id <- on_arrive("~/nbs_drops/", action = function(event, path) {
#'   message("Pipeline triggered for: ", path)
#' })
#' watcher_test(id)
#' watcher_test(id, event = "created", path = "~/nbs_drops/q3_labour.xlsx")
#' }
#'
#' @export
watcher_test <- function(id,
                         event  = "created",
                         path   = NULL,
                         silent = FALSE) {

  id    <- as.character(id)
  event <- .tw_normalise_event(event)   # accept friendly aliases too

  w <- .tw_state$watchers[[id]]
  if (is.null(w)) {
    stop("No watcher with id ", .q(id), ". ",
         "Use watcher_list() to see active watchers.", call. = FALSE)
  }
  if (identical(w$type, "schedule")) {
    stop("watcher_test() does not apply to schedule watchers. ",
         "Use schedule_test() instead.", call. = FALSE)
  }
  if (!is.function(w$callback)) {
    stop("Watcher ", .q(id), " has no callable callback.", call. = FALSE)
  }

  synth_path <- if (!is.null(path)) as.character(path) else
    file.path(w$path, "test_event.tmp")

  if (!isTRUE(silent)) {
    message("[orchrd] watcher_test: firing '", event, "' on ", .q(id), "\n",
            "         synthetic path: ", synth_path)
  }

  result <- tryCatch(
    w$callback(event, synth_path),
    error = function(e) {
      message("[orchrd] watcher_test: callback raised an error: ",
              conditionMessage(e))
      NULL
    }
  )
  invisible(result)
}

#' Simulate a cron schedule firing immediately
#'
#' For schedule watchers created with [on_schedule()], fires the action
#' immediately regardless of the current time. Equivalent to [watcher_test()]
#' for filesystem watchers.
#'
#' @param id Character. Schedule watcher ID.
#'
#' @return Invisibly returns the value returned by the action, or NULL on error.
#' @seealso [watcher_test()], [on_schedule()]
#'
#' @examples
#' \dontrun{
#' id <- on_schedule("0 8 * * *", action = ~ message("Morning fetch!"))
#' schedule_test(id)  # fires immediately
#' }
#'
#' @export
schedule_test <- function(id) {
  id <- as.character(id)
  w  <- .tw_state$watchers[[id]]

  if (is.null(w)) {
    stop("No watcher/schedule with id ", .q(id), ".", call. = FALSE)
  }
  if (!identical(w$type, "schedule")) {
    stop(.q(id), " is a filesystem watcher. Use watcher_test() instead.",
         call. = FALSE)
  }
  if (!is.function(w$callback)) {
    stop("Schedule ", .q(id), " has no callable action.", call. = FALSE)
  }

  message("[orchrd] schedule_test: firing ", .q(id), " immediately.")

  result <- tryCatch(
    w$callback(),
    error = function(e) {
      message("[orchrd] schedule_test: action raised an error: ",
              conditionMessage(e))
      NULL
    }
  )
  invisible(result)
}
