# =============================================================================
# R/with_rollback.R
# Rollback primitive for deployment workflows.
# If a step fails, undo what it did before the pipeline error propagates.
#
# WINDOWS SAFETY: matches run_cmd.R / artifact.R - plain paste0() inside
# stop(), never cli::format_error() with named vectors.
# ASCII-only: no smart quotes, em-dashes, arrows, or emoji.
# All cli::* templates interpolate error/label text via {.val {var}} data
# slots so literal braces in messages cannot be re-evaluated as glue.
# =============================================================================

#' Execute a step with an automatic rollback on failure
#'
#' Wraps a pipeline step with a rollback expression that runs if - and
#' only if - the step fails. If the step succeeds, the rollback is never
#' called. If the step fails, the rollback runs and then the error
#' propagates normally (so [pipe_exec()]'s `.on_error` logic still applies).
#'
#' Designed for deployment-style workflows where steps have side effects
#' that need to be undone if a later step fails. Common patterns:
#'
#' - Copy a file, rollback by deleting it
#' - Push a git tag, rollback by deleting the remote tag
#' - Deploy to a server, rollback by reverting to the previous version
#' - Write to a database, rollback by deleting the inserted rows
#'
#' If the rollback expression itself fails, its error is caught and
#' reported, but the *original* step error is always the one re-thrown,
#' so a failing rollback never masks the real cause.
#'
#' @param expr An R expression - the step to attempt.
#' @param rollback An R expression - what to run if `expr` fails.
#'   Run for its side effects only; its return value is discarded.
#'   `NULL` (the default) means there is nothing to undo.
#' @param label Character. Label for log messages. Defaults to an empty
#'   string (no label prefix).
#' @param verbose Logical. Log rollback activity (default `TRUE`).
#'
#' @return The value of `expr` if it succeeds. If `expr` fails, the
#'   rollback runs and then the original error is re-thrown.
#'
#' @seealso [deploy_step()], [pipe_exec()]
#'
#' @export
#' @examples
#' \dontrun{
#' pipe_exec(
#'   build = ~ with_rollback(
#'     build_package(),
#'     rollback = clean_build_dir(),
#'     label    = "build"
#'   ),
#'   deploy = ~ with_rollback(
#'     push_to_production(.x),
#'     rollback = revert_to_previous_release(),
#'     label    = "deploy"
#'   )
#' )
#' }
with_rollback <- function(
    expr,
    rollback = NULL,
    label    = "",
    verbose  = TRUE
) {
  if (!is.character(label) || length(label) != 1L || is.na(label)) {
    stop("label must be a single character string.", call. = FALSE)
  }
  if (!is.logical(verbose) || length(verbose) != 1L || is.na(verbose)) {
    stop("verbose must be a single TRUE or FALSE.", call. = FALSE)
  }

  expr_q     <- substitute(expr)
  rollback_q <- substitute(rollback)
  env        <- parent.frame()
  label_pfx  <- if (nzchar(label)) paste0("[", label, "] ") else ""

  # A rollback is "defined" only if the unevaluated expression is not the
  # literal NULL. (A variable that later evaluates to NULL is handled below.)
  has_rollback <- !is.null(rollback_q)

  tryCatch(
    eval(expr_q, envir = env),
    error = function(e) {
      err_msg <- conditionMessage(e)

      if (verbose) {
        cli::cli_alert_warning(
          "{label_pfx}Step failed: {.val {err_msg}}"
        )
      }

      if (has_rollback) {
        if (verbose) {
          cli::cli_inform(c("i" = "{label_pfx}Running rollback ..."))
        }

        rb_ok <- FALSE
        tryCatch(
          {
            rb_val <- eval(rollback_q, envir = env)
            # An expression that evaluates to NULL is treated as a no-op
            # rollback, which still counts as a clean rollback.
            rb_ok <- TRUE
          },
          error = function(rb_e) {
            rb_err <- conditionMessage(rb_e)
            cli::cli_alert_danger(
              "{label_pfx}Rollback itself failed: {.val {rb_err}}"
            )
          }
        )

        if (verbose && rb_ok) {
          cli::cli_alert_success("{label_pfx}Rollback complete.")
        }
      } else if (verbose) {
        cli::cli_inform(c("i" = "{label_pfx}No rollback defined."))
      }

      # Re-throw the ORIGINAL step error (never the rollback's) so that
      # pipe_exec()'s .on_error logic sees the true cause with its class
      # intact.
      stop(e)
    }
  )
}


#' Create a reversible deployment step
#'
#' A convenience wrapper around [with_rollback()] for the common pattern
#' where a deployment step writes something (a file, a tag, a remote
#' resource) and the rollback deletes it.
#'
#' @param deploy_expr The deployment expression.
#' @param revert_expr The revert (undo) expression. `NULL` means nothing
#'   to undo.
#' @param label Character. Label for log messages.
#' @param verbose Logical. Log rollback activity (default `TRUE`).
#'
#' @return The value of `deploy_expr` if it succeeds.
#' @seealso [with_rollback()]
#'
#' @export
#' @examples
#' \dontrun{
#' pipe_exec(
#'   upload = ~ deploy_step(
#'     deploy_expr = upload_to_server("data/out.parquet"),
#'     revert_expr = delete_from_server("data/out.parquet"),
#'     label       = "upload parquet"
#'   )
#' )
#' }
deploy_step <- function(
    deploy_expr,
    revert_expr = NULL,
    label       = "",
    verbose     = TRUE
) {
  deploy_q <- substitute(deploy_expr)
  revert_q <- substitute(revert_expr)
  env      <- parent.frame()

  # Forward by constructing a with_rollback() call that carries the
  # unevaluated deploy/revert expressions, with scalar args inlined by
  # value. Matches the retry_labeled() convention (no bquote()).
  call <- as.call(list(
    quote(with_rollback),
    expr     = deploy_q,
    rollback = revert_q,
    label    = label,
    verbose  = verbose
  ))
  eval(call, envir = env)
}
