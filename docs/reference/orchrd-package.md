# orchrd: PowerShell-Inspired Workflow Orchestration for R

`orchrd` brings PowerShell's workflow philosophy into R: simple
commands, clean outputs, pipeline thinking, retry logic, and
automation-friendly logging.

Designed as infrastructure for the openafrR ecosystem but useful for any
R developer orchestrating scripts, APIs, and system processes.

### Core functions

|  |  |
|----|----|
| Function | What it does |
| [`run_cmd()`](https://laws2020.github.io/orchrd/reference/run_cmd.md) | Run any system command, get structured output |
| [`run_script()`](https://laws2020.github.io/orchrd/reference/run_script.md) | Run R / Python / PowerShell / bash scripts |
| [`pipe_exec()`](https://laws2020.github.io/orchrd/reference/pipe_exec.md) | Chain steps into a named, logged pipeline |
| [`retry()`](https://laws2020.github.io/orchrd/reference/retry.md) | Retry any expression with backoff and jitter |
| [`log_step()`](https://laws2020.github.io/orchrd/reference/log_step.md) | Log a workflow step with level and timing |
| [`with_log()`](https://laws2020.github.io/orchrd/reference/with_log.md) | Auto-log entry, exit, and elapsed for any block |
| [`log_config()`](https://laws2020.github.io/orchrd/reference/log_config.md) | Configure log level and output file |
| [`get_log()`](https://laws2020.github.io/orchrd/reference/get_log.md) | Retrieve the in-memory session log |
| `inspect_file()` | See full structure of Excel/CSV/PDF before reading |
| `read_tabs()` | Smart multi-tab Excel reader |
| `sniff_csv()` | Detect encoding, delimiter, skip rows before reading |
| `scan_pdf()` | Classify PDF as digital or scanned, detect tables |
| `read_clean()` | One-shot smart reader for any file type |
| `warm_cache()` | Parallel cache warming via PowerShell |
| `cache_status()` | Report on the local dataset cache |
| `cache_clear()` | Remove stale or all cached files |
| `ps_available()` | Check if PowerShell 7 plus is installed |
| `validate_article()` | Validate an article before submission |
| `submit_article()` | Submit an article via git and GitHub PR |
| `article_status()` | Poll PR approval state |
| `list_articles()` | List all your article submissions |
| `retract_article()` | Close a PR and delete the remote branch |

### Quick start

    library(orchrd)

    # Run a system command and get structured output
    result <- run_cmd("git status")
    result$ok
    result$stdout

    # Full pipeline with logging and retry
    log_config(file = "logs/session.json")

    pipe_exec(
      fetch  = ~ retry(some_api_call()),
      clean  = ~ dplyr::filter(.x, !is.na(value)),
      export = ~ arrow::write_parquet(.x, "data/output.parquet")
    )

## See also

Useful links:

- <https://laws2020.github.io/orchrd>

- <https://github.com/laws2020/orchrd>

- Report bugs at <https://github.com/laws2020/orchrd/issues>

## Author

**Maintainer**: Lawrence Garba <laws.garba@gmail.com>

Authors:

- Lawrence Garba <laws.garba@gmail.com>
