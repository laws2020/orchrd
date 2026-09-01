# =============================================================================
# R/retry.R
# Retry any expression with exponential backoff and jitter.
# One line replaces ten lines of manual loop code.
#
# WINDOWS SAFETY: matches run_cmd.R / artifact.R - plain paste0() inside
# stop(), never cli::format_error() with named vectors.
# ASCII-only: no smart quotes, em-dashes, arrows, or emoji.
# All cli::* templates interpolate error/label text via {.val {var}} data
# slots so literal braces in messages cannot be re-evaluated as glue.
# =============================================================================

#' Retry an expression on failure
#'
#' Wraps any R expression with automatic retry logic. Supports exponential
#' backoff, random jitter, a wait cap, and pattern-matched error conditions.
#'
#' Default behaviour: up to 3 attempts, wait doubles after each failure
#' (2s, 4s, 8s), with plus/minus 30 percent random jitter so parallel
#' callers do not hammer the same server simultaneously.
#'
#' @param expr An R expression to attempt.
#' @param times Integer. Maximum number of attempts (default 3).
#' @param wait Numeric. Base wait in seconds between attempts (default 2).
#'   With backoff = TRUE this doubles each time: wait, wait*2, wait*4, ...
#' @param backoff Logical. Double the wait after each failure (default TRUE).
#'   Set FALSE for a flat wait.
#' @param max_wait Numeric. Upper bound (seconds) on any single wait after
#'   backoff and jitter are applied (default 60). Prevents unbounded growth.
#' @param jitter Logical. Add plus/minus 30 percent random variation to the
#'   wait time (default TRUE). Prevents thundering-herd on shared endpoints.
#' @param on Character vector. Error message patterns that trigger a retry.
#'   NULL (default) retries on any error. When supplied, errors that match
#'   none of the patterns fail immediately without retrying. Patterns are
#'   treated as case-insensitive regular expressions.
#' @param silent Logical. Suppress retry messages (default FALSE).
#' @param finally An optional expression evaluated after all attempts
#'   regardless of success or failure. Use for cleanup.
#'
#' @return The value of expr on success. Throws the last error if all
#'   attempts are exhausted.
#'
#' @seealso [retry_labeled()] for a version that prints a descriptive label.
#'
#' @export
retry <- function(
    expr,
    times    = 3L,
    wait     = 2,
    backoff  = TRUE,
    max_wait = 60,
    jitter   = TRUE,
    on       = NULL,
    silent   = FALSE,
    finally  = NULL
) {
  expr_q    <- substitute(expr)
  finally_q <- substitute(finally)
  env       <- parent.frame()
  times     <- max(1L, as.integer(times))
  last_error <- NULL

  # Cleanup runs no matter what; a failing cleanup must not clobber the
  # original error - warn instead.
  on.exit({
    if (!is.null(finally_q)) {
      tryCatch(
        eval(finally_q, envir = env),
        error = function(e) {
          warning("retry() finally block failed: ",
                  conditionMessage(e), call. = FALSE)
        }
      )
    }
  })

  for (attempt in seq_len(times)) {

    result <- tryCatch(
      eval(expr_q, envir = env),
      error = function(e) {
        structure(e, class = c("orchrd_retry_error", class(e)))
      }
    )

    # ---- Success -----------------------------------------------------------
    if (!inherits(result, "orchrd_retry_error")) {
      if (attempt > 1L && !silent) {
        cli::cli_alert_success("Succeeded on attempt {.val {attempt}}.")
      }
      return(result)
    }

    last_error <- result
    err_msg    <- conditionMessage(result)

    # ---- Pattern check - fail fast if not a retryable error ---------------
    if (!is.null(on)) {
      matches <- any(vapply(on, function(pat) {
        isTRUE(tryCatch(
          grepl(pat, err_msg, ignore.case = TRUE),
          error = function(e) FALSE   # bad regex must not break retry
        ))
      }, logical(1)))
      if (!matches) {
        # Re-throw the ORIGINAL error without the synthetic class, so
        # downstream handlers are not misled.
        class(last_error) <- setdiff(class(last_error), "orchrd_retry_error")
        stop(last_error)
      }
    }

    if (attempt == times) break

    # ---- Compute wait ------------------------------------------------------
    wait_secs <- if (backoff) wait * (2 ^ (attempt - 1L)) else wait
    if (jitter) wait_secs <- wait_secs * stats::runif(1, 0.7, 1.3)
    wait_secs <- min(round(wait_secs, 1), max_wait)

    if (!silent) {
      cli::cli_alert_warning(
        "Attempt {.val {attempt}}/{.val {times}} failed: {.val {err_msg}}"
      )
      cli::cli_inform(c("i" = "Retrying in {.val {wait_secs}}s ..."))
    }

    Sys.sleep(wait_secs)
  }

  if (!silent) cli::cli_alert_danger("All {.val {times}} attempts failed.")

  # Plain paste0() inside stop() - never cli::format_error() with a named
  # vector (RAWSXP recursive-error crash on Windows).
  detail <- if (!is.null(last_error)) {
    paste0("\n  ", conditionMessage(last_error))
  } else ""
  stop(
    paste0("retry() exhausted ", times, " attempt(s):", detail),
    call. = FALSE
  )
}


#' Retry with a descriptive label
#'
#' Prints a label before the first attempt then delegates to [retry()].
#' Makes log output readable when multiple retried calls run inside the
#' same [pipe_exec()] pipeline.
#'
#' @param label Character. Label printed before the first attempt.
#' @inheritParams retry
#'
#' @return The value of expr on success.
#' @seealso [retry()]
#'
#' @export
retry_labeled <- function(
    label,
    expr,
    times    = 3L,
    wait     = 2,
    backoff  = TRUE,
    max_wait = 60,
    jitter   = TRUE,
    on       = NULL,
    silent   = FALSE,
    finally  = NULL
) {
  expr_q    <- substitute(expr)
  finally_q <- substitute(finally)
  env       <- parent.frame()

  if (!silent) cli::cli_inform(c(">" = "{.val {label}}"))

  # Forward by constructing a retry() call that carries the unevaluated
  # expr and finally, with the scalar args inlined by value. This avoids
  # the previous bquote() approach silently dropping parameters.
  call <- as.call(list(
    quote(retry),
    expr     = expr_q,
    times    = times,
    wait     = wait,
    backoff  = backoff,
    max_wait = max_wait,
    jitter   = jitter,
    on       = on,
    silent   = silent,
    finally  = finally_q
  ))
  eval(call, envir = env)
}
