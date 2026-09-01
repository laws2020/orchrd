# Package index

## Pipeline Engine

Build, execute, resume, and inspect sequential workflows.

- [`pipe_exec()`](https://laws2020.github.io/orchrd/reference/pipe_exec.md)
  : Execute a named pipeline of steps sequentially
- [`pipeline_summary()`](https://laws2020.github.io/orchrd/reference/pipeline_summary.md)
  : Summarise pipeline performance across multiple runs
- [`resume_pipeline()`](https://laws2020.github.io/orchrd/reference/resume_pipeline.md)
  : Load a saved checkpoint value
- [`step_done()`](https://laws2020.github.io/orchrd/reference/step_done.md)
  : Check whether a checkpoint has already been saved

## Command & Script Execution

Run external commands and scripts through one structured interface.

- [`run_cmd()`](https://laws2020.github.io/orchrd/reference/run_cmd.md)
  : Run a system command cleanly
- [`run_script()`](https://laws2020.github.io/orchrd/reference/run_script.md)
  : Run an external script file

## Background & Batch Execution

Run background jobs and execute tasks with controlled parallelism.

- [`run_bg()`](https://laws2020.github.io/orchrd/reference/run_bg.md) :
  Run a function or pipeline in the background
- [`await()`](https://laws2020.github.io/orchrd/reference/await.md) :
  Wait for a background job and return its result
- [`batch_exec()`](https://laws2020.github.io/orchrd/reference/batch_exec.md)
  : Execute a list of tasks in controlled parallel batches
- [`batch_combine()`](https://laws2020.github.io/orchrd/reference/batch_combine.md)
  : Row-bind the successful data-frame results of a batch_exec() run

## Reliability & Control Flow

Retry operations, perform rollback actions, and create deployment steps.

- [`retry()`](https://laws2020.github.io/orchrd/reference/retry.md) :
  Retry an expression on failure
- [`retry_labeled()`](https://laws2020.github.io/orchrd/reference/retry_labeled.md)
  : Retry with a descriptive label
- [`with_rollback()`](https://laws2020.github.io/orchrd/reference/with_rollback.md)
  : Execute a step with an automatic rollback on failure
- [`deploy_step()`](https://laws2020.github.io/orchrd/reference/deploy_step.md)
  : Create a reversible deployment step

## Checkpoints

Persist workflow progress and resume interrupted pipelines.

- [`checkpoint()`](https://laws2020.github.io/orchrd/reference/checkpoint.md)
  : Save a pipeline step result as a checkpoint
- [`list_checkpoints()`](https://laws2020.github.io/orchrd/reference/list_checkpoints.md)
  : List all saved checkpoints
- [`clear_checkpoint()`](https://laws2020.github.io/orchrd/reference/clear_checkpoint.md)
  : Remove a saved checkpoint

## Artifacts

Persist, retrieve, inspect, and remove workflow artifacts.

- [`store_artifact()`](https://laws2020.github.io/orchrd/reference/store_artifact.md)
  : Store a pipeline output as a named artifact
- [`load_artifact()`](https://laws2020.github.io/orchrd/reference/load_artifact.md)
  : Load a previously stored artifact
- [`list_artifacts()`](https://laws2020.github.io/orchrd/reference/list_artifacts.md)
  : List all stored artifacts
- [`delete_artifact()`](https://laws2020.github.io/orchrd/reference/delete_artifact.md)
  : Delete a stored artifact

## Logging & Observability

Add structured logging and inspect workflow execution history.

- [`log_step()`](https://laws2020.github.io/orchrd/reference/log_step.md)
  : Log a workflow step
- [`with_log()`](https://laws2020.github.io/orchrd/reference/with_log.md)
  : Execute an expression with automatic entry and exit logging
- [`log_config()`](https://laws2020.github.io/orchrd/reference/log_config.md)
  : Configure session-wide logging
- [`get_log()`](https://laws2020.github.io/orchrd/reference/get_log.md)
  : Retrieve the in-memory session log

## Validation

Validate data and enforce simple structural and quality constraints.

- [`validate_data()`](https://laws2020.github.io/orchrd/reference/validate_data.md)
  : Run multiple validation assertions on a data frame
- [`assert_schema()`](https://laws2020.github.io/orchrd/reference/assert_schema.md)
  : Assert that required columns exist in a data frame
- [`assert_range()`](https://laws2020.github.io/orchrd/reference/assert_range.md)
  : Assert that a numeric column's values fall within a range
- [`assert_no_na()`](https://laws2020.github.io/orchrd/reference/assert_no_na.md)
  : Assert that specified columns contain no missing values

## Environment & Diagnostics

Verify the execution environment and diagnose system health.

- [`need()`](https://laws2020.github.io/orchrd/reference/need.md) :
  Assert that a pipeline's environment is ready
- [`health_check()`](https://laws2020.github.io/orchrd/reference/health_check.md)
  : Check that endpoints and services are alive
- [`health_report()`](https://laws2020.github.io/orchrd/reference/health_report.md)
  : Run all built-in health checks and return a summary
- [`diagnose()`](https://laws2020.github.io/orchrd/reference/diagnose.md)
  : Diagnose Docker Infrastructure

## Configuration

Manage layered configuration values used by workflows.

- [`config_get()`](https://laws2020.github.io/orchrd/reference/config_get.md)
  : Retrieve a configuration value
- [`config_all()`](https://laws2020.github.io/orchrd/reference/config_all.md)
  : Return the full in-memory config
- [`config_has()`](https://laws2020.github.io/orchrd/reference/config_has.md)
  : Check whether a configuration key exists
- [`config_clear()`](https://laws2020.github.io/orchrd/reference/config_clear.md)
  : Clear the in-memory config
- [`load_config()`](https://laws2020.github.io/orchrd/reference/load_config.md)
  : Load a configuration file into memory

## Secrets

Safely retrieve, mask, inspect, and reveal sensitive values.

- [`secret()`](https://laws2020.github.io/orchrd/reference/secret.md) :
  Retrieve a secret environment variable safely
- [`reveal()`](https://laws2020.github.io/orchrd/reference/reveal.md) :
  Reveal the raw value of a secret
- [`is_secret()`](https://laws2020.github.io/orchrd/reference/is_secret.md)
  : Test whether an object is an orchrd_secret
- [`secure_secrets()`](https://laws2020.github.io/orchrd/reference/secure_secrets.md)
  [`secure_r_secrets()`](https://laws2020.github.io/orchrd/reference/secure_secrets.md)
  : Create a .dockerignore that keeps secrets out of the build context

## Notifications

Signal workflow completion through supported notification channels.

- [`notify()`](https://laws2020.github.io/orchrd/reference/notify.md) :
  Send a notification when a pipeline finishes

## Filesystem Watchers

React to files being created, modified, deleted, or renamed.

- [`watch_dir()`](https://laws2020.github.io/orchrd/reference/watch_dir.md)
  : Watch a directory for filesystem events
- [`watch_file()`](https://laws2020.github.io/orchrd/reference/watch_file.md)
  : Watch a single file for filesystem events
- [`fire_on()`](https://laws2020.github.io/orchrd/reference/fire_on.md)
  : Bind an action to a filesystem event
- [`on_arrive()`](https://laws2020.github.io/orchrd/reference/on_arrive.md)
  : Trigger action when a file arrives (is created)
- [`on_change()`](https://laws2020.github.io/orchrd/reference/on_change.md)
  : Trigger action when a file is modified
- [`on_leave()`](https://laws2020.github.io/orchrd/reference/on_leave.md)
  : Trigger action when a file is deleted
- [`on_rename()`](https://laws2020.github.io/orchrd/reference/on_rename.md)
  : Trigger action when a file is renamed
- [`unwatch()`](https://laws2020.github.io/orchrd/reference/unwatch.md)
  : Stop a watcher
- [`unwatch_all()`](https://laws2020.github.io/orchrd/reference/unwatch_all.md)
  : Stop all active watchers
- [`watcher_test()`](https://laws2020.github.io/orchrd/reference/watcher_test.md)
  : Simulate a filesystem event on a watcher (dry-run)

## Scheduling

Register cron-style time-based triggers inside an R session.

- [`on_schedule()`](https://laws2020.github.io/orchrd/reference/on_schedule.md)
  : Schedule an action on a cron-style time expression
- [`schedule_test()`](https://laws2020.github.io/orchrd/reference/schedule_test.md)
  : Simulate a cron schedule firing immediately

## Guards & Throttling

Control when callbacks execute and prevent excessive event firing.

- [`guard()`](https://laws2020.github.io/orchrd/reference/guard.md) :
  Attach a safety condition to a watcher
- [`throttle()`](https://laws2020.github.io/orchrd/reference/throttle.md)
  : Throttle a watcher's callback (fire-first, suppress for N ms)
- [`disk_ok()`](https://laws2020.github.io/orchrd/reference/disk_ok.md)
  : Check available disk space
- [`mem_ok()`](https://laws2020.github.io/orchrd/reference/mem_ok.md) :
  Check available system memory
- [`net_ok()`](https://laws2020.github.io/orchrd/reference/net_ok.md) :
  Check network reachability

## Pipeline Integration

Connect filesystem events directly to orchrd pipelines.

- [`pipe_on_arrive()`](https://laws2020.github.io/orchrd/reference/pipe_on_arrive.md)
  : Fire an orchrd pipeline when a file arrives
- [`pipe_on_change()`](https://laws2020.github.io/orchrd/reference/pipe_on_change.md)
  : Re-run an orchrd pipeline when a config or data file changes

## Docker Operations

Diagnose, repair, maintain, and troubleshoot Docker environments.

- [`diagnose()`](https://laws2020.github.io/orchrd/reference/diagnose.md)
  : Diagnose Docker Infrastructure
- [`check_docker_oom()`](https://laws2020.github.io/orchrd/reference/check_docker_oom.md)
  : Detect Out-of-Memory (OOM) Crashes
- [`clean_docker_storage()`](https://laws2020.github.io/orchrd/reference/clean_docker_storage.md)
  : Clean Docker Storage Bloat
- [`force_remove_container()`](https://laws2020.github.io/orchrd/reference/force_remove_container.md)
  : Force Delete a Stuck Container
- [`free_docker_port()`](https://laws2020.github.io/orchrd/reference/free_docker_port.md)
  : Free Up a Blocked Port (Windows)
- [`repair_docker()`](https://laws2020.github.io/orchrd/reference/repair_docker.md)
  : Repair a Stuck Docker Engine (Windows)
- [`fix_docker_permissions()`](https://laws2020.github.io/orchrd/reference/fix_docker_permissions.md)
  : Fix Docker Named Pipe Permissions (Windows)
- [`debug_portal_api()`](https://laws2020.github.io/orchrd/reference/debug_portal_api.md)
  : Debug Portal and API Communication

## Docker & Build Scaffolding

Generate Docker assets and optimise R project builds.

- [`generate_dockerfile()`](https://laws2020.github.io/orchrd/reference/generate_dockerfile.md)
  [`generate_r_dockerfile()`](https://laws2020.github.io/orchrd/reference/generate_dockerfile.md)
  : Auto-generate an optimized, reproducible Dockerfile for any project
- [`minify_r_dependencies()`](https://laws2020.github.io/orchrd/reference/minify_r_dependencies.md)
  : Write leaner R install/runtime settings for containers
- [`optimize_build_speed()`](https://laws2020.github.io/orchrd/reference/optimize_build_speed.md)
  : Point a project at a fast, reliable CRAN mirror

## Portal Auditing

Audit portal frontend identifiers and network configuration.

- [`audit_portal_ids()`](https://laws2020.github.io/orchrd/reference/audit_portal_ids.md)
  : Audit Portal HTML IDs Against JavaScript References
- [`audit_portal_networks()`](https://laws2020.github.io/orchrd/reference/audit_portal_networks.md)
  : Audit Portal JavaScript for localhost API References

## Cloud

Deploy artifacts and workflows to cloud infrastructure.

- [`push_aws()`](https://laws2020.github.io/orchrd/reference/push_aws.md)
  : Sync a local directory to S3 via the AWS CLI
