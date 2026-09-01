# Point a project at a fast, reliable CRAN mirror

Writes a project-level `.Rprofile` setting `repos` to the CRAN cloud
mirror. R-specific; only relevant for the `"r-shiny"` stack.

## Usage

``` r
optimize_build_speed(dir = ".", overwrite = FALSE)
```

## Arguments

- dir:

  Character. Directory to write `.Rprofile` into. Default `"."`.

- overwrite:

  Logical. Overwrite an existing `.Rprofile` (default `FALSE`).

## Value

Invisibly returns the path to the written `.Rprofile`.

## See also

[`generate_dockerfile()`](https://laws2020.github.io/orchrd/reference/generate_dockerfile.md)
