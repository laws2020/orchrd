# Row-bind the successful data-frame results of a batch_exec() run

Collects every element of a
[`batch_exec()`](https://laws2020.github.io/orchrd/reference/batch_exec.md)
result list whose task succeeded and whose `result` is a data frame,
adds a `.task` column identifying the source task, and `rbind`s them
into a single data frame. Successful non-data-frame results are skipped
with a warning.

## Usage

``` r
batch_combine(results, verbose = TRUE)
```

## Arguments

- results:

  A named list returned by
  [`batch_exec()`](https://laws2020.github.io/orchrd/reference/batch_exec.md).

- verbose:

  Logical. Warn about skipped non-data-frame results (default `TRUE`).

## Value

A single data frame with a leading `.task` column, or an empty data
frame if there is nothing to combine.

## Details

Column handling is tolerant: frames are aligned by name (union of all
columns), with missing columns filled with `NA`, so slightly divergent
schemas still combine.

## See also

[`batch_exec()`](https://laws2020.github.io/orchrd/reference/batch_exec.md)
