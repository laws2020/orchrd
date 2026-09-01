# Configure session-wide logging

Sets the minimum log level and output file for the current session. Call
once at the top of a script or in `.Rprofile`.

## Usage

``` r
log_config(level = "info", file = NULL, reset = FALSE)
```

## Arguments

- level:

  Character. Minimum level to output. Messages below this level are
  silently dropped. One of `"debug"`, `"info"` (default), `"warn"`,
  `"error"`.

- file:

  Character. Path to the NDJSON log file. `NULL` = console only
  (default). The file is appended, not overwritten, unless
  `reset = TRUE`.

- reset:

  Logical. Clear the in-memory log and start a new session ID (default
  `FALSE`).

## Value

Invisibly returns a list with the previous `level` and `file`.

## Details

The log file format is NDJSON (newline-delimited JSON): one JSON object
per line, appended across the session. Readable by DuckDB, pandas, `jq`,
or any log aggregation tool.

## See also

[`get_log()`](https://laws2020.github.io/orchrd/reference/get_log.md) to
retrieve the in-memory log.

## Examples

``` r
if (FALSE) { # \dontrun{
log_config(level = "debug")
log_config(level = "info", file = "logs/session.json")
log_config(reset = TRUE, file = "logs/run_002.json")
} # }
```
