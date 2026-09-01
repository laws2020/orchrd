# Debug Portal and API Communication

Inspects Docker networking and recent container logs to help diagnose
communication problems between a web portal and its API. Talks to the
Docker CLI directly (cross-platform) with a bounded timeout.

## Usage

``` r
debug_portal_api(
  portal_container = "trsbs-portal",
  api_container = "trsbs-api",
  tail = 20L,
  timeout = 20,
  verbose = TRUE
)
```

## Arguments

- portal_container:

  Name or ID of the portal container.

- api_container:

  Name or ID of the API container.

- tail:

  Integer. Number of recent log lines to fetch per container.

- timeout:

  Numeric. Seconds before a docker call is abandoned.

- verbose:

  Logical. Print progress and output (default TRUE).

## Value

Invisibly, a named list with elements network, portal_logs, api_logs
(each a structured result list with ok/status/stdout/stderr).

## Examples

``` r
if (FALSE) { # \dontrun{
debug_portal_api()
d <- debug_portal_api("my-portal", "my-api")
d$network$stdout
} # }
```
