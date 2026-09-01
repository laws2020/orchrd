# List all stored artifacts

Scans the artifact directory and returns a data frame describing every
stored artifact — name, format, size, dimensions, and timestamp.

## Usage

``` r
list_artifacts(dir = .artifact_dir())
```

## Arguments

- dir:

  Character. Artifact directory.

## Value

A data frame. Printed and returned invisibly.

## See also

[`store_artifact()`](https://laws2020.github.io/orchrd/reference/store_artifact.md),
[`delete_artifact()`](https://laws2020.github.io/orchrd/reference/delete_artifact.md)

## Examples

``` r
if (FALSE) { # \dontrun{
list_artifacts()
} # }
```
