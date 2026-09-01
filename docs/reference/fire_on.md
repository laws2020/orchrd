# Bind an action to a filesystem event

The main trigger API. Declaratively describes: "when THIS event happens
to files matching THIS pattern in THIS location, run THIS action."

## Usage

``` r
fire_on(
  event,
  path,
  action,
  pattern = NULL,
  recursive = FALSE,
  debounce = 500L,
  id = NULL
)
```

## Arguments

- event:

  Character. One of "arrive", "change", "leave", "rename", or the raw
  equivalents "created", "modified", "deleted", "renamed".

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

[`on_arrive()`](https://laws2020.github.io/orchrd/reference/on_arrive.md),
[`on_change()`](https://laws2020.github.io/orchrd/reference/on_change.md),
[`on_leave()`](https://laws2020.github.io/orchrd/reference/on_leave.md),
[`on_rename()`](https://laws2020.github.io/orchrd/reference/on_rename.md),
[`watch_dir()`](https://laws2020.github.io/orchrd/reference/watch_dir.md),
[`watch_file()`](https://laws2020.github.io/orchrd/reference/watch_file.md)

## Examples

``` r
if (FALSE) { # \dontrun{
# Formula syntax - quick one-liners
fire_on("arrive", "~/nbs_drops/", pattern = "\\.xlsx$",
        action = ~ message("File arrived: ", .path))

# Function syntax - full pipeline trigger
fire_on("arrive", "~/cbn_feeds/",
        action = function(event, path) {
          opennaijR::fetch("NGA", "inflation")
        })
} # }
```
