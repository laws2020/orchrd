# ==============================================================================
# orchrd: R/safe_callback.R
# Callback error isolation (formerly tripwire GAP 5).
#
# WINDOWS SAFETY: plain paste0()/string concatenation inside stop()/warning(),
# never cli::format_error() with named vectors. ASCII-only: no smart quotes,
# em-dashes, arrows, or emoji.
# ------------------------------------------------------------------------------
# Every user-supplied watcher callback is wrapped here before it is handed to
# the C++ worker thread. A throwing callback must never propagate into that
# thread (undefined behaviour / silent crash).
#
# The wrapper:
#   1. Catches errors via tryCatch (unwinding is correct: stop the callback).
#   2. Catches warnings via withCallingHandlers (non-unwinding: the callback
#      keeps running after a warning, matching plain R semantics).
#   3. Logs failures via .tw_log().
#   4. Re-issues conditions on the main R thread (non-fatal).
#   5. Increments n_fired only when the callback did not error.
# ==============================================================================

#' @noRd
.tw_safe_callback <- function(id, callback) {
  force(id)
  force(callback)

  function(event, path) {
    result <- tryCatch(
      withCallingHandlers(
        {
          callback(event, path)
          "ok"
        },
        warning = function(w) {
          # Surface the warning but do NOT abort the callback body.
          warning(
            "[orchrd] Callback warning in watcher '", id, "' ",
            "(event=", event, "): ", conditionMessage(w),
            call. = FALSE
          )
          invokeRestart("muffleWarning")
        }
      ),
      error = function(e) {
        .tw_log(id, paste0("CALLBACK_ERROR:", conditionMessage(e)), path)
        warning(
          "[orchrd] Callback error in watcher '", id, "' ",
          "(event=", event, ", path=", path, "): ",
          conditionMessage(e),
          call. = FALSE
        )
        "error"
      }
    )

    # Count a firing only when the callback did not error.
    entry <- .tw_state$watchers[[id]]
    if (!is.null(entry) && !identical(result, "error")) {
      .tw_state$watchers[[id]]$n_fired <- (entry$n_fired %||% 0L) + 1L
    }

    invisible(result)
  }
}
