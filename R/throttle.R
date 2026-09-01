# ==============================================================================
# orchrd: R/throttle.R
# throttle(): fire immediately, then suppress for N ms (formerly tripwire GAP 3).
#
# WINDOWS SAFETY: plain paste0()/string concatenation inside stop(), never
# cli::format_error() with named vectors. ASCII-only throughout.
# ------------------------------------------------------------------------------
# Debounce collapses a burst and fires at the END (trailing edge).
# Throttle fires on the FIRST event, then suppresses duplicates for `ms`.
#
# Contrast:
#   debounce  editor writes a file 10 times in 200 ms -> fire once at the end
#   throttle  rate file arrives -> fire immediately, ignore re-drops for 30s
#
# throttle() wraps an existing watcher's callback in place, exactly like
# guard(), so the two compose:
#   id <- on_arrive("~/cbn_feeds/", action = function(e, p) fetch_rates(p))
#   throttle(id, ms = 30000)
#   guard(id, condition = ~ net_ok(), message = "No network")
# ==============================================================================

#' Throttle a watcher's callback (fire-first, suppress for N ms)
#'
#' Wraps the existing callback so it fires immediately on the first event, then
#' suppresses subsequent firings for \code{ms} milliseconds. This is the
#' complement of the built-in debounce (which fires at the trailing edge).
#'
#' @param id Character. Watcher ID to throttle.
#' @param ms Numeric. Suppression window in milliseconds. Default \code{1000}.
#'
#' @return Invisibly \code{TRUE}.
#'
#' @seealso [guard()], [on_arrive()]
#'
#' @examples
#' \dontrun{
#' id <- on_arrive("~/cbn_feeds/", action = function(event, path) {
#'   fetch_cbn_rates(path)
#' })
#' throttle(id, ms = 30000)  # fire once, then ignore re-drops for 30s
#' }
#'
#' @export
throttle <- function(id, ms = 1000) {
  id <- as.character(id)
  ms <- as.numeric(ms)
  if (length(ms) != 1L || is.na(ms) || ms < 0) {
    stop("`ms` must be a single non-negative number.", call. = FALSE)
  }
  .tw_assert_exists(id)

  old_cb   <- .tw_state$watchers[[id]]$callback
  last_env <- new.env(parent = emptyenv())
  last_env$fired <- list()  # named list: "event:path" -> last-fire ms

  # Prune keys older than 10x the window so long-lived watchers do not grow
  # the map without bound.
  .prune <- function(now) {
    keep <- vapply(
      last_env$fired,
      function(t) (now - t) < (ms * 10),
      logical(1)
    )
    last_env$fired <- last_env$fired[keep]
  }

  new_cb <- function(event, path) {
    now      <- proc.time()[["elapsed"]] * 1000  # ms, monotonic-ish
    last_key <- paste0(event, ":", path)
    last_t   <- last_env$fired[[last_key]]

    if (!is.null(last_t) && (now - last_t) < ms) {
      .tw_log(id, paste0("THROTTLED:", event), path)
      return(invisible(NULL))
    }

    last_env$fired[[last_key]] <- now
    if (length(last_env$fired) > 1000L) .prune(now)
    old_cb(event, path)
  }

  .tw_state$watchers[[id]]$callback <- new_cb
  .tw_update_callback(id, new_cb)

  message("[orchrd] Throttle (", ms, "ms) attached to watcher '", id, "'")
  invisible(TRUE)
}
