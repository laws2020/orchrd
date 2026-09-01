# Audit Portal HTML IDs Against JavaScript References

Extracts every element ID from the portal index.html and reports IDs
that are not referenced by any JavaScript file in the js/ directory.
Matching is aggregated across all .js files and uses word boundaries to
avoid the "foo matches foobar" false positive.

## Usage

``` r
audit_portal_ids(
  portal_path = "trsbs-portal",
  html_file = "index.html",
  verbose = TRUE
)
```

## Arguments

- portal_path:

  Path to the portal project. Default "trsbs-portal".

- html_file:

  Character. HTML file to scan, relative to portal_path.

- verbose:

  Logical. Print findings (default TRUE).

## Value

Invisibly, a data frame with columns id and referenced (logical).

## Examples

``` r
if (FALSE) { # \dontrun{
audit_portal_ids()
audit_portal_ids("C:/projects/trsbs-portal")
} # }
```
