# Retry with a descriptive label

Prints a label before the first attempt then delegates to
[`retry()`](https://laws2020.github.io/orchrd/reference/retry.md). Makes
log output readable when multiple retried calls run inside the same
[`pipe_exec()`](https://laws2020.github.io/orchrd/reference/pipe_exec.md)
pipeline.

Prints a label before the first attempt then delegates to
[`retry()`](https://laws2020.github.io/orchrd/reference/retry.md). Makes
log output readable when multiple retried calls run inside the same
[`pipe_exec()`](https://laws2020.github.io/orchrd/reference/pipe_exec.md)
pipeline.

## Usage

``` r
retry_labeled(
  label,
  expr,
  times = 3L,
  wait = 2,
  backoff = TRUE,
  max_wait = 60,
  jitter = TRUE,
  on = NULL,
  silent = FALSE,
  finally = NULL,
  record_attempts = FALSE
)

retry_labeled(
  label,
  expr,
  times = 3L,
  wait = 2,
  backoff = TRUE,
  max_wait = 60,
  jitter = TRUE,
  on = NULL,
  silent = FALSE,
  finally = NULL,
  record_attempts = FALSE
)
```

## Arguments

- label:

  Character. Label printed before the first attempt.

- expr:

  An R expression to attempt.

- times:

  Integer. Maximum number of attempts (default 3).

- wait:

  Numeric. Base wait in seconds between attempts (default 2). With
  backoff = TRUE this doubles each time: wait, wait*2, wait*4, ...

- backoff:

  Logical. Double the wait after each failure (default TRUE). Set FALSE
  for a flat wait.

- max_wait:

  Numeric. Upper bound (seconds) on any single wait after backoff and
  jitter are applied (default 60). Prevents unbounded growth.

- jitter:

  Logical. Add plus/minus 30 percent random variation to the wait time
  (default TRUE). Prevents thundering-herd on shared endpoints.

- on:

  Character vector. Error message patterns that trigger a retry. NULL
  (default) retries on any error. When supplied, errors that match none
  of the patterns fail immediately without retrying. Patterns are
  treated as case-insensitive regular expressions.

- silent:

  Logical. Suppress retry messages (default FALSE).

- finally:

  An optional expression evaluated after all attempts regardless of
  success or failure. Use for cleanup.

- record_attempts:

  Logical. When TRUE, attaches the number of attempts used as
  attr(value, "retry_attempts") on success (default FALSE, so atomic
  return values are never altered by default).

## Value

The value of expr on success.

The value of expr on success.

## See also

[`retry()`](https://laws2020.github.io/orchrd/reference/retry.md)
