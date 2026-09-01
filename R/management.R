
# -----------------------------------------------------------------------------
# Internal watcher validation helper
# -----------------------------------------------------------------------------
.tw_assert_exists <- function(id) {
  if (!(id %in% .tw_state$watchers)) {
    stop("[orchrd] Watcher does not exist: ", id, call. = FALSE)
  }

  invisible(TRUE)
}


#' @noRd
.tw_assert_exists <- function(id) {
  id <- as.character(id)

  if (!(id %in% names(.tw_state$watchers))) {
    stop(
      "[orchrd] Watcher does not exist: ",
      id,
      call. = FALSE
    )
  }

  invisible(TRUE)
}
