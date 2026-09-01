# Attach a safety condition to a watcher

Wraps the watcher's existing callback so it only fires when
`condition()` returns `TRUE`. If the condition fails, the event is
logged and the `on_fail` action is taken instead.

## Usage

``` r
guard(
  id,
  condition,
  message = "Guard condition failed",
  on_fail = c("warn", "stop", "silent")
)
```

## Arguments

- id:

  Character. Watcher ID to protect.

- condition:

  A zero-argument function that returns `TRUE` (safe to fire) or `FALSE`
  (hold back), or a one-sided formula `~ expr`.

- message:

  Character. Human-readable reason shown when the guard blocks the
  callback.

- on_fail:

  One of `"warn"` (default), `"stop"`, or `"silent"`. What to do when
  the guard blocks.

## Value

Invisibly `TRUE`.

## Details

Multiple guards can be attached to the same watcher. They are evaluated
in the order they were added, and *all* must pass for the callback to
fire.

## See also

[`throttle()`](https://laws2020.github.io/orchrd/reference/throttle.md),
[`disk_ok()`](https://laws2020.github.io/orchrd/reference/disk_ok.md),
[`mem_ok()`](https://laws2020.github.io/orchrd/reference/mem_ok.md),
[`net_ok()`](https://laws2020.github.io/orchrd/reference/net_ok.md)

## Examples

``` r
if (FALSE) { # \dontrun{
id <- on_arrive("~/cbn_feeds/", action = function(event, path) {
  opennaijR::fetch("NGA", "inflation")
})

# Only fetch if disk is not critically full
guard(id,
      condition = ~ disk_ok(threshold = 0.90),
      message   = "Disk over 90 percent full - skipping fetch")

# Only fetch if available memory > 500 MB
guard(id,
      condition = ~ mem_ok(min_mb = 500),
      message   = "Low memory - pipeline paused")
} # }
```
