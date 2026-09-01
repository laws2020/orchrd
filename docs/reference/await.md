# Wait for a background job and return its result

Blocks until the
[`run_bg()`](https://laws2020.github.io/orchrd/reference/run_bg.md) job
finishes (or `timeout` elapses), then returns the value the background
function produced. If the background job errored, the error is re-raised
in the calling session.

## Usage

``` r
await(job, timeout = Inf, verbose = TRUE)
```

## Arguments

- job:

  An `orchrd_job` handle from
  [`run_bg()`](https://laws2020.github.io/orchrd/reference/run_bg.md).

- timeout:

  Maximum seconds to wait. `Inf` (default) waits forever.

- verbose:

  Emit a short status line via `cli`? Default `TRUE`.

## Value

The value returned by the background function.

## See also

[`run_bg()`](https://laws2020.github.io/orchrd/reference/run_bg.md),
[`batch_exec()`](https://laws2020.github.io/orchrd/reference/batch_exec.md)

## Examples

``` r
if (FALSE) { # \dontrun{
job <- run_bg(function() Sys.sleep(1))
await(job)
} # }
```
