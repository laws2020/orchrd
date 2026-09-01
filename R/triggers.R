# ==============================================================================
# orchrd: R/triggers.R
# High-level trigger API: fire_on() and the on_*() shorthands.
#
# These functions are the primary interface most users will touch. They wrap
# watch_dir()/watch_file() in opinionated, readable verbs.
#
# ASCII-only: no smart quotes, em-dashes, arrows, or emoji.
# ==============================================================================

#' Bind an action to a filesystem event
#'
#' The main trigger API. Declaratively describes: "when THIS event happens
#' to files matching THIS pattern in THIS location, run THIS action."
#'
#' @param event      Character. One of "arrive", "change", "leave", "rename",
#'                   or the raw equivalents "created", "modified", "deleted",
#'                   "renamed".
#' @param path       Character. Directory (or file) to watch.
#' @param action     A function accepting (event, path), OR a one-sided formula
#'                   ~ expr where .path and .event are available as bindings.
#' @param pattern    Optional regex for matching filenames. NULL matches all.
#' @param recursive  Watch subdirectories? Default FALSE.
#' @param debounce   Milliseconds debounce window. Default 500L.
#' @param id         Optional watcher ID.
#'
#' @return Invisibly returns the watcher ID.
#'
#' @seealso [on_arrive()], [on_change()], [on_leave()], [on_rename()],
#'   [watch_dir()], [watch_file()]
#'
#' @examples
#' \dontrun{
#' # Formula syntax - quick one-liners
#' fire_on("arrive", "~/nbs_drops/", pattern = "\\.xlsx$",
#'         action = ~ message("File arrived: ", .path))
#'
#' # Function syntax - full pipeline trigger
#' fire_on("arrive", "~/cbn_feeds/",
#'         action = function(event, path) {
#'           opennaijR::fetch("NGA", "inflation")
#'         })
#' }
#'
#' @export
fire_on <- function(event,
                    path,
                    action,
                    pattern   = NULL,
                    recursive = FALSE,
                    debounce  = 500L,
                    id        = NULL) {

  if (missing(path) || !is.character(path) || length(path) != 1L || !nzchar(path)) {
    stop("`path` must be a single non-empty character string.", call. = FALSE)
  }

  # Normalise friendly aliases (arrive/change/leave/rename) to canonical names.
  event <- .tw_normalise_event(event)

  # Accept a function OR a one-sided formula (~ expr) with .event/.path bound.
  callback <- .tw_as_callback(action)

  path_norm <- suppressWarnings(normalizePath(path, mustWork = FALSE))

  if (file.exists(path_norm) && !dir.exists(path_norm)) {
    watch_file(
      path     = path_norm,
      events   = event,
      callback = callback,
      debounce = debounce,
      id       = id
    )
  } else {
    watch_dir(
      path      = path_norm,
      pattern   = pattern,
      events    = event,
      callback  = callback,
      recursive = recursive,
      debounce  = debounce,
      id        = id
    )
  }
}

#' Trigger action when a file arrives (is created)
#'
#' Shorthand for `fire_on("arrive", ...)`.
#'
#' @inheritParams fire_on
#' @return Invisibly returns the watcher ID.
#' @seealso [fire_on()]
#' @export
on_arrive <- function(path, action, pattern = NULL,
                      recursive = FALSE, debounce = 500L, id = NULL) {
  fire_on("arrive", path = path, action = action, pattern = pattern,
          recursive = recursive, debounce = debounce, id = id)
}

#' Trigger action when a file is modified
#'
#' Shorthand for `fire_on("change", ...)`.
#'
#' @inheritParams fire_on
#' @return Invisibly returns the watcher ID.
#' @seealso [fire_on()]
#' @export
on_change <- function(path, action, pattern = NULL,
                      recursive = FALSE, debounce = 500L, id = NULL) {
  fire_on("change", path = path, action = action, pattern = pattern,
          recursive = recursive, debounce = debounce, id = id)
}

#' Trigger action when a file is deleted
#'
#' Shorthand for `fire_on("leave", ...)`.
#'
#' @inheritParams fire_on
#' @return Invisibly returns the watcher ID.
#' @seealso [fire_on()]
#' @export
on_leave <- function(path, action, pattern = NULL,
                     recursive = FALSE, debounce = 500L, id = NULL) {
  fire_on("leave", path = path, action = action, pattern = pattern,
          recursive = recursive, debounce = debounce, id = id)
}

#' Trigger action when a file is renamed
#'
#' Shorthand for `fire_on("rename", ...)`.
#'
#' @inheritParams fire_on
#' @return Invisibly returns the watcher ID.
#' @seealso [fire_on()]
#' @export
on_rename <- function(path, action, pattern = NULL,
                      recursive = FALSE, debounce = 500L, id = NULL) {
  fire_on("rename", path = path, action = action, pattern = pattern,
          recursive = recursive, debounce = debounce, id = id)
}

# ------------------------------------------------------------------------------
# Internal helpers
# ------------------------------------------------------------------------------

# Map friendly aliases to canonical event names used by the C++ layer.
#' @noRd
.tw_normalise_event <- function(event) {
  if (!is.character(event) || !length(event)) {
    stop("`event` must be a non-empty character vector.", call. = FALSE)
  }
  aliases <- c(
    arrive = "created", change = "modified",
    leave  = "deleted", rename = "renamed",
    created = "created", modified = "modified",
    deleted = "deleted", renamed = "renamed"
  )
  out <- aliases[tolower(trimws(event))]
  bad <- is.na(out)
  if (any(bad)) {
    stop("Unknown event alias(es): ", paste(event[bad], collapse = ", "), "\n",
         "  Use: arrive, change, leave, rename ",
         "(or: created, modified, deleted, renamed)",
         call. = FALSE)
  }
  unname(out)
}

# Convert a formula or function into a proper callback(event, path).
#' @noRd
.tw_as_callback <- function(action) {
  if (is.function(action)) {
    params <- formals(action)
    if (length(params) < 2L && !"..." %in% names(params)) {
      stop("`action` function must accept (event, path) - got only ",
           length(params), " argument(s).", call. = FALSE)
    }
    return(action)
  }

  if (inherits(action, "formula")) {
    if (length(action) != 2L) {
      stop("`action` formula must be one-sided, e.g. ~ message(.path)",
           call. = FALSE)
    }
    expr    <- action[[2L]]
    formenv <- environment(action) %||% parent.frame()

    # Evaluate in a fresh child env so .event/.path never leak into or clobber
    # the formula's own (often global) environment.
    return(function(event, path) {
      eval_env <- new.env(parent = formenv)
      eval_env$.event <- event
      eval_env$.path  <- path
      eval(expr, envir = eval_env)
    })
  }

  stop("`action` must be a function or a one-sided formula (~).", call. = FALSE)
}
