# Audit Portal JavaScript for localhost API References

Scans every .js file under the portal js/ directory for hardcoded
localhost / 127.0.0.1 endpoints, which break when the API runs in a
separate Docker container. Findings are returned as a data frame instead
of a stream of warnings.

## Usage

``` r
audit_portal_networks(portal_path = "trsbs-portal", warn = TRUE)
```

## Arguments

- portal_path:

  Path to the portal project. Default "trsbs-portal".

- warn:

  Logical. Emit a single summary warning if hits are found (default
  TRUE).

## Value

Invisibly, a data frame with columns file, line, text.

## Examples

``` r
if (FALSE) { # \dontrun{
audit_portal_networks()
hits <- audit_portal_networks("../trsbs-portal")
} # }
```
