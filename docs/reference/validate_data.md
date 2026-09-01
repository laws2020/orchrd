# Run multiple validation assertions on a data frame

Runs any combination of
[`assert_schema()`](https://laws2020.github.io/orchrd/reference/assert_schema.md),
[`assert_range()`](https://laws2020.github.io/orchrd/reference/assert_range.md),
and
[`assert_no_na()`](https://laws2020.github.io/orchrd/reference/assert_no_na.md)
against a data frame and collects every failure before stopping. This
gives you a complete picture of what is wrong rather than halting on the
first problem.

## Usage

``` r
validate_data(data, ..., verbose = TRUE)
```

## Arguments

- data:

  A data frame to validate.

- ...:

  Named one-sided formulas (`name = ~ expr`). Each expression should
  call
  [`assert_schema()`](https://laws2020.github.io/orchrd/reference/assert_schema.md),
  [`assert_range()`](https://laws2020.github.io/orchrd/reference/assert_range.md),
  [`assert_no_na()`](https://laws2020.github.io/orchrd/reference/assert_no_na.md),
  or return `TRUE` on success and throw on failure. Use `.x` (or `data`)
  to refer to the data frame inside each formula.

- verbose:

  Logical. Print a pass message if all checks succeed (default `TRUE`).

## Value

The `data` argument invisibly if all checks pass. Throws an error
listing every failed check if any fail.

## Details

IMPORTANT: each rule must be a one-sided formula (`~ expr`) so that its
evaluation is deferred until inside `validate_data()`. If you pass a
bare `assert_*()` call (not wrapped in `~`), R evaluates it eagerly at
the call site and it will halt on the first failure instead of
collecting all of them. `validate_data()` warns if it detects a
pre-evaluated argument.

## See also

[`assert_schema()`](https://laws2020.github.io/orchrd/reference/assert_schema.md),
[`assert_range()`](https://laws2020.github.io/orchrd/reference/assert_range.md),
[`assert_no_na()`](https://laws2020.github.io/orchrd/reference/assert_no_na.md)

## Examples

``` r
if (FALSE) { # \dontrun{
pipe_exec(
  fetch    = ~ get_data("source"),

  validate = ~ validate_data(.x,
    schema = ~ assert_schema(.x, c("country", "year", "value")),
    ranges = ~ assert_range(.x,  "value", min = 0, max = 1000),
    nas    = ~ assert_no_na(.x,  c("country", "year"))
  ),

  export   = ~ save_output(.x, "data/out.parquet")
)
} # }
```
