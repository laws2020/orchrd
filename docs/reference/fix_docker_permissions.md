# Fix Docker Named Pipe Permissions (Windows)

Adds the current Windows user to the local `docker-users` security group
so Docker Desktop can be used without per-operation elevation.

## Usage

``` r
fix_docker_permissions(
  user = Sys.getenv("USERNAME"),
  timeout = 60,
  verbose = TRUE
)
```

## Arguments

- user:

  Character. Windows username to add. Defaults to the current user
  (`USERNAME` env var).

- timeout:

  Numeric. Seconds before the PowerShell call is killed. Default `60`.

- verbose:

  Logical. Print progress (default `TRUE`).

## Value

Invisibly, a list with `ok`, `status`, `stdout`, and `stderr`.

## Details

Windows-only, and **requires an elevated (Administrator) R session** —
modifying local groups is an administrative operation. Unlike the
original, this reports failure instead of silently swallowing a
permission error.

## Examples

``` r
if (FALSE) { # \dontrun{
res <- fix_docker_permissions()
res$ok
} # }
```
