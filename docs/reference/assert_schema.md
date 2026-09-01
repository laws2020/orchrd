# Assert that required columns exist in a data frame

Checks that every column name in `cols` is present in `data`. Throws a
descriptive error listing the missing columns if any are absent.

## Usage

``` r
assert_schema(data, cols)
```

## Arguments

- data:

  A data frame.

- cols:

  Character vector. Column names that must be present.

## Value

`data` invisibly if all columns exist. Throws an error listing missing
columns otherwise.

## See also

[`validate_data()`](https://laws2020.github.io/orchrd/reference/validate_data.md),
[`assert_range()`](https://laws2020.github.io/orchrd/reference/assert_range.md),
[`assert_no_na()`](https://laws2020.github.io/orchrd/reference/assert_no_na.md)

## Examples

``` r
if (FALSE) { # \dontrun{
assert_schema(df, c("country", "year", "value", "indicator"))
} # }
```
