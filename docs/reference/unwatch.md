# Stop a watcher

Terminates the background C++ thread associated with `id` and removes
the watcher from the registry.

## Usage

``` r
unwatch(id)
```

## Arguments

- id:

  Character. Watcher ID from
  [`watch_dir()`](https://laws2020.github.io/orchrd/reference/watch_dir.md)
  or
  [`watch_file()`](https://laws2020.github.io/orchrd/reference/watch_file.md).

## Value

Invisibly TRUE on success, FALSE if no such watcher.

## See also

[`unwatch_all()`](https://laws2020.github.io/orchrd/reference/unwatch_all.md)
