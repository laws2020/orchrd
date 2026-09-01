# Simulate a filesystem event on a watcher (dry-run)

Directly invokes the watcher's current callback with a synthetic event
and path, bypassing the C++ filesystem layer. All guards and throttles
attached to the watcher are evaluated as normal.

## Usage

``` r
watcher_test(id, event = "created", path = NULL, silent = FALSE)
```

## Arguments

- id:

  Character. Watcher ID to test.

- event:

  Character. Event type to simulate: "arrive"/"created",
  "change"/"modified", "leave"/"deleted", "rename"/"renamed". Default
  "created".

- path:

  Character. Synthetic file path passed to the callback. Defaults to
  "\<watcher_path\>/test_event.tmp".

- silent:

  Logical. If TRUE, suppress the informational message printed before
  firing. Useful in testthat. Default FALSE.

## Value

Invisibly returns the value returned by the callback, or NULL if the
callback was blocked by a guard or raised an error.

## See also

[`schedule_test()`](https://laws2020.github.io/orchrd/reference/schedule_test.md),
[`fire_on()`](https://laws2020.github.io/orchrd/reference/fire_on.md)

## Examples

``` r
if (FALSE) { # \dontrun{
id <- on_arrive("~/nbs_drops/", action = function(event, path) {
  message("Pipeline triggered for: ", path)
})
watcher_test(id)
watcher_test(id, event = "created", path = "~/nbs_drops/q3_labour.xlsx")
} # }
```
