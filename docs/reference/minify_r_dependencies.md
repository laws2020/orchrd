# Write leaner R install/runtime settings for containers

Writes an `Rprofile.site`. R-specific; only takes effect when copied to
`$R_HOME/etc/` inside the image, which
[`generate_dockerfile()`](https://laws2020.github.io/orchrd/reference/generate_dockerfile.md)
does for the `"r-shiny"` stack.

## Usage

``` r
minify_r_dependencies(dir = ".", overwrite = FALSE)
```

## Arguments

- dir:

  Character. Directory to write `Rprofile.site` into. Default `"."`.

- overwrite:

  Logical. Overwrite an existing file (default `FALSE`).

## Value

Invisibly returns the path to the written `Rprofile.site`.

## See also

[`generate_dockerfile()`](https://laws2020.github.io/orchrd/reference/generate_dockerfile.md)
