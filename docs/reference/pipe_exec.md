# Execute a named pipeline of steps sequentially

The core of `orchrd`. Each step receives the output of the previous step
as `.x`, logs progress, handles errors, and produces a structured result
you can inspect after the run.

## Usage

``` r
pipe_exec(
  ...,
  .init = NULL,
  .on_error = c("stop", "warn", "skip"),
  .log = TRUE,
  .log_file = NULL
)
```

## Arguments

- ...:

  One-sided formulas, named formulas, or functions. Each is one step.
  Duplicate names are made unique with a numeric suffix.

- .init:

  Any. Initial value passed as `.x` to the first step. Default `NULL`.

- .on_error:

  One of:

  `"stop"`

  :   (default) Halt on first failure.

  `"warn"`

  :   Log the failure, pass the previous `.x` through, keep going.

  `"skip"`

  :   Silently keep going with the previous `.x`.

- .log:

  Logical. Print step progress to the console (default `TRUE`).

- .log_file:

  Character. Write a JSON run log to this path. Created or overwritten
  each run. `NULL` (default) disables file logging.

## Value

An S3 object of class `orchrd_pipeline`:

- `$result`:

  The final step's output value.

- `$ok`:

  Logical. `TRUE` if all steps succeeded.

- `$steps`:

  Data frame: `step`, `status`, `elapsed_sec`, `error`.

- `$log`:

  List of raw per-step detail.

- `$elapsed_sec`:

  Total wall time across all steps.

## Details

Steps are one-sided formulas (`~ expr`) or named formulas
(`name = ~ expr`). `.x` is the only special symbol - it holds the output
of the previous step.

## Examples

``` r
if (FALSE) { # \dontrun{
pipe_exec(
  fetch  = ~ get_data("source"),
  clean  = ~ remove_na(.x),
  export = ~ save_parquet(.x, "out.parquet")
)

pipe_exec(
  .init = "NGA",
  fetch = ~ get_data(.x),
  clean = ~ remove_na(.x)
)

pipe_exec(
  a = ~ get_data("source_a"),
  b = ~ get_data("source_b"),
  .on_error = "warn"
)

out <- pipe_exec(
  fetch = ~ get_data("source"),
  clean = ~ remove_na(.x)
)
out$ok
out$result
out$steps
} # }
```
