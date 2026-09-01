# Detect Out-of-Memory (OOM) Crashes

Lists stopped containers that exited with status code 137 (SIGKILL),
which commonly - but not always - indicates an out-of-memory kill.
Cross-platform.

## Usage

``` r
check_docker_oom(timeout = 60, verbose = TRUE)
```

## Arguments

- timeout:

  Numeric. Seconds before the command is killed. Default `60`.

- verbose:

  Logical. Print the result table (default `TRUE`).

## Value

Invisibly, a data frame with columns `id`, `name`, `status`. Empty data
frame if no such containers exist.

## Examples

``` r
if (FALSE) { # \dontrun{
check_docker_oom()
} # }
```
