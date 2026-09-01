# Delete a stored artifact

Removes the artifact file and its metadata sidecar.

## Usage

``` r
delete_artifact(name, dir = .artifact_dir(), verbose = TRUE)
```

## Arguments

- name:

  Character. Artifact name to delete. `"all"` removes every artifact in
  `dir` (only recognised artifact + `.meta.json` files — unrelated files
  are left untouched).

- dir:

  Character. Artifact directory.

- verbose:

  Logical. Print confirmation (default `TRUE`).

## Value

Invisibly returns `TRUE`.

## See also

[`store_artifact()`](https://laws2020.github.io/orchrd/reference/store_artifact.md),
[`list_artifacts()`](https://laws2020.github.io/orchrd/reference/list_artifacts.md)

## Examples

``` r
if (FALSE) { # \dontrun{
delete_artifact("nga_cpi_clean")
delete_artifact("all")
} # }
```
