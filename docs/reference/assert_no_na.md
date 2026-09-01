# Assert that specified columns contain no missing values

Checks that `NA` does not appear in any of the listed columns. Reports
exactly how many `NA`s are in each column that fails.

## Usage

``` r
assert_no_na(data, cols = NULL)
```

## Arguments

- data:

  A data frame.

- cols:

  Character vector. Column names to check. If `NULL` (default), checks
  every column in the data frame.

## Value

`data` invisibly if no `NA`s are found. Throws an error listing every
column with `NA` counts otherwise.

## See also

[`validate_data()`](https://laws2020.github.io/orchrd/reference/validate_data.md),
[`assert_schema()`](https://laws2020.github.io/orchrd/reference/assert_schema.md),
[`assert_range()`](https://laws2020.github.io/orchrd/reference/assert_range.md)

## Examples

``` r
if (FALSE) { # \dontrun{
assert_no_na(df, c("country", "year", "value"))
assert_no_na(df)
} # }
```
