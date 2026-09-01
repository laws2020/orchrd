# Run a system command cleanly

A unified, cross-platform interface for running system commands. Returns
a structured `orchrd_result` object — exit code, stdout, stderr, and
elapsed time.

## Usage

``` r
run_cmd(
  cmd,
  args = character(),
  dir = ".",
  env = character(),
  timeout = 60,
  echo = FALSE,
  error_ok = FALSE
)
```

## Arguments

- cmd:

  Character. The command to run, e.g. `"git status"`. For arguments
  containing spaces or quotes, use `args` instead.

- args:

  Character vector. Arguments passed separately — safer for paths with
  spaces or special characters.

- dir:

  Character. Working directory. Defaults to current directory.

- env:

  Named character vector. Extra environment variables. These are
  *merged* into the current environment (PATH etc. are preserved).

- timeout:

  Numeric. Seconds before the process is killed. Default 60. Use `Inf`
  for long-running operations (large pushes, uploads).

- echo:

  Logical. Stream output in real-time (default FALSE).

- error_ok:

  Logical. Return result even on failure (default FALSE).

## Value

An S3 object of class `orchrd_result` with fields: `$ok`, `$status`,
`$stdout`, `$stderr`, `$elapsed_sec`, `$cmd`.

## Examples

``` r
if (FALSE) { # \dontrun{
run_cmd("git status")
run_cmd("git", args = c("commit", "-m", "my commit message"))
} # }
```
