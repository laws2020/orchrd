# Retrieve a configuration value

Returns a value from the config loaded by
[`load_config()`](https://laws2020.github.io/orchrd/reference/load_config.md).
Supports nested access by passing multiple keys.

## Usage

``` r
config_get(..., default = .no_default)
```

## Arguments

- ...:

  One or more character keys forming a path through the config. Single
  key for top-level values; multiple keys for nested values.

- default:

  Any. Value to return if the key is not found. If omitted, a missing
  key is an error. Supplying `default = NULL` is honored — it returns
  `NULL` instead of erroring.

## Value

The config value, or `default` if the key is not found.

## See also

[`load_config()`](https://laws2020.github.io/orchrd/reference/load_config.md),
[`config_all()`](https://laws2020.github.io/orchrd/reference/config_all.md),
[`config_has()`](https://laws2020.github.io/orchrd/reference/config_has.md)

## Examples

``` r
if (FALSE) { # \dontrun{
config_get("throttle")
config_get("sources", "cbn")
config_get("missing_key", default = "fallback")
config_get("maybe_missing", default = NULL)   # returns NULL, no error
} # }
```
