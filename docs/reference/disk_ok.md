# Check available disk space

Returns `TRUE` if disk usage on the partition containing `path` is at or
below `threshold`. Fails open: if disk stats cannot be read, returns
`TRUE` so a guard never blocks purely because of a probe error.

## Usage

``` r
disk_ok(path = ".", threshold = 0.9)
```

## Arguments

- path:

  Character. Path on the partition to check. Default `"."` (current
  working directory).

- threshold:

  Numeric in \\\[0, 1\]\\. Maximum acceptable usage fraction. Default
  `0.90` (90 percent).

## Value

Logical scalar.

## Examples

``` r
disk_ok()          # TRUE if under 90 percent used on current partition
#> [1] FALSE
disk_ok(threshold = 0.95)
#> [1] TRUE
```
