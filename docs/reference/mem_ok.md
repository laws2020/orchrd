# Check available system memory

Returns `TRUE` if free/available memory is at least `min_mb` megabytes.
Fails open on probe error.

## Usage

``` r
mem_ok(min_mb = 500)
```

## Arguments

- min_mb:

  Numeric. Minimum megabytes of free memory required. Default `500`.

## Value

Logical scalar.
