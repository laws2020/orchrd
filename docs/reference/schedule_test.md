# Simulate a cron schedule firing immediately

For schedule watchers created with
[`on_schedule()`](https://laws2020.github.io/orchrd/reference/on_schedule.md),
fires the action immediately regardless of the current time. Equivalent
to
[`watcher_test()`](https://laws2020.github.io/orchrd/reference/watcher_test.md)
for filesystem watchers.

## Usage

``` r
schedule_test(id)
```

## Arguments

- id:

  Character. Schedule watcher ID.

## Value

Invisibly returns the value returned by the action, or NULL on error.

## See also

[`watcher_test()`](https://laws2020.github.io/orchrd/reference/watcher_test.md),
[`on_schedule()`](https://laws2020.github.io/orchrd/reference/on_schedule.md)

## Examples

``` r
if (FALSE) { # \dontrun{
id <- on_schedule("0 8 * * *", action = ~ message("Morning fetch!"))
schedule_test(id)  # fires immediately
} # }
```
