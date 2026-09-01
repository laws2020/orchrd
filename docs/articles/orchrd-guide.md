# orchrd: Workflow Orchestration for R

## Introduction

`orchrd` brings PowerShell’s workflow philosophy into R: simple
commands,  
clean structured outputs, pipeline thinking, retry logic, and  
automation-friendly logging. It is designed as infrastructure for the  
openafrR ecosystem but is useful for any R developer orchestrating  
scripts, APIs, and system processes.

This guide is organized in three tiers so you can enter at your level:

- **Beginner** – run a command, chain a few steps, validate data.  
- **Intermediate** – logging, retries, config, secrets, notifications.  
- **Advanced** – background jobs, batching, rollbacks, checkpoints,  
  Docker scaffolding and diagnostics.

### Installation

``` r

# install.packages("remotes")  
remotes::install_github("laws2020/orchrd")  
  
library(orchrd)  
```

### The two core return types

Almost everything in `orchrd` returns one of two predictable shapes,
so  
you never have to guess what you got back.

| Class | Returned by | Key fields |
|----|----|----|
| `orchrd_result` | [`run_cmd()`](https://laws2020.github.io/orchrd/reference/run_cmd.md), [`run_script()`](https://laws2020.github.io/orchrd/reference/run_script.md) | `$ok`, `$status`, `$stdout`, `$stderr` |
| `orchrd_pipeline` | [`pipe_exec()`](https://laws2020.github.io/orchrd/reference/pipe_exec.md) | `$ok`, `$steps` (data frame), `$elapsed_sec` |

Both have [`print()`](https://rdrr.io/r/base/print.html) methods, so
inspecting them in the console is clean.

------------------------------------------------------------------------

## Beginner

### Running a single command: `run_cmd()`

[`run_cmd()`](https://laws2020.github.io/orchrd/reference/run_cmd.md)
spawns an external process via
[`processx::run()`](http://processx.r-lib.org/reference/run.md) and
returns a  
structured `orchrd_result`. You never parse raw text or guess exit
codes.

``` r

res <- run_cmd("git", c("status", "--short"))  
  
res$ok        # TRUE if exit status was 0  
res$status    # integer exit code  
res$stdout    # character vector of stdout lines  
res$stderr    # character vector of stderr lines  
```

**Why not [`system2()`](https://rdrr.io/r/base/system2.html)?**
[`run_cmd()`](https://laws2020.github.io/orchrd/reference/run_cmd.md)
gives you separated stdout/stderr, a  
timeout, and a consistent object you can test with `res$ok` instead of  
inspecting attributes.

### Running a script file: `run_script()`

[`run_script()`](https://laws2020.github.io/orchrd/reference/run_script.md)
detects the file extension and invokes the right  
interpreter automatically – R, Python, PowerShell, bash, or Quarto.

``` r

run_script("analysis.R")          # -> Rscript --vanilla  
run_script("clean.py")            # -> python3  
run_script("deploy.ps1")          # -> pwsh -NoProfile -NonInteractive -File  
run_script("report.qmd")          # -> quarto render  
```

You never need to remember the exact interpreter flags; one call
handles  
all of them and returns the same `orchrd_result` as
[`run_cmd()`](https://laws2020.github.io/orchrd/reference/run_cmd.md).

### Chaining steps: `pipe_exec()`

[`pipe_exec()`](https://laws2020.github.io/orchrd/reference/pipe_exec.md)
is the heart of the package. Each step is a one-sided  
formula (`~ expr`) or a named formula (`name = ~ expr`). The special  
symbol `.x` holds the output of the previous step.

``` r

result <- pipe_exec(  
  fetch   = ~ read.csv("input.csv"),  
  clean   = ~ subset(.x, !is.na(value)),  
  summary = ~ aggregate(value ~ group, .x, mean)  
)  
  
result$ok            # TRUE if every step succeeded  
result$steps         # data frame: name, ok, elapsed, message  
result$elapsed_sec   # total run time  
```

Each step is timed, logged, and error-handled. Inspect the run with  
`print(result)`.

### Validating data inline: `validate_data()` and asserts

Quick, inline assertions that fail loudly with clear messages. Not a  
replacement for a full framework – meant to catch obvious problems
early.

``` r

validate_data(  
  df,  
  schema = ~ assert_schema(.x, c("id", "value", "group")),  
  bounds = ~ assert_range(.x, "value", min = 0, max = 100),  
  filled = ~ assert_no_na(.x, c("id", "value"))  
)  
```

- `assert_schema(data, cols)` – required columns must exist.  
- `assert_range(data, col, min, max)` – numeric column within bounds.  
- `assert_no_na(data, cols)` – no missing values in the named columns.

Wrap each rule as a formula (`~ assert_*()`) so
[`validate_data()`](https://laws2020.github.io/orchrd/reference/validate_data.md)
can  
collect **all** failures instead of stopping at the first.

------------------------------------------------------------------------

## Intermediate

### Observability: `log_step()`, `with_log()`, `log_config()`, `get_log()`

Make any workflow observable. Log at a severity level, print via
`cli`,  
and optionally write NDJSON to a file for later analysis.

``` r

log_config(level = "debug", file = "run.ndjson")   # configure the session logger  
  
with_log("nightly refresh", {  
  log_step("Starting fetch", level = "info")  
  data <- fetch_data()  
  log_step("Fetched rows", level = "debug", data = list(n = nrow(data)))  
})  
  
get_log()   # data frame of timestamp, level, message for the session  
```

[`get_log()`](https://laws2020.github.io/orchrd/reference/get_log.md)
returns a tidy data frame; the full structured `.data` per  
entry is preserved in the NDJSON sink for
[`jsonlite::stream_in()`](https://jeroen.r-universe.dev/jsonlite/reference/stream_in.html).

### Retrying flaky work: `retry()` and `retry_labeled()`

Wrap any expression with automatic retry logic: exponential backoff,  
random jitter, a `max_wait` cap, and pattern-matched error conditions.

``` r

retry(  
  httr2::req_perform(req),  
  times    = 5,  
  wait     = 2,       # 2s, 4s, 8s ... (doubles)  
  max_wait = 30,      # cap the delay  
  jitter   = TRUE,    # +/- 30% so parallel callers do not sync up  
  on       = "timeout|HTTP 5"   # only retry matching errors  
)  
  
# Labeled variant prints a header, ideal inside pipe_exec():  
pipe_exec(  
  a = ~ retry_labeled("Source A", get_data("a")),  
  b = ~ retry_labeled("Source B", get_data("b"))  
)  
```

### Configuration: the `config_*` family

Read and manage layered configuration for a pipeline.

``` r

config_get("api_url")     # fetch one key  
config_has("token")       # TRUE / FALSE  
config_all()              # everything as a list  
config_clear()            # reset  
```

### Secrets: `secret()`, `reveal()`, `is_secret()`

Read secrets from environment variables with three guarantees plain  
[`Sys.getenv()`](https://rdrr.io/r/base/Sys.getenv.html) does not give
you: presence validation, log safety, and  
masked printing.

``` r

key <- secret("AZURE_KEY")   # errors immediately if unset  
key                          # prints as <secret: AZURE_KEY>, never the value  
is_secret(key)               # TRUE  
  
reveal(key)                  # the only way to get the plain string  
```

Because printing and
[`as.character()`](https://rdrr.io/r/base/character.html) are masked,
secrets will not leak  
through [`str()`](https://rdrr.io/r/utils/str.html),
[`dput()`](https://rdrr.io/r/base/dput.html), logs, or accidental
console echo. Pass  
`reveal(key)` explicitly to any function that needs the raw value.

### Completion signals: `notify()`

Signal when an unattended pipeline finishes. Supports desktop  
notifications, Slack, Microsoft Teams, and plain console output.

``` r

pipe_exec(  
  build  = ~ run_script("build.R"),  
  deploy = ~ run_script("deploy.R")  
) |>  
  notify(channel = "slack", webhook = reveal(secret("SLACK_WEBHOOK")))  
```

Non-console channels fall back to the console on failure, so a broken  
webhook never silently swallows the completion signal.

### Pre-flight checks: `need()` and `health_check()`

Fail fast, before a single step runs.

``` r

# Assert the environment is ready (commands, env vars, files, packages)  
need(  
  commands = c("git", "docker"),  
  env      = c("AWS_REGION"),  
  files    = c("config.yml"),  
  packages = c("httr2", "jsonlite")  
)  
  
# Probe that external services are reachable  
health_check(c(  
  "https://api.example.com",  
  "db.internal:5432",  
  "docker"  
))  
```

[`need()`](https://laws2020.github.io/orchrd/reference/need.md) lists
**every** missing item at once (not just the first) and  
includes install hints for well-known commands.
[`health_check()`](https://laws2020.github.io/orchrd/reference/health_check.md)
returns  
a tidy data frame with a `type` column and `response_ms` timings.

------------------------------------------------------------------------

## Advanced

### Reactive automation

`orchrd` also watches the world and reacts to it: filesystem events
and  
cron-style time events, both from a single in-session API. Watchers
are  
backed by a compiled C++ layer (inotify on Linux,
ReadDirectoryChangesW  
on Windows, kqueue on macOS); schedules run on R’s event loop via
`later`.

### React to files: `fire_on()` and the `on_*()` verbs

`fire_on(event, path, action, ...)` binds an action to a filesystem  
event. `action` is either a function `(event, path)` or a one-sided  
formula `~ expr` where `.path` and `.event` are bound.

``` r

# Formula shorthand  
on_arrive("~/nbs_drops/", pattern = "\\.xlsx$",  
          action = ~ message("File arrived: ", .path))  
  
# Function form  
on_change("~/configs/pipeline.yml",  
          action = function(event, path) reload_config(path))  
```

Event verbs:
[`on_arrive()`](https://laws2020.github.io/orchrd/reference/on_arrive.md)
(created),
[`on_change()`](https://laws2020.github.io/orchrd/reference/on_change.md)
(modified),  
[`on_leave()`](https://laws2020.github.io/orchrd/reference/on_leave.md)
(deleted),
[`on_rename()`](https://laws2020.github.io/orchrd/reference/on_rename.md)
(renamed). Each returns a watcher  
ID invisibly. Low-level
[`watch_dir()`](https://laws2020.github.io/orchrd/reference/watch_dir.md)
/
[`watch_file()`](https://laws2020.github.io/orchrd/reference/watch_file.md)
sit underneath.

### React to time: `on_schedule()`

Register a recurring in-session timer with a 5-field cron expression  
(`min hour dom mon dow`). It never blocks the session and needs no  
system cron. Requires the `later` package.

``` r

on_schedule("0 8 * * *",  action = ~ fetch_cbn_rates())        # 08:00 daily  
on_schedule("*/15 9-17 * * 1-5", action = ~ log_step("beat"))  # every 15m, Mon-Fri  
```

### Safety conditions: `guard()`, `disk_ok()`, `mem_ok()`, `net_ok()`

`guard(id, condition, message, on_fail)` wraps a watcher’s callback so
it  
only fires when `condition()` is `TRUE`; otherwise the event is logged  
and `on_fail` (`"warn"`, `"stop"`, or `"silent"`) is taken.

``` r

id <- on_arrive("~/cbn_feeds/", action = ~ fetch_rates(.path))  
  
guard(id, condition = ~ disk_ok(threshold = 0.90),  
      message = "Disk > 90% full - skipping fetch")  
guard(id, condition = ~ net_ok(), message = "No network")  
```

### Rate control: `throttle()`

Debounce fires at the trailing edge of a burst; `throttle(id, ms)`
fires  
immediately on the first event then suppresses re-fires for `ms`.

``` r

throttle(id, ms = 30000)   # fire once, ignore re-drops for 30s  
```

### Manage watchers

``` r

watcher_list()      # active watchers as a data frame  
watcher_status(id)  # one watcher's state  
watcher_pause(id); watcher_resume(id)  
watcher_log()       # recent events (FIRED / GUARDED / THROTTLED / errors)  
unwatch(id)         # stop one  
unwatch_all()       # stop all  
```

### Pipeline bridge: `pipe_on_arrive()`, `pipe_on_change()`, `health_report()`

Dispatch a full `orchrd` pipeline in the background the moment a file  
lands, and print a system-health summary.

``` r

pipe_on_arrive("~/drops/", pipeline = function(.file) run_script(.file))  
health_report()     # disk / memory / network status  
```

### Background jobs: `run_bg()` and `await()`

[`run_bg()`](https://laws2020.github.io/orchrd/reference/run_bg.md)
launches a job in a background R process (via `callr`) and  
returns immediately;
[`await()`](https://laws2020.github.io/orchrd/reference/await.md) blocks
until it finishes and collects the  
result. These are the primitives
[`batch_exec()`](https://laws2020.github.io/orchrd/reference/batch_exec.md)
and tripwire’s  
[`orchrd::run_bg()`](https://laws2020.github.io/orchrd/reference/run_bg.md)
bridge build on.

``` r

job <- run_bg(~ heavy_computation(big_data))  
# ... do other work ...  
result <- await(job)          # blocks until done, returns the value  
```

### Controlled parallelism: `batch_exec()` and `batch_combine()`

Run a list of tasks N at a time until exhausted – for example,
fetching  
54 country datasets without overwhelming the network.

``` r

tasks <- lapply(country_codes, function(code) {  
  function() fetch_country(code)  
})  
  
results <- batch_exec(tasks, workers = 4)   # 4 at a time  
combined <- batch_combine(results)          # rbind the per-task frames  
```

[`batch_exec()`](https://laws2020.github.io/orchrd/reference/batch_exec.md)
spawns via
[`run_bg()`](https://laws2020.github.io/orchrd/reference/run_bg.md) and
cleans up leftover jobs (kill or  
`await`) if it stops early.

### Rollback on failure: `with_rollback()` and `deploy_step()`

For deployment-style workflows: if a step fails, undo what it did
before  
the error propagates. If the step succeeds, the rollback never runs.

``` r

pipe_exec(  
  upload = ~ deploy_step(  
    deploy_expr = upload_to_server("out.parquet"),  
    revert_expr = delete_from_server("out.parquet"),  
    label       = "upload parquet"  
  )  
)  
```

### Resumable pipelines: checkpoints

[`checkpoint()`](https://laws2020.github.io/orchrd/reference/checkpoint.md),
[`step_done()`](https://laws2020.github.io/orchrd/reference/step_done.md),
[`resume_pipeline()`](https://laws2020.github.io/orchrd/reference/resume_pipeline.md),
and  
[`clear_checkpoint()`](https://laws2020.github.io/orchrd/reference/clear_checkpoint.md)
let a long pipeline skip already-completed steps on  
a re-run.

``` r

checkpoint("fetch")           # mark progress  
step_done("fetch")            # query whether a step already ran  
resume_pipeline()             # continue from the last checkpoint  
clear_checkpoint()            # start fresh  
```

### Artifacts: `store_artifact()`, `delete_artifact()`, `push_aws()`

Persist and move intermediate outputs.

``` r

store_artifact(model, "model-v1")  
push_aws("model-v1", bucket = "s3://my-bucket/models")  
delete_artifact("model-v1")  
```

### Metrics: `pipeline_summary()`

Aggregate performance across multiple runs by reading the NDJSON logs  
written by `log_config(file=)` and/or the JSON run logs from  
`pipe_exec(.log_file=)`.

``` r

summ <- pipeline_summary("logs/")  
summ$runs           # number of runs  
summ$success_rate   # fraction of steps that succeeded  
summ$elapsed        # timing distribution  
summ$errors         # data frame of warn/error entries  
```

### Docker scaffolding

Generate reproducible Docker assets for any project stack.

``` r

generate_dockerfile(stack = "r-shiny")   # stack-aware Dockerfile  
optimize_build_speed()                   # project .Rprofile with CRAN mirror  
minify_r_dependencies()                  # leaner Rprofile.site  
secure_secrets()                         # .dockerignore excluding secrets  
```

### Docker diagnostics and maintenance

Cross-platform Docker operations (the Docker CLI is invoked directly,
not  
through PowerShell) plus Windows-only recovery helpers.

``` r

diagnose()                          # overall Docker health report  
check_docker_oom()                  # containers killed for out-of-memory  
clean_docker_storage()              # docker system prune (careful: volumes)  
force_remove_container("trsbs-api") # docker rm -f  
free_docker_port(8080)              # Windows: find and free a held port  
debug_portal_api("portal", "api")  # inspect networking + recent logs  
  
# Windows-only Docker Desktop recovery:  
repair_docker()                     # restart Docker Desktop + WSL  
fix_docker_permissions()            # add user to docker-users group  
```

The
[`repair_docker()`](https://laws2020.github.io/orchrd/reference/repair_docker.md)
and
[`fix_docker_permissions()`](https://laws2020.github.io/orchrd/reference/fix_docker_permissions.md)
helpers guard on OS  
and error clearly on non-Windows systems.

------------------------------------------------------------------------
