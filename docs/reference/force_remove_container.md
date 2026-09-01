# Force Delete a Stuck Container

Forcefully removes a Docker container by name or ID via `docker rm -f`.
Cross-platform. Persistent volumes are not removed.

## Usage

``` r
force_remove_container(container_name, timeout = 60, verbose = TRUE)
```

## Arguments

- container_name:

  Name or ID of the container to remove.

- timeout:

  Numeric. Seconds before the command is killed. Default `60`.

- verbose:

  Logical. Print progress (default `TRUE`).

## Value

Invisibly, a list with `ok`, `status`, `stdout`, `stderr`.

## Examples

``` r
if (FALSE) { # \dontrun{
force_remove_container("trsbs-api")
force_remove_container("a1b2c3d4e5f6")
} # }
```
