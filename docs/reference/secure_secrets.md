# Create a .dockerignore that keeps secrets out of the build context

Writes a `.dockerignore` excluding credential files, environment files,
build output, dependency caches, and VCS metadata for **any** stack (R,
JS/web, Node). Existing entries are preserved; only missing recommended
entries are appended (deduplicated); your custom rules are never
dropped.

## Usage

``` r
secure_secrets(dir = ".")

secure_r_secrets(dir = ".")
```

## Arguments

- dir:

  Character. Directory to write `.dockerignore` into. Default `"."`.

## Value

Invisibly returns the path to the written `.dockerignore`.

## See also

[`generate_dockerfile()`](https://laws2020.github.io/orchrd/reference/generate_dockerfile.md)
