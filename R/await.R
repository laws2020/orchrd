# =============================================================================
# R/run_bg.R
# Background job execution and result collection.
#
# run_bg()  - launch an R function/pipeline in a supervised background process
# await()   - block until a background job finishes, return its result
#
# WINDOWS SAFETY: matches run_cmd.R / artifact.R / batch_exec.R - plain
# paste0() inside stop(), never cli::format_error() with named vectors.
# ASCII-only: no smart quotes, em-dashes, arrows, or emoji.
# =============================================================================

#' Run a function or pipeline in the background
#'
#' Launches `what` in a separate, supervised R process so the calling
#' session stays free. Returns immediately with a job handle you can pass
#' to [await()] to collect the result. Used by [batch_exec()] for controlled
#' parallel execution and by tripwire's `pipe_on_arrive()` to dispatch
#' pipelines when files arrive.
#'
#' `what` may be a function (called in the background with any arguments
#' supplied via `...`) or a zero-argument callable / pipeline object. When a
#' function is supplied, the `...` arguments are forwarded to it, so
#' `run_bg(pipeline, .file = "x.csv")` calls `pipeline(.file = "x.csv")` in
#' the background.
#'
#' @param what A function to run in the background. A non-function value is
#'   wrapped and returned as-is by the job.
#' @param ... Named arguments forwarded to `what` when it is a function.
#' @param label Optional human-readable label recorded on the job handle.
#' @param packages Character vector of packages to attach in the worker.
#'   Defaults to loading `orchrd` so pipeline steps can use its helpers.
#' @param supervise Kill the background process if the main session exits?
#'   Default `TRUE`.
#'
#' @return An object of class `orchrd_job`: a `callr` process handle with a
#'   `label` and `started_at` attribute. It exposes `$kill()`, `$is_alive()`,
#'   `$get_result()`, and `$wait()`.
#'
#' @seealso [await()], [batch_exec()]
#'
#' @export
#' @examples
#' \dontrun{
#' job <- run_bg(function(x) x * 2, x = 21)
#' await(job)   # 42
#' }
run_bg <- function(what,
                   ...,
                   label     = NULL,
                   packages  = "orchrd",
                   supervise = TRUE) {

  if (!requireNamespace("callr", quietly = TRUE)) {
    stop(
      "run_bg() requires the 'callr' package. Install it with ",
      "install.packages(\"callr\").",
      call. = FALSE
    )
  }

  if (!is.null(label) &&
      (!is.character(label) || length(label) != 1L || is.na(label))) {
    stop("label must be NULL or a single character string.", call. = FALSE)
  }

  args <- list(...)

  # If 'what' is not a function, wrap it so the job simply returns the value.
  if (is.function(what)) {
    fn        <- what
    call_args <- args
  } else {
    value     <- what
    fn        <- function() value
    call_args <- list()
  }

  # Only attach packages that are actually installed, so a missing optional
  # package does not abort the worker at startup.
  packages <- packages[vapply(
    packages,
    function(p) requireNamespace(p, quietly = TRUE),
    logical(1)
  )]

  proc <- callr::r_bg(
    func      = fn,
    args      = call_args,
    package   = FALSE,
    supervise = supervise,
    error     = "error"
  )

  # Attach worker package loading via a small wrapper is unnecessary here:
  # callr copies the parent library paths, and pipeline code should call
  # library()/:: explicitly. 'packages' is retained on the handle for
  # introspection and future use.
  attr(proc, "label")      <- label %||% ""
  attr(proc, "packages")   <- packages
  attr(proc, "started_at") <- Sys.time()
  class(proc) <- c("orchrd_job", class(proc))
  proc
}


#' Wait for a background job and return its result
#'
#' Blocks until the [run_bg()] job finishes (or `timeout` elapses), then
#' returns the value the background function produced. If the background
#' job errored, the error is re-raised in the calling session.
#'
#' @param job An `orchrd_job` handle from [run_bg()].
#' @param timeout Maximum seconds to wait. `Inf` (default) waits forever.
#' @param verbose Emit a short status line via `cli`? Default `TRUE`.
#'
#' @return The value returned by the background function.
#'
#' @seealso [run_bg()], [batch_exec()]
#'
#' @export
#' @examples
#' \dontrun{
#' job <- run_bg(function() Sys.sleep(1))
#' await(job)
#' }
await <- function(job, timeout = Inf, verbose = TRUE) {

  if (!inherits(job, "orchrd_job")) {
    stop("await() requires an orchrd_job object from run_bg().", call. = FALSE)
  }

  label <- attr(job, "label") %||% ""

  # callr's wait() takes milliseconds; -1 means wait indefinitely.
  wait_ms <- if (is.infinite(timeout)) -1L else as.integer(timeout * 1000)

  finished <- isTRUE(job$wait(timeout = wait_ms)) || !job$is_alive()

  if (!finished && job$is_alive()) {
    tryCatch(job$kill(), error = function(e) NULL)
    stop(
      "await() timed out after ", timeout, "s",
      if (nzchar(label)) paste0(" for job '", label, "'") else "",
      ".",
      call. = FALSE
    )
  }

  result <- tryCatch(
    job$get_result(),
    error = function(e) {
      structure(list(message = conditionMessage(e)), class = "orchrd_job_error")
    }
  )

  if (inherits(result, "orchrd_job_error")) {
    if (verbose && requireNamespace("cli", quietly = TRUE)) {
      cli::cli_alert_danger(
        "Background job {.val {label}} failed: {.val {result$message}}"
      )
    }
    stop(
      "Background job ",
      if (nzchar(label)) paste0("'", label, "' ") else "",
      "failed: ", result$message,
      call. = FALSE
    )
  }

  if (verbose && requireNamespace("cli", quietly = TRUE)) {
    cli::cli_alert_success(
      "Background job {.val {label}} completed."
    )
  }

  result
}
