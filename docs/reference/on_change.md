# Trigger action when a file is modified

Shorthand for `fire_on("change", ...)`.

## Usage

``` r
on_change(
  path,
  action,
  pattern = NULL,
  recursive = FALSE,
  debounce = 500L,
  id = NULL
)
```

## Arguments

- path:

  Character. Directory (or file) to watch.

- action:

  A function accepting (event, path), OR a one-sided formula ~ expr
  where .path and .event are available as bindings.

- pattern:

  Optional regex for matching filenames. NULL matches all.

- recursive:

  Watch subdirectories? Default FALSE.

- debounce:

  Milliseconds debounce window. Default 500L.

- id:

  Optional watcher ID.

## Value

Invisibly returns the watcher ID.

## See also

[`fire_on()`](https://laws2020.github.io/orchrd/reference/fire_on.md)
