# =============================================================================
# R/orchrd_bridge.R
# Integration seam between the tripwire watcher layer and the orchrd
# pipeline engine, both now living in the single orchrd package.
#
# tripwire detects that something happened; orchrd decides what to do.
# Because run_bg() / reload_config() are now local orchrd functions, there
# is no soft-dependency guard and no orchrd:: prefix.
#
# WINDOWS SAFETY: plain paste0()/string concatenation inside stop(), never
# cli::format_error() with named vectors. ASCII-only: no smart quotes,
# em-dashes, arrows, or emoji (status glyphs use \u2713/\u2717 escapes).
# =============================================================================


# =============================================================================
# pipe_on_arrive() - the primary watcher-to-pipeline integration point
# =============================================================================

#' Fire an orchrd pipeline when a file arrives
#'
#' Combines [on_arrive()] with [run_bg()] so that a complete pipeline is
#' dispatched in the background the moment a matching file lands in `path`.
#'
#' The file path is injected into the pipeline call as the named argument
#' `.file`, so your pipeline can optionally consume it.
#'
#' @param path      Directory to watch.
#' @param pipeline  A function (or orchrd pipeline object) to run.
#' @param pattern   Optional filename regex.
#' @param recursive Watch subdirectories? Default `FALSE`.
#' @param debounce  Milliseconds debounce. Default `500L`.
#' @param guard_fns Optional named list of zero-argument guard functions.
#'   All must return `TRUE` for the pipeline to fire.
#'   Example: `list(disk = disk_ok, net = net_ok)`.
#' @param id        Optional watcher ID.
#' @param ...       Additional arguments forwarded to [run_bg()].
#'
#' @return Invisibly returns the watcher ID.
#'
#' @seealso [pipe_on_change()], [on_arrive()], [run_bg()]
#'
#' @examples
#' \dontrun{
#' pipe_on_arrive(
#'   "~/nbs_drops/",
#'   pattern  = "\\.xlsx$",
#'   pipeline = function(.file) {
#'     opennaijR::fetch("NGA", "labour_force", file = .file)
#'   },
#'   guard_fns = list(disk = disk_ok, net = net_ok)
#' )
#' }
#'
#' @export
pipe_on_arrive <- function(path,
                           pipeline,
                           pattern   = NULL,
                           recursive = FALSE,
                           debounce  = 500L,
                           guard_fns = list(),
                           id        = NULL,
                           ...) {
  .validate_pipe_args(pipeline, guard_fns)
  dots <- list(...)

  callback <- function(event, file_path) {
    if (!.guards_pass(guard_fns, file_path, "pipe_on_arrive")) {
      return(invisible(NULL))
    }
    message("[orchrd] Dispatching pipeline for: ", file_path)
    do.call(run_bg, c(list(pipeline, .file = file_path), dots))
  }

  on_arrive(
    path      = path,
    action    = callback,
    pattern   = pattern,
    recursive = recursive,
    debounce  = debounce,
    id        = id
  )
}


# =============================================================================
# pipe_on_change()
# =============================================================================

#' Re-run an orchrd pipeline when a config or data file changes
#'
#' Useful for live-reloading a pipeline when its configuration file is edited.
#'
#' @inheritParams pipe_on_arrive
#'
#' @return Invisibly returns the watcher ID.
#'
#' @seealso [pipe_on_arrive()], [on_change()], [run_bg()]
#'
#' @examples
#' \dontrun{
#' pipe_on_change(
#'   "~/configs/pipeline.yml",
#'   pipeline = function(.file) reload_config(.file)
#' )
#' }
#'
#' @export
pipe_on_change <- function(path,
                           pipeline,
                           pattern   = NULL,
                           recursive = FALSE,
                           debounce  = 1000L,
                           guard_fns = list(),
                           id        = NULL,
                           ...) {
  .validate_pipe_args(pipeline, guard_fns)
  dots <- list(...)

  callback <- function(event, file_path) {
    if (!.guards_pass(guard_fns, file_path, "pipe_on_change")) {
      return(invisible(NULL))
    }
    message("[orchrd] Config changed - dispatching reload pipeline for: ",
            file_path)
    do.call(run_bg, c(list(pipeline, .file = file_path), dots))
  }

  on_change(
    path      = path,
    action    = callback,
    pattern   = pattern,
    recursive = recursive,
    debounce  = debounce,
    id        = id
  )
}


# =============================================================================
# health_report()
# =============================================================================

#' Run all built-in health checks and return a summary
#'
#' A quick system snapshot that can be embedded in a [health_check()]
#' pipeline or printed interactively.
#'
#' @param path   Path for disk check. Default `"."`.
#' @param host   Host for network ping. Default `"8.8.8.8"`.
#' @param min_mb Minimum free RAM in MB. Default `500`.
#'
#' @return A named logical vector: `disk`, `memory`, `network`. Prints a
#'   formatted summary as a side effect.
#'
#' @seealso [disk_ok()], [mem_ok()], [net_ok()]
#'
#' @export
health_report <- function(path = ".", host = "8.8.8.8", min_mb = 500) {
  checks <- c(
    disk    = isTRUE(disk_ok(path   = path)),
    memory  = isTRUE(mem_ok(min_mb  = min_mb)),
    network = isTRUE(net_ok(host    = host))
  )

  # \u2713 = check mark, \u2717 = ballot x (ASCII-safe escapes)
  symbols <- ifelse(checks, "\u2713", "\u2717")
  labels  <- c(
    sprintf("Disk       %s  (threshold: %.0f%%)", symbols[["disk"]],    90),
    sprintf("Memory     %s  (min free: %d MB)",   symbols[["memory"]],  as.integer(min_mb)),
    sprintf("Network    %s  (host: %s)",          symbols[["network"]], host)
  )

  cat("[orchrd] System Health\n",
      paste0("  ", labels, collapse = "\n"),
      "\n", sep = "")

  invisible(checks)
}


# =============================================================================
# Internal helpers
# =============================================================================

#' @noRd
.validate_pipe_args <- function(pipeline, guard_fns) {
  if (!is.function(pipeline) && !inherits(pipeline, "orchrd_pipeline")) {
    stop("`pipeline` must be a function or an orchrd_pipeline object.",
         call. = FALSE)
  }
  if (!is.list(guard_fns) ||
      (length(guard_fns) > 0L && is.null(names(guard_fns)))) {
    stop("`guard_fns` must be a named list of zero-argument functions.",
         call. = FALSE)
  }
  invisible(TRUE)
}

#' Evaluate all guards; return TRUE only if every guard passes.
#' Warns (ASCII-only) and returns FALSE on the first failing guard.
#' @noRd
.guards_pass <- function(guard_fns, file_path, where) {
  for (nm in names(guard_fns)) {
    ok <- tryCatch(isTRUE(guard_fns[[nm]]()), error = function(e) FALSE)
    if (!ok) {
      warning("[orchrd] ", where, ": guard '", nm,
              "' failed - not dispatched for: ", file_path,
              call. = FALSE)
      return(FALSE)
    }
  }
  TRUE
}
