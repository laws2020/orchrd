# Run a function or pipeline in the background

Launches `what` in a separate, supervised R process so the calling
session stays free. Returns immediately with a job handle you can pass
to [`await()`](https://laws2020.github.io/orchrd/reference/await.md) to
collect the result. Used by
[`batch_exec()`](https://laws2020.github.io/orchrd/reference/batch_exec.md)
for controlled parallel execution and by tripwire's
[`pipe_on_arrive()`](https://laws2020.github.io/orchrd/reference/pipe_on_arrive.md)
to dispatch pipelines when files arrive.

## Usage

``` r
run_bg(what, ..., label = NULL, packages = "orchrd", supervise = TRUE)
```

## Arguments

- what:

  A function to run in the background. A non-function value is wrapped
  and returned as-is by the job.

- ...:

  Named arguments forwarded to `what` when it is a function.

- label:

  Optional human-readable label recorded on the job handle.

- packages:

  Character vector of packages to attach in the worker. Defaults to
  loading `orchrd` so pipeline steps can use its helpers.

- supervise:

  Kill the background process if the main session exits? Default `TRUE`.

## Value

An object of class `orchrd_job`: a `callr` process handle with a `label`
and `started_at` attribute. It exposes `$kill()`, `$is_alive()`,
`$get_result()`, and `$wait()`.

## Details

`what` may be a function (called in the background with any arguments
supplied via `...`) or a zero-argument callable / pipeline object. When
a function is supplied, the `...` arguments are forwarded to it, so
`run_bg(pipeline, .file = "x.csv")` calls `pipeline(.file = "x.csv")` in
the background.

## See also

[`await()`](https://laws2020.github.io/orchrd/reference/await.md),
[`batch_exec()`](https://laws2020.github.io/orchrd/reference/batch_exec.md)

## Examples

``` r
if (FALSE) { # \dontrun{
job <- run_bg(function(x) x * 2, x = 21)
await(job)   # 42
} # }
```
