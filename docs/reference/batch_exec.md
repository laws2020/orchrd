# Execute a list of tasks in controlled parallel batches

Processes a list of inputs by applying a function to each. In
`"parallel"` mode, `batch_size` tasks run simultaneously via
[`run_bg()`](https://laws2020.github.io/orchrd/reference/run_bg.md) and
are awaited with
[`await()`](https://laws2020.github.io/orchrd/reference/await.md); when
one batch completes, the next starts, continuing until the full list is
exhausted. In `"sequential"` mode tasks run one at a time in the current
session with progress tracking, and `batch_size` is ignored.

## Usage

``` r
batch_exec(
  tasks,
  fn,
  batch_size = 4L,
  mode = c("sequential", "parallel"),
  on_error = c("collect", "stop"),
  combine = FALSE,
  verbose = TRUE
)
```

## Arguments

- tasks:

  A list or named character vector. Each element is one input to
  process.

- fn:

  A function that accepts one element of `tasks` and returns a result.
  Must be a plain R function (not a formula).

- batch_size:

  Integer. Maximum number of tasks to run simultaneously in `"parallel"`
  mode. Ignored in `"sequential"` mode. Default `4`.

- mode:

  Character. `"sequential"` (default) runs tasks one at a time in the
  current session with progress tracking. `"parallel"` runs `batch_size`
  tasks simultaneously as background jobs via
  [`run_bg()`](https://laws2020.github.io/orchrd/reference/run_bg.md).
  Note: `"parallel"` requires `fn` (and everything it closes over) to be
  serialisable with [`saveRDS()`](https://rdrr.io/r/base/readRDS.html) -
  use `"sequential"` when `fn` closes over session variables, open
  connections, or external pointers.

- on_error:

  Character. `"collect"` (default) records failures and continues.
  `"stop"` halts on the first failure (killing any still-running jobs in
  the current batch first).

- combine:

  Logical. If `TRUE`, `rbind` the successful results that are data
  frames into a single data frame, returned as the `"combined"`
  attribute of the result list (and, when every successful result is a
  data frame, also accessible via
  [`batch_combine()`](https://laws2020.github.io/orchrd/reference/batch_combine.md)).
  A `.task` column is added identifying the source task. Non-data-frame
  results are skipped with a warning. Default `FALSE`.

- verbose:

  Logical. Print batch progress (default `TRUE`).

## Value

A named list with one element per task:

- result:

  The return value of `fn(task)`, or `NULL` on failure.

- ok:

  Logical. Whether the task succeeded.

- error:

  Character error message, or `NA` if successful.

- elapsed_sec:

  Numeric. Time taken for this task. In `"parallel"` mode this is
  approximate wall time measured from when the job's await began, not
  the job's true run time.

Names match the names of `tasks` (or `task_1`, `task_2`, ... if unnamed;
duplicates are disambiguated with
[`make.unique()`](https://rdrr.io/r/base/make.unique.html)). When
`combine = TRUE`, the combined data frame is attached as the
`"combined"` attribute.

## Details

This is the right tool when you have more tasks than you want to run
simultaneously. Running all 54 country fetches at once would overwhelm
the network and the target servers. Running them one-by-one is too slow.
`batch_exec()` gives you a controlled middle ground.

## See also

[`run_bg()`](https://laws2020.github.io/orchrd/reference/run_bg.md),
[`await()`](https://laws2020.github.io/orchrd/reference/await.md),
[`pipe_exec()`](https://laws2020.github.io/orchrd/reference/pipe_exec.md),
[`batch_combine()`](https://laws2020.github.io/orchrd/reference/batch_combine.md)

## Examples

``` r
if (FALSE) { # \dontrun{
# Fetch country datasets - 4 at a time in parallel, combined into one df
countries <- c("NGA", "ZAF", "KEN", "GHA", "ETH", "EGY")

results <- batch_exec(
  tasks      = countries,
  fn         = function(iso) get_data(iso),
  batch_size = 4,
  mode       = "parallel",
  combine    = TRUE
)

combined <- attr(results, "combined")   # one data frame, with a .task column

successes <- Filter(function(r) isTRUE(r$ok), results)
failures  <- Filter(function(r) !isTRUE(r$ok), results)
message(length(successes), " succeeded, ", length(failures), " failed")
} # }
```
