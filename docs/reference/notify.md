# Send a notification when a pipeline finishes

Sends a message when an `orchrd_pipeline` result is passed to it.
Designed to be piped after
[`pipe_exec()`](https://laws2020.github.io/orchrd/reference/pipe_exec.md)
so unattended pipelines signal completion without manual checking.

## Usage

``` r
notify(
  result,
  on_success = "Pipeline complete: {n_steps} steps, {elapsed}s",
  on_failure = "Pipeline failed. Step(s) with errors: {failed_steps}",
  via = "console",
  webhook = NULL,
  title = "orchrd pipeline",
  timeout = 10,
  ...
)
```

## Arguments

- result:

  An `orchrd_pipeline` object from
  [`pipe_exec()`](https://laws2020.github.io/orchrd/reference/pipe_exec.md).

- on_success:

  Character. Message to send on full success.

- on_failure:

  Character. Message to send when any step failed.

- via:

  Character vector. One or more of `"console"` (default), `"desktop"`,
  `"slack"`, `"teams"`.

- webhook:

  An `orchrd_secret` or character. Webhook URL for Slack or Teams. Use
  [`secret()`](https://laws2020.github.io/orchrd/reference/secret.md) to
  pass this safely.

- title:

  Character. Notification title. Default `"orchrd pipeline"`.

- timeout:

  Numeric. Seconds before a webhook request is abandoned. Default `10`.

- ...:

  Reserved for future channel-specific arguments.

## Value

The `result` object, invisibly, so `notify()` can end a chain.

## Details

Supports desktop notifications (all platforms), Slack webhooks,
Microsoft Teams webhooks, and plain console output. More than one
channel may be supplied to `via`; all channels except `"console"`
require a webhook or the relevant system tool.

Message strings support glue-style interpolation. Available variables:

- `{ok}` - TRUE/FALSE

- `{n_steps}` - total number of steps

- `{n_failed}` - number of failed steps

- `{elapsed}` - total elapsed seconds across all steps

- `{failed_steps}` - comma-separated names of failed steps
