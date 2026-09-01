# Re-run an orchrd pipeline when a config or data file changes

Useful for live-reloading a pipeline when its configuration file is
edited.

## Usage

``` r
pipe_on_change(
  path,
  pipeline,
  pattern = NULL,
  recursive = FALSE,
  debounce = 1000L,
  guard_fns = list(),
  id = NULL,
  ...
)
```

## Arguments

- path:

  Directory to watch.

- pipeline:

  A function (or orchrd pipeline object) to run.

- pattern:

  Optional filename regex.

- recursive:

  Watch subdirectories? Default `FALSE`.

- debounce:

  Milliseconds debounce. Default `500L`.

- guard_fns:

  Optional named list of zero-argument guard functions. All must return
  `TRUE` for the pipeline to fire. Example:
  `list(disk = disk_ok, net = net_ok)`.

- id:

  Optional watcher ID.

- ...:

  Additional arguments forwarded to
  [`run_bg()`](https://laws2020.github.io/orchrd/reference/run_bg.md).

## Value

Invisibly returns the watcher ID.

## See also

[`pipe_on_arrive()`](https://laws2020.github.io/orchrd/reference/pipe_on_arrive.md),
[`on_change()`](https://laws2020.github.io/orchrd/reference/on_change.md),
[`run_bg()`](https://laws2020.github.io/orchrd/reference/run_bg.md)

## Examples

``` r
if (FALSE) { # \dontrun{
pipe_on_change(
  "~/configs/pipeline.yml",
  pipeline = function(.file) reload_config(.file)
)
} # }
```
