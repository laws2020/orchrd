# Run all built-in health checks and return a summary

A quick system snapshot that can be embedded in a
[`health_check()`](https://laws2020.github.io/orchrd/reference/health_check.md)
pipeline or printed interactively.

## Usage

``` r
health_report(path = ".", host = "8.8.8.8", min_mb = 500)
```

## Arguments

- path:

  Path for disk check. Default `"."`.

- host:

  Host for network ping. Default `"8.8.8.8"`.

- min_mb:

  Minimum free RAM in MB. Default `500`.

## Value

A named logical vector: `disk`, `memory`, `network`. Prints a formatted
summary as a side effect.

## See also

[`disk_ok()`](https://laws2020.github.io/orchrd/reference/disk_ok.md),
[`mem_ok()`](https://laws2020.github.io/orchrd/reference/mem_ok.md),
[`net_ok()`](https://laws2020.github.io/orchrd/reference/net_ok.md)
