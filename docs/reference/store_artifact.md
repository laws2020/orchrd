# Store a pipeline output as a named artifact

Saves an R object to disk with metadata tracking. Supports multiple
formats: `"rds"` (any R object), `"parquet"` (data frames, requires
`arrow`), `"csv"` (data frames), and `"json"`.

## Usage

``` r
store_artifact(
  x,
  name,
  format = "rds",
  dir = .artifact_dir(),
  overwrite = TRUE,
  verbose = TRUE
)
```

## Arguments

- x:

  The R object to save.

- name:

  Character. A unique name for this artifact.

- format:

  Character. Storage format: `"rds"` (default), `"parquet"`, `"csv"`, or
  `"json"`. Only `"rds"` and `"parquet"` preserve R types faithfully;
  `"csv"` and `"json"` are lossy for factors, dates, and list-columns.

- dir:

  Character. Artifact directory. Defaults to
  `tools::R_user_dir("orchrd", "cache")`.

- overwrite:

  Logical. Replace an existing artifact with the same name (default
  `TRUE`).

- verbose:

  Logical. Print confirmation (default `TRUE`).

## Value

`x` invisibly so the function can be used at the end of a
[`pipe_exec()`](https://laws2020.github.io/orchrd/reference/pipe_exec.md)
step without breaking the flow.

## Details

The artifact is saved with a metadata sidecar (`.meta.json`) recording
the name, format, dimensions (for data frames), timestamp, and size. Use
[`load_artifact()`](https://laws2020.github.io/orchrd/reference/load_artifact.md)
to retrieve it and
[`list_artifacts()`](https://laws2020.github.io/orchrd/reference/list_artifacts.md)
to see what is stored.

Designed to sit at the end of a
[`pipe_exec()`](https://laws2020.github.io/orchrd/reference/pipe_exec.md)
step so every significant output is tracked and reloadable without
re-running the pipeline.

## See also

[`load_artifact()`](https://laws2020.github.io/orchrd/reference/load_artifact.md),
[`list_artifacts()`](https://laws2020.github.io/orchrd/reference/list_artifacts.md),
[`delete_artifact()`](https://laws2020.github.io/orchrd/reference/delete_artifact.md)

## Examples

``` r
if (FALSE) { # \dontrun{
pipe_exec(
  fetch  = ~ get_data("source"),
  clean  = ~ remove_na(.x),
  save   = ~ store_artifact(.x, "nga_cpi_clean", format = "parquet")
)

model <- lm(value ~ year, data = df)
store_artifact(model, "nga_cpi_model")

df    <- load_artifact("nga_cpi_clean")
model <- load_artifact("nga_cpi_model")
} # }
```
