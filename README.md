# orchrd: PowerShell-Inspired Workflow Orchestration for R  
  
`orchrd` brings PowerShell's workflow philosophy into R: simple commands,  
clean structured outputs, pipeline thinking, retry logic, and  
automation-friendly logging. It is infrastructure for building  
unattended, observable, resilient R pipelines.  
  
Every command returns a **structured result** (`list(ok, status, stdout, stderr)`  
or an `orchrd_*` object) rather than a raw character vector, so you can  
always inspect what happened programmatically.  
  
**Windows-safe by design:** all error messages use plain string  
concatenation (never `cli::format_error()` with named vectors, which can  
trigger a RAWSXP crash during error unwinding on Windows), and every file  
is ASCII-only.  
  
---  
  
## Table of contents  
  
1. [Installation](#installation)  
2. [Quick start (beginners)](#quick-start-beginners)  
3. [Core concepts](#core-concepts)  
4. [Function reference by subsystem](#function-reference-by-subsystem)  
   - [Running commands and scripts](#1-running-commands-and-scripts)  
   - [The pipeline engine](#2-the-pipeline-engine)  
   - [Reliability and control flow](#3-reliability-and-control-flow)  
   - [Background and batch execution](#4-background-and-batch-execution)  
   - [Logging and observability](#5-logging-and-observability)  
   - [Configuration](#6-configuration)  
   - [Secrets](#7-secrets)  
   - [Validation](#8-validation)  
   - [Pre-flight checks and health](#9-pre-flight-checks-and-health)  
   - [Artifacts and checkpoints](#10-artifacts-and-checkpoints)  
   - [Notifications](#11-notifications)  
   - [Docker operations](#12-docker-operations)  
   - [Docker scaffolding](#13-docker-scaffolding)  
   - [Portal / API debugging](#14-portal--api-debugging)  
   - [Cloud](#15-cloud)  
5. [End-to-end examples (advanced)](#end-to-end-examples-advanced)  
  
---  
  
## Installation  
  
```r  
# install.packages("devtools")  
devtools::install_github("laws2020/orchrd")  
  
library(orchrd)  
```  
  
List everything the package exposes:  
  
```r  
ls("package:orchrd")            # exported (user-facing) functions  
getNamespaceExports("orchrd")   # same, from NAMESPACE  
```  
  
---  
  
## Quick start (beginners)  
  
Run a system command and inspect the result:  
  
```r  
res <- run_cmd("git", c("status", "--short"))  
res$ok        # TRUE / FALSE  
res$status    # exit code (0 = success)  
res$stdout    # captured standard output (character vector)  
res$stderr    # captured standard error  
```  
  
Chain a few named steps into a pipeline:  
  
```r  
result <- pipe_exec(  
  fetch = ~ run_cmd("git", c("pull")),  
  build = ~ run_cmd("Rscript", c("build.R")),  
  test  = ~ run_cmd("Rscript", c("test.R"))  
)  
  
result$ok           # did the whole pipeline succeed?  
print(result)       # per-step status table  
```  
  
Retry a flaky operation automatically:  
  
```r  
retry(download.file(url, dest), times = 5)  
```  
  
---  
  
## Core concepts  
  
| Concept | What it is |  
|---|---|  
| `orchrd_result` | Return value of `run_cmd()`/`run_script()`: `list(ok, status, stdout, stderr)`. Has a `print()` method. |  
| `orchrd_pipeline` | Return value of `pipe_exec()`: `$ok`, `$steps` (data frame), `$elapsed_sec`. Has a `print()` method. |  
| `orchrd_secret` | Masked credential from `secret()`. Never prints or logs its value. |  
| Step formula | A one-sided formula `~ expr` (optionally named `name = ~ expr`) passed to `pipe_exec()`. `.x` holds the previous step's output. |  
| Structured errors | Errors stop loudly with clear, ASCII-only messages listing every problem, not just the first. |  
  
---  
  
## Function reference by subsystem  
  
### 1. Running commands and scripts  
  
#### `run_cmd(cmd, args = character(), timeout = NULL, ...)`  
Spawn an external command via `processx::run()`. Returns an `orchrd_result`.  
  
```r  
res <- run_cmd("docker", c("ps", "-a"), timeout = 30)  
if (!res$ok) stop("docker ps failed: ", paste(res$stderr, collapse = "\n"))  
```  
  
- **Beginner:** treat it as a safer `system2()` that never silently swallows errors.  
- **Intermediate:** set `timeout` to guard against hung daemons.  
- **Advanced:** the returned `orchrd_result` is the same shape every command  
  produces, so downstream code can branch on `$ok`/`$status` uniformly.  
  
#### `run_script(path, args = character(), interpreter = NULL, timeout = NULL)`  
Run any script file by auto-detecting the interpreter from the extension  
(`.R` -> `Rscript --vanilla`, `.py` -> `python3`, `.ps1` -> `pwsh -File`,  
`.sh` -> bash, `.qmd` -> `quarto render`). Returns an `orchrd_result`.  
  
```r  
run_script("scripts/etl.py", args = c("--verbose"))  
run_script("report.qmd")           # quarto render  
```  
  
- Interpreter resolution order: explicit `interpreter` arg, then shebang line, then extension.  
  
---  
  
### 2. The pipeline engine  
  
#### `pipe_exec(..., .on_error = c("stop", "continue"), .log_file = NULL)`  
Execute named steps sequentially. Each step receives the previous step's  
output as `.x`. Times each step, logs progress, and returns an  
`orchrd_pipeline`.  
  
```r  
pipe_exec(  
  raw    = ~ readr::read_csv("in.csv"),  
  clean  = ~ dplyr::filter(.x, !is.na(id)),  
  write  = ~ readr::write_csv(.x, "out.csv"),  
  .on_error = "stop",  
  .log_file = "logs/run.json"  
)  
```  
  
- Steps are `~ expr` or `name = ~ expr`; duplicate names are de-duplicated with `make.unique()`.  
- `.on_error = "continue"` records the failure and keeps going; `"stop"` halts (the failed step is still written to the log).  
- `$elapsed_sec` reports total run time.  
  
#### `pipeline_summary(log_file, ...)`  
Aggregate performance across multiple runs from the JSON run logs  
(`pipe_exec(.log_file=)`) and/or NDJSON session logs (`log_config(file=)`).  
Returns `list(runs, success_rate, elapsed, steps, errors, raw)`.  
  
```r  
s <- pipeline_summary("logs/")     # a directory of logs  
s$success_rate  
s$errors                           # data frame of warn/error entries  
```  
  
- In `"auto"` mode, if a directory has both pipeline and session logs, pipeline logs take precedence.  
  
#### `print.orchrd_pipeline(x, ...)`  
S3 print method: shows an `ok` line and the per-step table.  
  
---  
  
### 3. Reliability and control flow  
  
#### `retry(expr, times = 3, wait = 2, backoff = TRUE, max_wait = Inf, jitter = TRUE, on = NULL, silent = FALSE, finally = NULL)`  
Retry any expression with exponential backoff and jitter.  
  
```r  
retry(  
  httr2::req_perform(req),  
  times    = 5,  
  wait     = 2,       # 2s -> 4s -> 8s ...  
  max_wait = 60,      # cap the delay  
  on       = "timeout|refused"   # only retry matching errors  
)  
```  
  
- `backoff = TRUE` doubles the wait each failure; `jitter` adds +/-30% randomness so parallel callers do not synchronize.  
- `on` is a regex matched against the error message; non-matching errors are re-thrown with their original class preserved.  
- `finally` runs after the last attempt regardless of outcome.  
  
#### `retry_labeled(label, expr, ...)`  
Same as `retry()` but prints a `label` first, for readable multi-source output.  
  
```r  
pipe_exec(  
  a = ~ retry_labeled("Source A", get_data("a")),  
  b = ~ retry_labeled("Source B", get_data("b"))  
)  
```  
  
#### `with_rollback(expr, rollback, label = "", verbose = TRUE)`  
Run a step; if (and only if) it fails, run `rollback` and then re-throw the  
original error. For deployment-style workflows.  
  
```r  
with_rollback(  
  expr     = upload_to_server("data/out.parquet"),  
  rollback = delete_from_server("data/out.parquet"),  
  label    = "upload parquet"  
)  
```  
  
#### `deploy_step(deploy_expr, revert_expr = NULL, label = "", verbose = TRUE)`  
Convenience wrapper around `with_rollback()` designed to sit inside `pipe_exec()`.  
  
```r  
pipe_exec(  
  upload = ~ deploy_step(  
    deploy_expr = upload_to_server("out.parquet"),  
    revert_expr = delete_from_server("out.parquet"),  
    label       = "upload"  
  )  
)  
```  
  
---  
  
### 4. Background and batch execution  
  
#### `run_bg(x, ..., .file = NULL)`  
Start a background job (via `callr`) and return a handle. Accepts either a  
function/expression to run in a child R process, or (as used by `tripwire`)  
a pipeline plus forwarded arguments.  
  
```r  
job <- run_bg(function() heavy_computation())  
```  
  
> Requires `callr` in `Imports`.  
  
#### `await(job, timeout = NULL, verbose = TRUE)`  
Block until a `run_bg()` job finishes and return its result.  
  
```r  
result <- await(job)  
```  
  
#### `batch_exec(tasks, n = 4, ...)`  
Run a list of tasks `n` at a time until exhausted (controlled parallelism).  
Ideal for fetching many datasets without overwhelming the network.  
  
```r  
batch_exec(country_tasks, n = 6)  
```  
  
- Internally spawns background jobs via `run_bg()` and awaits them per batch; leftover jobs are killed/awaited and their temp files cleaned up on early stop.  
  
#### `batch_combine(results)`  
`rbind`-combine per-task data frames returned by `batch_exec()` into one frame.  
  
---  
  
### 5. Logging and observability  
  
#### `log_step(message, level = "info", ...)`  
Log a message at a severity level (`debug`, `info`, `warn`, `error`),  
printed via `cli` and optionally written to an NDJSON sink. Brace-safe:  
literal `{}` in messages are not re-interpolated.  
  
```r  
log_step("Loaded 1000 rows", level = "info")  
log_step("API returned 500", level = "error")  
```  
  
#### `with_log(expr, ...)`  
Run an expression inside a logging context so its steps are captured.  
  
#### `log_config(level = "info", file = NULL)`  
Configure the session logger: minimum level and an optional NDJSON file sink.  
  
```r  
log_config(level = "debug", file = "logs/session.ndjson")  
```  
  
#### `get_log()`  
Return the in-memory log entries as a data frame (`timestamp`, `level`, `message`).  
  
```r  
get_log()  
```  
  
- The structured `.data` per entry is preserved in memory and in the NDJSON sink; read it back with `jsonlite::stream_in()`.  
  
---  
  
### 6. Configuration  
  
#### `config_get(key, default = NULL)` / `config_has(key)` / `config_all()` / `config_clear()`  
A small key/value store for pipeline configuration.  
  
```r  
config_get("api_url", default = "https://api.example.com")  
config_has("api_url")  
config_all()      # everything as a list  
config_clear()    # wipe  
```  
  
(If your build also exports `config_set()`, use it to write keys.)  
  
---  
  
### 7. Secrets  
  
#### `secret(name, what = NULL)`  
Read a secret from an environment variable with presence validation,  
log-safety, and masked printing. Returns an `orchrd_secret`.  
  
```r  
key <- secret("AZURE_KEY", what = "Azure Blob access")  
print(key)        # <secret: AZURE_KEY>  -- value never shown  
```  
  
- Errors immediately with a clear message if the variable is unset.  
  
#### `reveal(x)`  
Return the plain string value of an `orchrd_secret`. Call this explicitly  
wherever a bare string is required.  
  
```r  
httr2::req_auth_bearer_token(req, reveal(key))  
```  
  
#### `is_secret(x)`  
`TRUE` if `x` is an `orchrd_secret`.  
  
#### S3 methods `print` / `format` / `as.character` / `str` / `toString` for `orchrd_secret`  
All mask the value (`<secret: NAME>`) so it cannot leak via printing,  
`str()`, `dput()`, or accidental string coercion. To get the real value you  
must call `reveal()`.  
  
---  
  
### 8. Validation  
  
#### `validate_data(data, ...)`  
Run multiple assertions and collect **all** failures, not just the first.  
Pass assertions as formulas so they are evaluated lazily inside the collector.  
  
```r  
validate_data(  
  df,  
  ~ assert_schema(.x, c("id", "value")),  
  ~ assert_no_na(.x, "id"),  
  ~ assert_range(.x, "value", min = 0, max = 100)  
)  
```  
  
> Use the `~ assert_*()` form. A bare `assert_*()` argument evaluates eagerly and fails at the call site (a warning is emitted).  
  
#### `assert_schema(data, cols)`  
Required columns must exist.  
  
#### `assert_range(data, col, min, max)`  
A numeric column must fall within `[min, max]`.  
  
#### `assert_no_na(data, cols)`  
No missing values in the specified columns.  
  
Each `assert_*()` returns `data` invisibly on success, so they chain.  
  
---  
  
### 9. Pre-flight checks and health  
  
#### `need(commands = NULL, envvars = NULL, files = NULL, dirs = NULL, packages = NULL, r_version = NULL)`  
Assert an environment is ready **before** a pipeline runs. Reports every  
missing item at once with actionable install hints.  
  
```r  
need(  
  commands = c("git", "docker"),  
  envvars  = c("API_KEY"),  
  files    = "config.yml",  
  packages = c("dplyr", "httr2")  
)  
```  
  
- Command lookups use PATH (`Sys.which()` / `.which_exe()`), so they resolve Windows `.cmd`/`.bat`/`.exe` wrappers and do not spawn processes.  
  
#### `health_check(targets, ok_status = 400, fail = FALSE, ...)`  
Probe endpoints/services and return a tidy data frame (`target`, `type`,  
`ok`, `status`, `response_ms`). URLs -> HTTP HEAD, `host:port` -> socket  
test, bare names -> command-on-PATH check.  
  
```r  
health_check(c(  
  "https://api.example.com",  
  "db.internal:5432",  
  "git"  
))  
```  
  
- `ok_status = 400` means 4xx/5xx count as failures; pass `ok_status = 500` for "any response under 500 is fine".  
  
---  
  
### 10. Artifacts and checkpoints  
  
#### `store_artifact(object, name, ...)` / `delete_artifact(name)`  
Persist and remove named intermediate outputs.  
(If exported, `list_artifacts()` / `load_artifact()` retrieve them.)  
  
```r  
store_artifact(model, "trained_model")  
delete_artifact("trained_model")  
```  
  
#### `checkpoint(name, expr)` / `step_done(name)` / `clear_checkpoint(name)` / `resume_pipeline(...)`  
Make long pipelines resumable: record completed steps so a rerun skips work  
already done.  
  
```r  
checkpoint("extract", { big_extract() })  
step_done("extract")       # mark complete  
resume_pipeline()          # continue from last incomplete step  
clear_checkpoint("extract")  
```  
  
---  
  
### 11. Notifications  
  
#### `notify(result, channel = c("console", "desktop", "slack", "teams"), ...)`  
Signal pipeline completion. Designed to be piped after `pipe_exec()`.  
Non-console channels require credentials (webhook URL) and fall back to the  
console on failure.  
  
```r  
pipe_exec(...) |> notify(channel = "slack")  
pipe_exec(...) |> notify(channel = "teams")  
```  
  
- Supports desktop toasts (all platforms), Slack webhooks, Teams webhooks, and plain console output.  
  
---  
  
### 12. Docker operations  
  
Docker CLI is cross-platform, so these call `docker` directly (via  
`processx`), not through PowerShell. Each returns a structured result and  
accepts a `timeout`.  
  
#### `diagnose(timeout = ...)`  
Run a suite of Docker health checks and return a report.  
  
#### `clean_docker_storage(timeout = ...)`  
`docker system prune --all --volumes --force`. **Destructive** — may delete  
data in unused volumes.  
  
#### `check_docker_oom(timeout = ...)`  
Inspect containers for out-of-memory kills; returns a parsed  
`id`/`name`/`status` data frame.  
  
#### `force_remove_container(container_name, timeout = ..., verbose = TRUE)`  
`docker rm -f <name>`, with input validation.  
  
```r  
force_remove_container("trsbs-api")  
```  
  
#### Windows-only Docker helpers  
These guard on Windows and use PowerShell where the operation is  
Windows-specific. They return `list(ok, status, stdout, stderr)`.  
  
- `repair_docker(timeout = ..., verbose = TRUE)` — restart a stuck Docker  
  Desktop + WSL.  
- `fix_docker_permissions(user = ...)` — add the current user to the  
  `docker-users` group.  
- `free_docker_port(port)` — free a port held by another process  
  (`Get-NetTCPConnection` is Windows-specific).  
  
---  
  
### 13. Docker scaffolding  
  
Generate reproducible Docker assets for R Shiny, static web, or Node projects.  
  
#### `generate_dockerfile(dir = ".", stack = c("auto", "r-shiny", "static", "node"), ...)`  
Write a stack-aware, reproducible `Dockerfile`.  
  
#### `generate_r_dockerfile(dir = ".")`  
Back-compat wrapper for `stack = "r-shiny"`.  
  
#### `optimize_build_speed(dir = ".")`  
Write a project `.Rprofile` pinning a CRAN mirror for faster installs.  
  
#### `minify_r_dependencies(dir = ".")`  
Write `Rprofile.site` for leaner installs.  
  
#### `secure_secrets(dir = ".")` / `secure_r_secrets(dir = ".")`  
Write/update a `.dockerignore` that excludes secrets and env files.  
  
```r  
generate_dockerfile(stack = "r-shiny")  
optimize_build_speed()  
secure_secrets()  
```  
  
---  
  
### 14. Portal / API debugging  
  
#### `debug_portal_api(portal_container, api_container, tail = 100, timeout = ...)`  
Inspect Docker networking and recent portal/API container logs to diagnose  
frontend-to-backend communication problems. Returns a structured result.  
  
#### `audit_portal_networks(dir = "js")`  
Scan `.js` files for hardcoded `localhost:`/`127.0.0.1:` API references.  
Returns a data frame (`file`, `line`, `text`) and emits one summary warning.  
  
#### `audit_portal_ids(...)`  
Cross-check DOM IDs referenced in JS against those actually present.  
  
---  
  
### 15. Cloud  
  
#### `push_aws(...)`  
Push artifacts/data to AWS (e.g. S3). Requires AWS credentials/CLI on PATH.  
  
---  
  
## End-to-end examples (advanced)  
  
### A resilient, observable ETL pipeline  
  
```r  
library(orchrd)  
  
# 1. Fail fast if the environment is not ready  
need(  
  commands = c("git", "docker"),  
  envvars  = "DB_URL",  
  packages = c("readr", "dplyr", "httr2")  
)  
  
# 2. Configure logging to an NDJSON sink  
log_config(level = "info", file = "logs/etl.ndjson")  
  
# 3. Secrets stay masked  
db <- secret("DB_URL", what = "database connection")  
  
# 4. Run the pipeline with retries, validation, rollback, and a JSON log  
result <- pipe_exec(  
  extract = ~ retry(pull_from_db(reveal(db)), times = 5, on = "timeout"),  
  check   = ~ validate_data(.x,  
                            ~ assert_schema(.x, c("id", "amount")),  
                            ~ assert_no_na(.x, "id")),  
  load    = ~ deploy_step(  
                deploy_expr = upload_to_warehouse(.x),  
                revert_expr = rollback_warehouse(),  
                label       = "load"),  
  .on_error = "stop",  
  .log_file = "logs/etl-run.json"  
)  
  
# 5. Notify + summarize  
result |> notify(channel = "slack")  
pipeline_summary("logs/")  
```  
  
### Controlled parallel fetch of many sources  
  
```r  
tasks <- lapply(country_codes, function(cc) function() fetch_country(cc))  
raw   <- batch_exec(tasks, n = 6)  
combined <- batch_combine(raw)  
```  
  
### Pushing this package to GitHub with `run_cmd()`  
  
```r  
run_cmd("git", c("add", "-A"))  
run_cmd("git", c("commit", "-m", "Update package"))  
run_cmd("git", c("push", "origin", "main"))  
```  
  
---  
  
## Getting help  
  
```r  
?pipe_exec  
?run_cmd  
?retry  
help(package = "orchrd")  
```
