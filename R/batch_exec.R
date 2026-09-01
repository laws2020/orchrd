# =============================================================================
# R/batch_exec.R
# Controlled parallel execution in batches.
#
# Run a list of tasks N at a time until exhausted.
# Useful for fetching 54 country datasets without overwhelming the network,
# or running checks across many packages without maxing out CPU.
#
# WINDOWS SAFETY: matches the run_cmd.R / artifact.R fix - no
# cli::format_error() with named vectors inside stop(). Plain paste0() only,
# to avoid the recursive RAWSXP crash on Windows during error unwinding.
# All cli::* templates that interpolate task names or error text do so via
# {.val {var}} data slots so literal braces in messages can't be re-evaluated
# as glue templates.
#
# ASCII-only: no smart quotes, em-dashes, arrows, box-drawing, or emoji.
#
# Public API:
#   batch_exec(tasks, fn, batch_size, ...)  - process a list in parallel batches
# =============================================================================


#' Execute a list of tasks in controlled parallel batches
#'
#' Processes a list of inputs by applying a function to each. In
#' `"parallel"` mode, `batch_size` tasks run simultaneously via `run_bg()`
#' and are awaited with `await()`; when one batch completes, the next starts,
#' continuing until the full list is exhausted. In `"sequential"` mode tasks
#' run one at a time in the current session with progress tracking, and
#' `batch_size` is ignored.
#'
#' This is the right tool when you have more tasks than you want to run
#' simultaneously. Running all 54 country fetches at once would overwhelm
#' the network and the target servers. Running them one-by-one is too slow.
#' `batch_exec()` gives you a controlled middle ground.
#'
#' @param tasks A list or named character vector. Each element is one input
#'   to process.
#' @param fn A function that accepts one element of `tasks` and returns a
#'   result. Must be a plain R function (not a formula).
#' @param batch_size Integer. Maximum number of tasks to run simultaneously
#'   in `"parallel"` mode. Ignored in `"sequential"` mode. Default `4`.
#' @param mode Character. `"sequential"` (default) runs tasks one at a time
#'   in the current session with progress tracking. `"parallel"` runs
#'   `batch_size` tasks simultaneously as background jobs via `run_bg()`.
#'   Note: `"parallel"` requires `fn` (and everything it closes over) to be
#'   serialisable with [saveRDS()] - use `"sequential"` when `fn` closes over
#'   session variables, open connections, or external pointers.
#' @param on_error Character. `"collect"` (default) records failures and
#'   continues. `"stop"` halts on the first failure (killing any still-running
#'   jobs in the current batch first).
#' @param combine Logical. If `TRUE`, `rbind` the successful results that are
#'   data frames into a single data frame, returned as the `"combined"`
#'   attribute of the result list (and, when every successful result is a
#'   data frame, also accessible via [batch_combine()]). A `.task` column is
#'   added identifying the source task. Non-data-frame results are skipped
#'   with a warning. Default `FALSE`.
#' @param verbose Logical. Print batch progress (default `TRUE`).
#'
#' @return A named list with one element per task:
#'   \describe{
#'     \item{result}{The return value of `fn(task)`, or `NULL` on failure.}
#'     \item{ok}{Logical. Whether the task succeeded.}
#'     \item{error}{Character error message, or `NA` if successful.}
#'     \item{elapsed_sec}{Numeric. Time taken for this task. In `"parallel"`
#'       mode this is approximate wall time measured from when the job's
#'       await began, not the job's true run time.}
#'   }
#'   Names match the names of `tasks` (or `task_1`, `task_2`, ... if
#'   unnamed; duplicates are disambiguated with [make.unique()]). When
#'   `combine = TRUE`, the combined data frame is attached as the
#'   `"combined"` attribute.
#'
#' @seealso `run_bg()`, `await()`, [pipe_exec()], [batch_combine()]
#'
#' @export
#' @examples
#' \dontrun{
#' # Fetch country datasets - 4 at a time in parallel, combined into one df
#' countries <- c("NGA", "ZAF", "KEN", "GHA", "ETH", "EGY")
#'
#' results <- batch_exec(
#'   tasks      = countries,
#'   fn         = function(iso) get_data(iso),
#'   batch_size = 4,
#'   mode       = "parallel",
#'   combine    = TRUE
#' )
#'
#' combined <- attr(results, "combined")   # one data frame, with a .task column
#'
#' successes <- Filter(function(r) isTRUE(r$ok), results)
#' failures  <- Filter(function(r) !isTRUE(r$ok), results)
#' message(length(successes), " succeeded, ", length(failures), " failed")
#' }
batch_exec <- function(
    tasks,
    fn,
    batch_size = 4L,
    mode       = c("sequential", "parallel"),
    on_error   = c("collect", "stop"),
    combine    = FALSE,
    verbose    = TRUE
) {
  mode     <- match.arg(mode)
  on_error <- match.arg(on_error)

  if (!is.function(fn)) {
    stop("batch_exec() requires fn to be a function.", call. = FALSE)
  }

  if (!is.list(tasks)) tasks <- as.list(tasks)
  batch_size <- max(1L, as.integer(batch_size))

  # -- Robust, non-duplicating name assignment --------------------------------
  raw_names  <- names(tasks)
  if (is.null(raw_names)) raw_names <- rep("", length(tasks))
  empty      <- is.na(raw_names) | !nzchar(raw_names)
  raw_names[empty] <- paste0("task_", which(empty))
  task_names <- make.unique(raw_names, sep = "_")
  names(tasks) <- task_names

  n_tasks   <- length(tasks)
  n_batches <- ceiling(n_tasks / batch_size)

  if (verbose) {
    cli::cli_rule(
      left  = cli::style_bold("batch_exec"),
      right = paste0(n_tasks, " tasks | batch_size ", batch_size,
                     " | mode: ", mode)
    )
  }

  results        <- vector("list", n_tasks)
  names(results) <- task_names
  overall_start  <- proc.time()[["elapsed"]]

  # -- Sequential mode --------------------------------------------------------
  if (mode == "sequential") {
    for (i in seq_len(n_tasks)) {
      nm   <- task_names[i]
      task <- tasks[[i]]

      if (verbose) {
        cli::cli_progress_step("Task {i}/{n_tasks}: {.val {nm}}")
      }

      t_start <- proc.time()[["elapsed"]]
      result  <- tryCatch(
        list(result = fn(task), ok = TRUE, error = NA_character_),
        error = function(e) list(
          result = NULL,
          ok     = FALSE,
          error  = conditionMessage(e)
        )
      )
      result$elapsed_sec <- round(proc.time()[["elapsed"]] - t_start, 3)

      if (verbose) {
        if (result$ok) {
          cli::cli_progress_done()
        } else {
          cli::cli_progress_done(result = "failed")
          cli::cli_alert_warning("{.val {nm}}: {.val {result$error}}")
        }
      }

      results[[i]] <- result

      if (!result$ok && on_error == "stop") {
        stop(
          paste0(
            "batch_exec() halted at task ", i, " (", nm, "): ", result$error
          ),
          call. = FALSE
        )
      }
    }

  } else {
    # -- Parallel mode - run in batches of batch_size -------------------------
    batches <- split(
      seq_len(n_tasks),
      ceiling(seq_len(n_tasks) / batch_size)
    )

    fn_rds <- tempfile(fileext = ".rds")
    saveRDS(fn, fn_rds)
    on.exit(unlink(fn_rds), add = TRUE)

    fn_size_mb <- round(file.info(fn_rds)$size / 1024^2, 1)
    if (verbose && !is.na(fn_size_mb) && fn_size_mb > 50) {
      cli::cli_alert_warning(
        paste0("Serialised fn is large (", fn_size_mb, " MB). It closes over ",
               "big objects - consider trimming its environment.")
      )
    }

    for (b_idx in seq_along(batches)) {
      batch_indices <- batches[[b_idx]]
      n_in_batch    <- length(batch_indices)

      if (verbose) {
        cli::cli_inform(c(
          ">" = paste0(
            "Batch ", b_idx, "/", n_batches,
            " (", n_in_batch, " task(s)): ",
            paste(task_names[batch_indices], collapse = ", ")
          )
        ))
      }

      batch_jobs <- vector("list", n_in_batch)

      for (j in seq_len(n_in_batch)) {
        idx  <- batch_indices[j]
        nm   <- task_names[idx]
        task <- tasks[[idx]]

        tmp_rds    <- tempfile(fileext = ".rds")
        tmp_script <- tempfile(fileext = ".R")
        tmp_result <- tempfile(fileext = ".rds")

        saveRDS(task, tmp_rds)

        script_body <- paste0(
          'fn      <- readRDS("', fn_rds, '")\n',
          'task    <- readRDS("', tmp_rds, '")\n',
          'result <- tryCatch(\n',
          '  fn(task),\n',
          '  error = function(e) structure(list(message = conditionMessage(e)),\n',
          '                                class = "orchrd_bg_error")\n',
          ')\n',
          'saveRDS(result, "', tmp_result, '")\n'
        )
        writeLines(script_body, tmp_script)

        job <- tryCatch(
          run_bg(tmp_script, label = nm, verbose = FALSE),
          error = function(e) NULL
        )

        batch_jobs[[j]] <- list(
          job        = job,
          idx        = idx,
          nm         = nm,
          tmp_result = tmp_result,
          tmp_rds    = tmp_rds,
          tmp_script = tmp_script
        )
      }

      for (j in seq_len(n_in_batch)) {
        entry <- batch_jobs[[j]]
        idx   <- entry$idx
        nm    <- entry$nm

        t_start <- proc.time()[["elapsed"]]

        if (is.null(entry$job)) {
          result <- list(
            result      = NULL,
            ok          = FALSE,
            error       = "Failed to start background job",
            elapsed_sec = 0
          )
        } else {
          job_result <- tryCatch(
            await(entry$job, verbose = FALSE),
            error = function(e) list(ok = FALSE, stderr = conditionMessage(e))
          )

          bg_val <- tryCatch(
            if (file.exists(entry$tmp_result)) readRDS(entry$tmp_result) else NULL,
            error = function(e) NULL
          )

          if (!is.null(bg_val) && inherits(bg_val, "orchrd_bg_error")) {
            result <- list(
              result      = NULL,
              ok          = FALSE,
              error       = bg_val$message,
              elapsed_sec = round(proc.time()[["elapsed"]] - t_start, 3)
            )
          } else {
            result <- list(
              result      = bg_val,
              ok          = isTRUE(job_result$ok),
              error       = if (!isTRUE(job_result$ok)) {
                paste(job_result$stderr, collapse = " ")
              } else NA_character_,
              elapsed_sec = round(proc.time()[["elapsed"]] - t_start, 3)
            )
          }
        }

        for (f in c(entry$tmp_rds, entry$tmp_script, entry$tmp_result)) {
          tryCatch(unlink(f), error = function(e) NULL)
        }

        if (verbose) {
          icon <- if (result$ok) "[ok]" else "[x]"
          cli::cli_text("  {icon} {.val {nm}} ({result$elapsed_sec}s)")
        }

        results[[idx]] <- result

        if (!result$ok && on_error == "stop") {
          .batch_cleanup_jobs(batch_jobs, exclude = j)
          stop(
            paste0(
              "batch_exec() halted at task ", idx, " (", nm, "): ", result$error
            ),
            call. = FALSE
          )
        }
      }
    }
  }

  total_elapsed <- round(proc.time()[["elapsed"]] - overall_start, 2)
  n_ok     <- sum(vapply(results, function(r) isTRUE(r$ok), logical(1)))
  n_failed <- n_tasks - n_ok

  if (verbose) {
    cli::cli_rule()
    if (n_failed == 0L) {
      cli::cli_alert_success(
        "All {n_tasks} task(s) complete in {total_elapsed}s."
      )
    } else {
      cli::cli_alert_warning(
        "{n_ok} succeeded, {n_failed} failed. Total: {total_elapsed}s."
      )
    }
  }

  # -- combine = TRUE: rbind successful data-frame results ---------------------
  if (isTRUE(combine)) {
    combined <- batch_combine(results, verbose = verbose)
    attr(results, "combined") <- combined
  }

  invisible(results)
}


