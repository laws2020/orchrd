# =============================================================================
# R/pipe_exec.R
# Chain steps. Name them. Time them. Control errors. Log the run.
#
# WINDOWS SAFETY: matches run_cmd.R / artifact.R / batch_exec.R - plain
# paste0() inside stop()/warning(), never cli::format_error() with named
# vectors. All cli::* templates interpolate step names and error text via
# {.val {var}} data slots so literal braces in messages cannot be
# re-evaluated as glue templates.
# ASCII-only throughout: no smart quotes, em-dashes, arrows, or emoji.
#
# Public API:
#   pipe_exec(...)  - execute a named pipeline of steps sequentially
# =============================================================================

#' Execute a named pipeline of steps sequentially
#'
#' The core of `orchrd`. Each step receives the output of the previous step
#' as `.x`, logs progress, handles errors, and produces a structured result
#' you can inspect after the run.
#'
#' Steps are one-sided formulas (`~ expr`) or named formulas
#' (`name = ~ expr`). `.x` is the only special symbol - it holds the output
#' of the previous step.
#'
#' @param ... One-sided formulas, named formulas, or functions. Each is one
#'   step. Duplicate names are made unique with a numeric suffix.
#' @param .init Any. Initial value passed as `.x` to the first step.
#'   Default `NULL`.
#' @param .on_error One of:
#'   \describe{
#'     \item{`"stop"`}{(default) Halt on first failure.}
#'     \item{`"warn"`}{Log the failure, pass the previous `.x` through,
#'       keep going.}
#'     \item{`"skip"`}{Silently keep going with the previous `.x`.}
#'   }
#' @param .log Logical. Print step progress to the console (default `TRUE`).
#' @param .log_file Character. Write a JSON run log to this path. Created
#'   or overwritten each run. `NULL` (default) disables file logging.
#'
#' @return An S3 object of class `orchrd_pipeline`:
#'   \describe{
#'     \item{`$result`}{The final step's output value.}
#'     \item{`$ok`}{Logical. `TRUE` if all steps succeeded.}
#'     \item{`$steps`}{Data frame: `step`, `status`, `elapsed_sec`, `error`.}
#'     \item{`$log`}{List of raw per-step detail.}
#'     \item{`$elapsed_sec`}{Total wall time across all steps.}
#'   }
#'
#' @export
#' @examples
#' \dontrun{
#' pipe_exec(
#'   fetch  = ~ get_data("source"),
#'   clean  = ~ remove_na(.x),
#'   export = ~ save_parquet(.x, "out.parquet")
#' )
#'
#' pipe_exec(
#'   .init = "NGA",
#'   fetch = ~ get_data(.x),
#'   clean = ~ remove_na(.x)
#' )
#'
#' pipe_exec(
#'   a = ~ get_data("source_a"),
#'   b = ~ get_data("source_b"),
#'   .on_error = "warn"
#' )
#'
#' out <- pipe_exec(
#'   fetch = ~ get_data("source"),
#'   clean = ~ remove_na(.x)
#' )
#' out$ok
#' out$result
#' out$steps
#' }
pipe_exec <- function(
    ...,
    .init     = NULL,
    .on_error = c("stop", "warn", "skip"),
    .log      = TRUE,
    .log_file = NULL
) {
  .on_error <- match.arg(.on_error)
  steps     <- rlang::list2(...)

  if (length(steps) == 0L) {
    cli::cli_warn("pipe_exec() called with no steps.")
    return(invisible(.new_pipeline(NULL, list(), TRUE, 0)))
  }

  # Fix #6: fill blank names, then make.unique() so lookups stay unambiguous.
  step_names <- names(steps)
  if (is.null(step_names)) step_names <- rep("", length(steps))
  blank <- !nzchar(step_names)
  step_names[blank] <- paste0("step_", seq_along(steps))[blank]
  step_names <- make.unique(step_names, sep = "_")
  names(steps) <- step_names

  # Fix #5: validate every step up front. An invalid step is a programming
  # error and must fail loudly, not be caught by the per-step handler.
  step_fns <- lapply(seq_along(steps), function(i) {
    fn <- tryCatch(.step_to_fn(steps[[i]]), error = function(e) NULL)
    if (is.null(fn)) {
      stop(
        paste0(
          "pipe_exec() step ", i, " (", step_names[i],
          ") must be a one-sided formula (~ expr) or a function."
        ),
        call. = FALSE
      )
    }
    fn
  })

  if (.log) {
    cli::cli_rule(
      left  = cli::style_bold("orchrd pipeline"),
      right = paste0(length(steps), " steps")
    )
  }

  pipeline_start <- proc.time()[["elapsed"]]
  current        <- .init
  log_entries    <- vector("list", length(steps))
  all_ok         <- TRUE

  for (i in seq_along(steps)) {
    nm <- step_names[i]
    fn <- step_fns[[i]]

    if (.log) {
      cli::cli_progress_step("Step {i}/{length(steps)}: {.val {nm}}")
    }

    step_start <- proc.time()[["elapsed"]]
    entry <- list(
      name        = nm,
      status      = "ok",
      elapsed_sec = NA_real_,
      error       = NA_character_
    )

    result <- tryCatch(
      fn(current),
      error = function(e) {
        structure(
          list(message = conditionMessage(e)),
          class = "orchrd_step_error"
        )
      }
    )

    entry$elapsed_sec <- round(proc.time()[["elapsed"]] - step_start, 3)

    if (inherits(result, "orchrd_step_error")) {
      all_ok       <- FALSE
      entry$status <- "error"
      entry$error  <- result$message

      if (.log) {
        cli::cli_progress_done(result = "failed")
        # Fix #2: error text goes through a data slot, never a glue template.
        cli::cli_alert_danger("Step {.val {nm}} failed: {.val {result$message}}")
      }

      log_entries[[i]] <- entry

      if (.on_error == "stop") {
        elapsed  <- round(proc.time()[["elapsed"]] - pipeline_start, 3)
        pipeline <- .new_pipeline(current, log_entries[seq_len(i)], FALSE, elapsed)
        .write_pipeline_log(pipeline, .log_file)
        # Fix #1: plain paste0() inside stop(), no cli::format_error().
        stop(
          paste0(
            "Pipeline stopped at step ", i, " (", nm, "): ",
            result$message,
            "\n  Use .on_error = \"skip\" to continue past failures."
          ),
          call. = FALSE
        )
      } else if (.on_error == "warn") {
        # Fix #1/#2: plain paste0() inside warning(), no glue re-parse.
        warning(
          paste0("Step ", nm, " failed: ", result$message),
          call. = FALSE
        )
      }
      # "skip": current stays unchanged, no message.

    } else {
      current <- result
      if (.log) {
        cli::cli_progress_done()
      }
    }

    log_entries[[i]] <- entry
  }

  pipeline_elapsed <- round(proc.time()[["elapsed"]] - pipeline_start, 3)

  if (.log) {
    if (all_ok) {
      cli::cli_rule()
      cli::cli_alert_success(
        "Pipeline complete in {pipeline_elapsed}s - all {length(steps)} step(s) passed."
      )
    } else {
      n_failed <- sum(vapply(
        log_entries,
        function(e) identical(e$status, "error"),
        logical(1)
      ))
      cli::cli_alert_warning(
        "Pipeline finished in {pipeline_elapsed}s - {n_failed} step(s) had errors."
      )
    }
  }

  pipeline <- .new_pipeline(current, log_entries, all_ok, pipeline_elapsed)
  .write_pipeline_log(pipeline, .log_file)

  invisible(pipeline)
}

