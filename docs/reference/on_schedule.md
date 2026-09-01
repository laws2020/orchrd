# Schedule an action on a cron-style time expression

Registers a recurring in-session timer that fires `action` whenever the
current time matches the cron expression. The timer runs on R's event
loop via
[`later::later()`](https://later.r-lib.org/reference/later.html): it
does not block the session and needs no system cron or root access.

## Usage

``` r
on_schedule(cron, action, id = NULL, tz = "")
```

## Arguments

- cron:

  Character. A 5-field cron expression (`"min hour dom mon dow"`). See
  Details.

- action:

  A zero-argument function or a one-sided formula `~ expr`.

- id:

  Optional character ID. Auto-generated when `NULL`.

- tz:

  Time zone for schedule evaluation. Default `""` (system).

## Value

Invisibly returns the schedule ID. Pass to
[`unwatch()`](https://laws2020.github.io/orchrd/reference/unwatch.md) to
cancel.

## Details

The returned ID is compatible with
[`unwatch()`](https://laws2020.github.io/orchrd/reference/unwatch.md) so
teardown is consistent with filesystem watchers.

Cron fields (left to right): minute (0-59), hour (0-23), day-of-month
(1-31), month (1-12), day-of-week (0-6, 0 = Sunday).

Supported syntax per field:

- `*`:

  Every value.

- `N`:

  Exactly N.

- `*/N`:

  Every N-th value, stepping from the field minimum.

- `N,M,...`:

  Explicit list.

- `N-M`:

  Inclusive range.

## See also

[`unwatch()`](https://laws2020.github.io/orchrd/reference/unwatch.md),
[`on_arrive()`](https://laws2020.github.io/orchrd/reference/on_arrive.md)

## Examples

``` r
if (FALSE) { # \dontrun{
on_schedule("0 8 * * *", action = ~ fetch_cbn_rates())
on_schedule("*/15 9-17 * * 1-5",
            action = function() log_step("Heartbeat check"))
id <- on_schedule("* * * * *", action = ~ message(Sys.time()))
unwatch(id)
} # }
```
