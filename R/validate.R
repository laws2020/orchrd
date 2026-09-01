# =============================================================================
# R/validate.R
# Inline data validation for pipelines.
#
# WINDOWS SAFETY: matches run_cmd.R / artifact.R - plain paste0() inside
# stop(), never cli::format_error() with named vectors.
# ASCII-only: no smart quotes, em-dashes, arrows, or emoji.
# All cli::* templates interpolate values via {.val {var}} data slots so
# literal braces in column names or messages cannot be re-evaluated as glue.
#
# Public API:
#   validate_data(data, ...)          - run multiple assertions, collect all failures
#   assert_schema(data, cols)         - required columns must exist
#   assert_range(data, col, min, max) - numeric column within bounds
#   assert_no_na(data, cols)          - no missing values in specified columns
# =============================================================================


#' Run multiple validation assertions on a data frame
#'
#' Runs any combination of [assert_schema()], [assert_range()], and
#' [assert_no_na()] against a data frame and collects every failure before
#' stopping. This gives you a complete picture of what is wrong rather than
#' halting on the first problem.
#'
#' IMPORTANT: each rule must be a one-sided formula (`~ expr`) so that its
#' evaluation is deferred until inside `validate_data()`. If you pass a bare
#' `assert_*()` call (not wrapped in `~`), R evaluates it eagerly at the call
#' site and it will halt on the first failure instead of collecting all of
#' them. `validate_data()` warns if it detects a pre-evaluated argument.
#'
#' @param data A data frame to validate.
#' @param ... Named one-sided formulas (`name = ~ expr`). Each expression
#'   should call [assert_schema()], [assert_range()], [assert_no_na()], or
#'   return `TRUE` on success and throw on failure. Use `.x` (or `data`) to
#'   refer to the data frame inside each formula.
#' @param verbose Logical. Print a pass message if all checks succeed
#'   (default `TRUE`).
#'
#' @return The `data` argument invisibly if all checks pass. Throws an
#'   error listing every failed check if any fail.
#'
#' @seealso [assert_schema()], [assert_range()], [assert_no_na()]
#'
#' @export
#' @examples
#' \dontrun{
#' pipe_exec(
#'   fetch    = ~ get_data("source"),
#'
#'   validate = ~ validate_data(.x,
#'     schema = ~ assert_schema(.x, c("country", "year", "value")),
#'     ranges = ~ assert_range(.x,  "value", min = 0, max = 1000),
#'     nas    = ~ assert_no_na(.x,  c("country", "year"))
#'   ),
#'
#'   export   = ~ save_output(.x, "data/out.parquet")
#' )
#' }
validate_data <- function(data, ..., verbose = TRUE) {
  if (!is.data.frame(data)) {
    stop("validate_data() requires a data frame.", call. = FALSE)
  }

  checks   <- list(...)
  failures <- character()

  for (i in seq_along(checks)) {
    nm    <- names(checks)[i]
    if (is.null(nm) || !nzchar(nm)) nm <- paste0("check_", i)
    check <- checks[[i]]

    if (!rlang::is_formula(check) && !is.function(check)) {
      # Pre-evaluated argument: it already ran (and passed, or we would not
      # be here). Warn so the user knows this rule cannot collect failures.
      cli::cli_warn(c(
        "!" = "Rule {.val {nm}} was passed pre-evaluated, not as a formula.",
        "i" = "Wrap it as {.code {nm} = ~ assert_...(.x, ...)} so failures can be collected."
      ))
      next
    }

    result <- tryCatch({
      fn <- if (rlang::is_formula(check)) rlang::as_function(check) else check
      fn(data)
      NULL    # NULL means pass
    }, error = function(e) conditionMessage(e))

    if (!is.null(result)) {
      failures <- c(failures, paste0("[", nm, "] ", result))
    }
  }

  if (length(failures) > 0L) {
    stop(
      paste0(
        "validate_data() found ", length(failures), " failure(s):\n",
        paste0("  x ", failures, collapse = "\n")
      ),
      call. = FALSE
    )
  }

  n_checks <- length(checks)
  if (verbose) {
    cli::cli_alert_success(
      "Data validated: {.val {n_checks}} check(s) passed on {.val {nrow(data)}} rows x {.val {ncol(data)}} cols."
    )
  }

  invisible(data)
}


#' Assert that required columns exist in a data frame
#'
#' Checks that every column name in `cols` is present in `data`. Throws
#' a descriptive error listing the missing columns if any are absent.
#'
#' @param data A data frame.
#' @param cols Character vector. Column names that must be present.
#'
#' @return `data` invisibly if all columns exist. Throws an error listing
#'   missing columns otherwise.
#'
#' @seealso [validate_data()], [assert_range()], [assert_no_na()]
#'
#' @export
#' @examples
#' \dontrun{
#' assert_schema(df, c("country", "year", "value", "indicator"))
#' }
assert_schema <- function(data, cols) {
  if (!is.data.frame(data)) {
    stop("assert_schema() requires a data frame.", call. = FALSE)
  }
  if (!is.character(cols) || length(cols) == 0L) {
    stop("assert_schema() requires a non-empty character vector of column names.",
         call. = FALSE)
  }

  missing_cols <- setdiff(cols, names(data))

  if (length(missing_cols) > 0L) {
    stop(
      paste0(
        "assert_schema() failed: ", length(missing_cols), " column(s) missing\n",
        "  x ", paste(missing_cols, collapse = ", "), "\n",
        "  i Data has: ", paste(names(data), collapse = ", ")
      ),
      call. = FALSE
    )
  }

  invisible(data)
}


