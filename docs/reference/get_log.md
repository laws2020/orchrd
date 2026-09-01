# Retrieve the in-memory session log

Returns all log entries written since the session started (or since the
last
[`log_config()`](https://laws2020.github.io/orchrd/reference/log_config.md)
call with `reset = TRUE`) as a tidy data frame.

## Usage

``` r
get_log()
```

## Value

A data frame with columns `timestamp`, `session`, `level`, `message`.
Returns an empty (0-row) data frame with the same columns if nothing has
been logged yet.

## See also

[`log_config()`](https://laws2020.github.io/orchrd/reference/log_config.md)
to write logs to a file.

## Examples

``` r
if (FALSE) { # \dontrun{
log_step("step one")
log_step("something suspicious", level = "warn")
df <- get_log()
df[df$level %in% c("warn", "error"), ]
} # }
```
