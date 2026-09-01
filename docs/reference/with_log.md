# Execute an expression with automatic entry and exit logging

Wraps a block of code with start and completion log messages, including
elapsed time. On error, logs the failure message before re-throwing.

## Usage

``` r
with_log(label = "step", expr, level = "info", .data = NULL)
```

## Arguments

- label:

  Character. Description of the step shown in log messages.

- expr:

  An R expression or block `{ ... }`.

- level:

  Character. Log level for the start and done messages (default
  `"info"`).

- .data:

  List. Extra structured data attached to the log entries.

## Value

The value of `expr`. Side effect: two log entries written, start and
done (or failure) with elapsed time.

## Details

Drop `with_log("label", { ... })` around any block and it becomes fully
observable: timestamped, timed, and failure-safe, without touching the
logic inside.

## See also

[`log_step()`](https://laws2020.github.io/orchrd/reference/log_step.md)
for single messages,
[`log_config()`](https://laws2020.github.io/orchrd/reference/log_config.md)
to configure file output.

## Examples

``` r
if (FALSE) { # \dontrun{
df <- with_log("Fetch source data", {
  get_data("source")
})
} # }
```