#' Assert that a numeric column's values fall within a range
#'
#' Checks that all non-NA values in `col` are between `min` and `max`
#' (inclusive). Reports how many values are out of range and what the
#' actual min/max are.
#'
#' @param data A data frame.
#' @param col Character. The column name to check.
#' @param min Numeric. Minimum acceptable value (inclusive).
#' @param max Numeric. Maximum acceptable value (inclusive).
#' @param na_ok Logical. If `TRUE`, `NA` values are ignored. If `FALSE`
#'   (default), `NA` values cause the assertion to fail.
#'
#' @return `data` invisibly if all values are in range. Throws an error
#'   with a summary of out-of-range values otherwise.
#'
#' @seealso [validate_data()], [assert_schema()], [assert_no_na()]
#'
#' @export
#' @examples
#' \dontrun{
#' assert_range(df, "value", min = -50, max = 500)
#' }
assert_range <- function(data, col, min, max, na_ok = FALSE) {
  if (!is.data.frame(data)) {
    stop("assert_range() requires a data frame.", call. = FALSE)
  }
  if (!is.character(col) || length(col) != 1L || is.na(col)) {
    stop("assert_range() requires a single column name.", call. = FALSE)
  }
  if (!is.numeric(min) || length(min) != 1L || !is.finite(min) ||
      !is.numeric(max) || length(max) != 1L || !is.finite(max)) {
    stop("assert_range() requires finite numeric 'min' and 'max'.", call. = FALSE)
  }
  if (min > max) {
    stop(
      paste0("assert_range() failed: min (", min, ") is greater than max (", max, ")."),
      call. = FALSE
    )
  }
  if (!col %in% names(data)) {
    stop(
      paste0(
        "assert_range() failed: column not found\n",
        "  x '", col, "' is not in the data frame"
      ),
      call. = FALSE
    )
  }

  vals <- data[[col]]

  if (!is.numeric(vals)) {
    stop(
      paste0(
        "assert_range() failed: column is not numeric\n",
        "  x '", col, "' is of type ", class(vals)[1]
      ),
      call. = FALSE
    )
  }

  na_count <- sum(is.na(vals))
  if (!na_ok && na_count > 0L) {
    stop(
      paste0(
        "assert_range() failed: ", na_count, " NA value(s) in '", col, "'\n",
        "  i Set na_ok = TRUE to ignore NAs"
      ),
      call. = FALSE
    )
  }

  non_na <- vals[!is.na(vals)]
  if (length(non_na) == 0L) {
    invisible(data)
    return(invisible(data))
  }

  out_low  <- sum(non_na < min)
  out_high <- sum(non_na > max)
  n_out    <- out_low + out_high

  if (n_out > 0L) {
    actual_min <- round(min(non_na), 4)
    actual_max <- round(max(non_na), 4)
    stop(
      paste0(
        "assert_range() failed: ", n_out, " value(s) out of range in '", col, "'\n",
        "  x ", out_low, " below ", min, "  |  ", out_high, " above ", max, "\n",
        "  i Actual range: [", actual_min, ", ", actual_max, "]"
      ),
      call. = FALSE
    )
  }

  invisible(data)
}


#' Assert that specified columns contain no missing values
#'
#' Checks that `NA` does not appear in any of the listed columns. Reports
#' exactly how many `NA`s are in each column that fails.
#'
#' @param data A data frame.
#' @param cols Character vector. Column names to check. If `NULL`
#'   (default), checks every column in the data frame.
#'
#' @return `data` invisibly if no `NA`s are found. Throws an error
#'   listing every column with `NA` counts otherwise.
#'
#' @seealso [validate_data()], [assert_schema()], [assert_range()]
#'
#' @export
#' @examples
#' \dontrun{
#' assert_no_na(df, c("country", "year", "value"))
#' assert_no_na(df)
#' }
assert_no_na <- function(data, cols = NULL) {
  if (!is.data.frame(data)) {
    stop("assert_no_na() requires a data frame.", call. = FALSE)
  }

  cols <- cols %||% names(data)
  missing_cols <- setdiff(cols, names(data))
  if (length(missing_cols) > 0L) {
    stop(
      paste0(
        "assert_no_na() failed: columns not found in data\n",
        "  x ", paste(missing_cols, collapse = ", ")
      ),
      call. = FALSE
    )
  }

  na_counts <- vapply(
    data[cols],
    function(col) sum(is.na(col)),
    integer(1)
  )
  bad_cols <- na_counts[na_counts > 0L]

  if (length(bad_cols) > 0L) {
    details <- paste0(
      names(bad_cols), ": ", bad_cols, " NA(s)",
      collapse = "  |  "
    )
    stop(
      paste0(
        "assert_no_na() failed: NA values found in ", length(bad_cols), " column(s)\n",
        "  x ", details
      ),
      call. = FALSE
    )
  }

  invisible(data)
}