# ---- Internals --------------------------------------------------------------

#' @noRd
.new_pipeline <- function(result, log, ok, elapsed_sec = NA_real_) {
  steps_df <- if (length(log)) {
    data.frame(
      step        = vapply(log, `[[`, "", "name"),
      status      = vapply(log, `[[`, "", "status"),
      elapsed_sec = vapply(log, function(e) e$elapsed_sec %||% NA_real_, numeric(1)),
      error       = vapply(log, function(e) e$error %||% NA_character_, character(1)),
      stringsAsFactors = FALSE
    )
  } else {
    data.frame(
      step        = character(),
      status      = character(),
      elapsed_sec = numeric(),
      error       = character(),
      stringsAsFactors = FALSE
    )
  }
  structure(
    list(
      result      = result,
      ok          = ok,
      steps       = steps_df,
      log         = log,
      elapsed_sec = elapsed_sec
    ),
    class = "orchrd_pipeline"
  )
}

#' @noRd
.step_to_fn <- function(step) {
  if (rlang::is_formula(step)) {
    rlang::as_function(step)
  } else if (is.function(step)) {
    step
  } else {
    stop("Pipeline steps must be formulas (~ expr) or functions.", call. = FALSE)
  }
}

#' @noRd
.write_pipeline_log <- function(pipeline, path) {
  if (is.null(path) || !nzchar(path %||% "")) return(invisible(NULL))

  # Fix #7: never let a logging failure abort the pipeline; write atomically.
  ok <- tryCatch({
    dir.create(dirname(path), showWarnings = FALSE, recursive = TRUE)
    tmp <- tempfile(tmpdir = dirname(path), fileext = ".json")
    jsonlite::write_json(
      list(
        timestamp   = format(Sys.time(), "%Y-%m-%dT%H:%M:%S"),
        ok          = pipeline$ok,
        elapsed_sec = pipeline$elapsed_sec,
        steps       = pipeline$steps
      ),
      path       = tmp,
      pretty     = TRUE,
      auto_unbox = TRUE
    )
    file.rename(tmp, path) || file.copy(tmp, path, overwrite = TRUE)
  }, error = function(e) FALSE)

  if (!isTRUE(ok)) {
    cli::cli_warn("Could not write pipeline log to {.path {path}}.")
  }
  invisible(NULL)
}

#' @export
print.orchrd_pipeline <- function(x, ...) {
  cli::cli_rule(left = cli::style_bold("orchrd_pipeline"))
  icon <- if (isTRUE(x$ok)) "[OK]" else "[FAIL]"
  cli::cli_text("{icon} ok = {x$ok}  ({x$elapsed_sec %||% NA}s)")
  cli::cli_text("")
  print(x$steps, row.names = FALSE)
  invisible(x)
}
