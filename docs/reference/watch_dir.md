# Watch a directory for filesystem events

Registers a native OS-level watcher (inotify on Linux,
ReadDirectoryChangesW on Windows, kqueue on macOS) that fires `callback`
whenever a matching file event occurs inside `path`.

## Usage

``` r
watch_dir(
  path,
  pattern = NULL,
  events = c("created", "modified"),
  callback,
  recursive = FALSE,
  debounce = 500L,
  id = NULL
)
```

## Arguments

- path:

  Character. Directory to watch. Normalised; must exist.

- pattern:

  Optional regex applied to the filename (basename only). NULL matches
  all files.

- events:

  Character vector: any of "created", "modified", "deleted", "renamed".

- callback:

  A function accepting (event, path).

- recursive:

  Logical. Watch subdirectories? Default FALSE.

- debounce:

  Integer. Milliseconds debounce window. Default 500L.

- id:

  Optional character ID. Auto-generated if NULL.

## Value

Invisibly returns the watcher ID.

## See also

[`watch_file()`](https://laws2020.github.io/orchrd/reference/watch_file.md),
[`unwatch()`](https://laws2020.github.io/orchrd/reference/unwatch.md),
[`fire_on()`](https://laws2020.github.io/orchrd/reference/fire_on.md)

## Examples

``` r
if (FALSE) { # \dontrun{
id <- watch_dir("~/nbs_drops/", pattern = "\\.xlsx$", events = "created",
  callback = function(event, path) message("New file: ", path))
} # }
```
