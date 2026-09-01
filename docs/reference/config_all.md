# Return the full in-memory config

Return the full in-memory config

## Usage

``` r
config_all()
```

## Value

A named list containing all loaded config values.

## See also

[`load_config()`](https://laws2020.github.io/orchrd/reference/load_config.md),
[`config_get()`](https://laws2020.github.io/orchrd/reference/config_get.md)

## Examples

``` r
if (FALSE) { # \dontrun{
load_config("config.yml")
str(config_all())
} # }
```
