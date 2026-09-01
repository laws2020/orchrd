# Repair a Stuck Docker Engine (Windows)

Attempts to recover a Docker Desktop installation that is stuck or
unresponsive on Windows by stopping the Docker Desktop and backend
processes, shutting down WSL, restarting the WSL service, and
relaunching Docker Desktop.

## Usage

``` r
repair_docker(timeout = 120, verbose = TRUE)
```

## Arguments

- timeout:

  Numeric. Seconds before the PowerShell recovery script is killed.
  Default `120`. Use `Inf` to wait indefinitely.

- verbose:

  Logical. Print progress (default `TRUE`).

## Value

Invisibly, a list with `ok`, `status`, `stdout`, and `stderr`.

## Details

Windows-only. Some operations (restarting the WSL service) may require
an elevated (Administrator) R session; when not elevated, those steps
are skipped by PowerShell and reported in the result's `stderr`.

## Examples

``` r
if (FALSE) { # \dontrun{
res <- repair_docker()
res$ok
} # }
```
