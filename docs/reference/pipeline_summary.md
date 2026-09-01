# Summarise pipeline performance across multiple runs

Reads the log file(s) produced by
[`log_config()`](https://laws2020.github.io/orchrd/reference/log_config.md)
and/or
[`pipe_exec()`](https://laws2020.github.io/orchrd/reference/pipe_exec.md)
and returns a tidy summary of performance metrics across runs: success
rate, mean and total elapsed time, step-level timing, and failure
patterns.

## Usage

``` r
pipeline_summary(
  log_file,
  type = c("auto", "session", "pipeline"),
  verbose = TRUE
)
```

## Arguments

- log_file:

  Character. Path to an NDJSON session log written by
  [`log_config()`](https://laws2020.github.io/orchrd/reference/log_config.md)
  with `file=`, OR a pipe_exec JSON run log written by
  [`pipe_exec()`](https://laws2020.github.io/orchrd/reference/pipe_exec.md)
  with `.log_file=`, OR a directory containing multiple such files.
  Multiple paths can be supplied as a character vector.

- type:

  Character. `"auto"` (default) detects each file's format; `"session"`
  forces NDJSON session logs; `"pipeline"` forces pipe_exec JSON run
  logs.

- verbose:

  Logical. Print summary to console (default `TRUE`).

## Value

A named list with a stable shape (keys always present): `$runs`,
`$success_rate`, `$elapsed`, `$steps`, `$errors`, `$raw`.

## Details

This is the function to call after a week of scheduled pipeline runs to
understand where time is spent and which steps fail most often.

## Examples

``` r
if (FALSE) { # \dontrun{
pipeline_summary("logs/")
pipeline_summary(c("logs/run_2026_04_01.json", "logs/run_2026_04_02.json"),
                 type = "pipeline")
pipeline_summary("logs/session.json", type = "session")
} # }
```
