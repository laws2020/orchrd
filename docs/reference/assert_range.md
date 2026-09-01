# Assert that a numeric column's values fall within a range

Checks that all non-NA values in `col` are between `min` and `max`
(inclusive). Reports how many values are out of range and what the
actual min/max are.

## Usage

``` r
assert_range(data, col, min, max, na_ok = FALSE)
```

## Arguments

- data:

  A data frame.

- col:

  Character. The column name to check.

- min:

  Numeric. Minimum acceptable value (inclusive).

- max:

  Numeric. Maximum acceptable value (inclusive).

- na_ok:

  Logical. If `TRUE`, `NA` values are ignored. If `FALSE` (default),
  `NA` values cause the assertion to fail.

## Value

`data` invisibly if all values are in range. Throws an error with a
summary of out-of-range values otherwise.

## See also

[`validate_data()`](https://laws2020.github.io/orchrd/reference/validate_data.md),
[`assert_schema()`](https://laws2020.github.io/orchrd/reference/assert_schema.md),
[`assert_no_na()`](https://laws2020.github.io/orchrd/reference/assert_no_na.md)

## Examples

``` r
if (FALSE) { # \dontrun{
assert_range(df, "value", min = -50, max = 500)
} # }
```
