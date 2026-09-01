# Load a previously stored artifact

Retrieves an artifact saved by
[`store_artifact()`](https://laws2020.github.io/orchrd/reference/store_artifact.md).
The format is detected automatically from the metadata sidecar — you do
not need to specify it.

## Usage

``` r
load_artifact(name, dir = .artifact_dir(), verbose = TRUE)
```

## Arguments

- name:

  Character. The artifact name to load.

- dir:

  Character. Artifact directory.

- verbose:

  Logical. Print a loading message (default `TRUE`).

## Value

The R object that was stored.

## See also

[`store_artifact()`](https://laws2020.github.io/orchrd/reference/store_artifact.md),
[`list_artifacts()`](https://laws2020.github.io/orchrd/reference/list_artifacts.md)

## Examples

``` r
if (FALSE) { # \dontrun{
df    <- load_artifact("nga_cpi_clean")
model <- load_artifact("nga_cpi_model")
} # }
```
