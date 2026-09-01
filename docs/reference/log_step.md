# Log a workflow step

Logs a message at a given severity level. Printed to the console via
`cli` and optionally written to an NDJSON log file configured by
[`log_config()`](https://laws2020.github.io/orchrd/reference/log_config.md).

## Usage

``` r
log_step(msg, level = "info", .data = NULL)
```

## Arguments

- msg:

  Character. The message. Supports cli inline markup and interpolation,
  e.g. `"Loaded {nrow(df)} rows"`. Interpolation happens exactly once,
  against the calling environment.

- level:

  Character. One of `"debug"`, `"info"` (default), `"warn"`, or
  `"error"`.

- .data:

  List. Optional structured data attached to the log entry. Written to
  the JSON file only, not printed to the console.

## Value

Invisibly returns the log entry as a list.

## Details

Works anywhere: standalone in a script, inside
[`pipe_exec()`](https://laws2020.github.io/orchrd/reference/pipe_exec.md)
steps, or inside any function you want to make observable.

## See also

[`with_log()`](https://laws2020.github.io/orchrd/reference/with_log.md)
to auto-log an entire block of code.

## Examples

``` r
if (FALSE) { # \dontrun{
log_step("Starting data fetch")
log_step("Cache miss - downloading fresh data", level = "warn")
log_step("Connection timed out", level = "error")
log_step("Loaded {nrow(df)} rows from {source}")
log_step("Fetch complete",
         .data = list(source = "endpoint_a", rows = nrow(df)))
} # }
```
