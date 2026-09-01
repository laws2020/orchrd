# Watch a single file for filesystem events

Convenience wrapper around
[`watch_dir()`](https://laws2020.github.io/orchrd/reference/watch_dir.md)
that targets a specific file rather than an entire directory.

## Usage

``` r
watch_file(path, events = "modified", callback, debounce = 500L, id = NULL)
```

## Arguments

- path:

  Character. Full path to the file to watch.

- events:

  Character vector of event types. Default "modified".

- callback:

  A function accepting (event, path).

- debounce:

  Integer. Milliseconds debounce window. Default 500L.

- id:

  Optional watcher ID.

## Value

Invisibly returns the watcher ID.

## See also

[`watch_dir()`](https://laws2020.github.io/orchrd/reference/watch_dir.md),
[`unwatch()`](https://laws2020.github.io/orchrd/reference/unwatch.md)

## Examples

``` r
if (FALSE) { # \dontrun{
watch_file("~/configs/pipeline.yml",
  callback = function(event, path) message("Config changed: ", path))
} # }
```
