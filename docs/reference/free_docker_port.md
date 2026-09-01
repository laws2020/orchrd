# Free Up a Blocked Port (Windows)

Finds and terminates the Windows process(es) holding a TCP port, using
PowerShell's `Get-NetTCPConnection`. Useful when Docker cannot bind a
host port because another application is already listening on it.

## Usage

``` r
free_docker_port(port, timeout = 30, verbose = TRUE)
```

## Arguments

- port:

  Integer TCP port to clear (1-65535).

- timeout:

  Numeric. Seconds before the command is killed. Default `30`.

- verbose:

  Logical. Print what was found and killed (default `TRUE`).

## Value

Invisibly, a list with `ok`, `status`, `stdout`, `stderr`.

## Details

Terminating a process can cause unsaved work to be lost. System PIDs (0
and 4) are never touched.

## Examples

``` r
if (FALSE) { # \dontrun{
free_docker_port(8000)
free_docker_port(5432)
} # }
```
