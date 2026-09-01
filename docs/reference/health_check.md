# Check that endpoints and services are alive

Sends lightweight probes (HTTP HEAD requests for URLs, socket tests for
hosts, command checks for system tools) and returns a tidy data frame
reporting the status of each. Designed to be called before a pipeline
that depends on external services so you know upfront which sources are
reachable.

## Usage

``` r
health_check(
  ...,
  timeout = 10,
  ok_status = 400L,
  types = NULL,
  stop_on_fail = FALSE,
  verbose = TRUE
)
```

## Arguments

- ...:

  Named or unnamed character strings. Each is one endpoint to check. See
  Details for how each is classified.

- timeout:

  Numeric. Seconds before a probe times out (default `10`).

- ok_status:

  Integer. HTTP status codes below this are considered healthy (default
  `400`, so 4xx/5xx are failures). Set to `500` to treat 4xx as
  reachable-but-erroring.

- types:

  Optional named/positional character vector to force the probe type of
  a target: one of `"http"`, `"socket"`, `"cmd"`. Length must match the
  number of targets, or be `NULL` (default, auto-detect).

- stop_on_fail:

  Logical. If `TRUE`, throws an error after checking all endpoints if
  any failed (default `FALSE`).

- verbose:

  Logical. Print results to the console (default `TRUE`).

## Value

A data frame with columns `name`, `target`, `type`, `ok`, `status`,
`response_ms`. Invisibly returned so it can be used in a pipeline.

## Details

Each target is classified as:

- **URL** — starts with `http://` or `https://` -\> HTTP HEAD probe.

- **host / host:port** — contains a dot or an explicit `:port` -\> TCP
  socket probe (default port 80).

- **command** — a bare token with no dot, slash, or colon -\>
  [`Sys.which()`](https://rdrr.io/r/base/Sys.which.html) lookup.

The classification can be forced per target with the `types` argument.

By default `health_check()` **does not stop** on failure — it reports
every result and lets you decide. Set `stop_on_fail = TRUE` to make it
halt the pipeline if any check fails.

## Examples

``` r
if (FALSE) { # \dontrun{
health_check(
  CBN  = "https://www.cbn.gov.ng/rates/mprates.asp",
  NBS  = "https://nigerianstat.gov.ng"
)

health_check("https://api.example.com", stop_on_fail = TRUE)

health_check(git = "git", pwsh = "pwsh", gh = "gh")
} # }
```
