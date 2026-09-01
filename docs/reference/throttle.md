# Throttle a watcher's callback (fire-first, suppress for N ms)

Wraps the existing callback so it fires immediately on the first event,
then suppresses subsequent firings for `ms` milliseconds. This is the
complement of the built-in debounce (which fires at the trailing edge).

## Usage

``` r
throttle(id, ms = 1000)
```

## Arguments

- id:

  Character. Watcher ID to throttle.

- ms:

  Numeric. Suppression window in milliseconds. Default `1000`.

## Value

Invisibly `TRUE`.

## See also

[`guard()`](https://laws2020.github.io/orchrd/reference/guard.md),
[`on_arrive()`](https://laws2020.github.io/orchrd/reference/on_arrive.md)

## Examples

``` r
if (FALSE) { # \dontrun{
id <- on_arrive("~/cbn_feeds/", action = function(event, path) {
  fetch_cbn_rates(path)
})
throttle(id, ms = 30000)  # fire once, then ignore re-drops for 30s
} # }
```