#' Row-bind the successful data-frame results of a batch_exec() run
#'
#' Collects every element of a `batch_exec()` result list whose task
#' succeeded and whose `result` is a data frame, adds a `.task` column
#' identifying the source task, and `rbind`s them into a single data frame.
#' Successful non-data-frame results are skipped with a warning.
#'
#' Column handling is tolerant: frames are aligned by name (union of all
#' columns), with missing columns filled with `NA`, so slightly divergent
#' schemas still combine.
#'
#' @param results A named list returned by [batch_exec()].
#' @param verbose Logical. Warn about skipped non-data-frame results
#'   (default `TRUE`).
#'
#' @return A single data frame with a leading `.task` column, or an empty
#'   data frame if there is nothing to combine.
#'
#' @seealso [batch_exec()]
#' @export
batch_combine <- function(results, verbose = TRUE) {
  ok_idx <- which(vapply(results, function(r) isTRUE(r$ok), logical(1)))
  if (length(ok_idx) == 0L) return(data.frame())

  nms     <- names(results)
  frames  <- list()
  skipped <- character()

  for (i in ok_idx) {
    val <- results[[i]]$result
    if (is.data.frame(val)) {
      val$.task <- if (!is.null(nms)) nms[i] else paste0("task_", i)
      # move .task to the front
      val <- val[c(".task", setdiff(names(val), ".task"))]
      frames[[length(frames) + 1L]] <- val
    } else if (!is.null(val)) {
      skipped <- c(skipped, if (!is.null(nms)) nms[i] else paste0("task_", i))
    }
  }

  if (verbose && length(skipped)) {
    cli::cli_alert_warning(
      "combine: skipped {length(skipped)} non-data-frame result(s): {.val {skipped}}"
    )
  }

  if (length(frames) == 0L) return(data.frame())

  # Align columns by union of names so divergent schemas still bind.
  all_cols <- Reduce(union, lapply(frames, names))
  frames <- lapply(frames, function(df) {
    missing <- setdiff(all_cols, names(df))
    for (m in missing) df[[m]] <- NA
    df[all_cols]
  })

  do.call(rbind, frames)
}


# -- Internal helper: kill/await leftover jobs on early stop ------------------
.batch_cleanup_jobs <- function(batch_jobs, exclude = integer()) {
  for (k in seq_along(batch_jobs)) {
    if (k %in% exclude) next
    entry <- batch_jobs[[k]]
    if (!is.null(entry$job)) {
      killed <- FALSE
      if (is.function(entry$job$kill)) {
        killed <- isTRUE(tryCatch({ entry$job$kill(); TRUE },
                                  error = function(e) FALSE))
      }
      if (!killed) {
        tryCatch(await(entry$job, verbose = FALSE), error = function(e) NULL)
      }
    }
    for (f in c(entry$tmp_rds, entry$tmp_script, entry$tmp_result)) {
      tryCatch(unlink(f), error = function(e) NULL)
    }
  }
}
