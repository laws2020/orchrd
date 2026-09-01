# Check whether a configuration key exists

Non-throwing predicate — returns `TRUE` if the (possibly nested) key
path resolves in the loaded config, `FALSE` otherwise. Useful for
feature flags and optional settings.

## Usage

``` r
config_has(...)
```

## Arguments

- ...:

  One or more character keys forming a path through the config.

## Value

Logical, length 1.

## See also

[`config_get()`](https://laws2020.github.io/orchrd/reference/config_get.md)

## Examples

``` r
if (FALSE) { # \dontrun{
if (config_has("features", "beta")) enable_beta()
} # }
```
