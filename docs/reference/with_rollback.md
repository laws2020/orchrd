# Execute a step with an automatic rollback on failure

Wraps a pipeline step with a rollback expression that runs if - and only
if - the step fails. If the step succeeds, the rollback is never called.
If the step fails, the rollback runs and then the error propagates
normally (so
[`pipe_exec()`](https://laws2020.github.io/orchrd/reference/pipe_exec.md)'s
`.on_error` logic still applies).

## Usage

``` r
with_rollback(expr, rollback = NULL, label = "", verbose = TRUE)
```

## Arguments

- expr:

  An R expression - the step to attempt.

- rollback:

  An R expression - what to run if `expr` fails. Run for its side
  effects only; its return value is discarded. `NULL` (the default)
  means there is nothing to undo.

- label:

  Character. Label for log messages. Defaults to an empty string (no
  label prefix).

- verbose:

  Logical. Log rollback activity (default `TRUE`).

## Value

The value of `expr` if it succeeds. If `expr` fails, the rollback runs
and then the original error is re-thrown.

## Details

Designed for deployment-style workflows where steps have side effects
that need to be undone if a later step fails. Common patterns:

- Copy a file, rollback by deleting it

- Push a git tag, rollback by deleting the remote tag

- Deploy to a server, rollback by reverting to the previous version

- Write to a database, rollback by deleting the inserted rows

If the rollback expression itself fails, its error is caught and
reported, but the *original* step error is always the one re-thrown, so
a failing rollback never masks the real cause.

## See also

[`deploy_step()`](https://laws2020.github.io/orchrd/reference/deploy_step.md),
[`pipe_exec()`](https://laws2020.github.io/orchrd/reference/pipe_exec.md)

## Examples

``` r
if (FALSE) { # \dontrun{
pipe_exec(
  build = ~ with_rollback(
    build_package(),
    rollback = clean_build_dir(),
    label    = "build"
  ),
  deploy = ~ with_rollback(
    push_to_production(.x),
    rollback = revert_to_previous_release(),
    label    = "deploy"
  )
)
} # }
```
