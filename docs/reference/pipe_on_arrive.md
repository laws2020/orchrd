# Fire an orchrd pipeline when a file arrives

Combines
[`on_arrive()`](https://laws2020.github.io/orchrd/reference/on_arrive.md)
with [`run_bg()`](https://laws2020.github.io/orchrd/reference/run_bg.md)
so that a complete pipeline is dispatched in the background the moment a
matching file lands in `path`.

## Usage

``` r
pipe_on_arrive(
  path,
  pipeline,
  pattern = NULL,
  recursive = FALSE,
  debounce = 500L,
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

## Details

The file path is injected into the pipeline call as the named argument
`.file`, so your pipeline can optionally consume it.

## See also

[`pipe_on_change()`](https://laws2020.github.io/orchrd/reference/pipe_on_change.md),
[`on_arrive()`](https://laws2020.github.io/orchrd/reference/on_arrive.md),
[`run_bg()`](https://laws2020.github.io/orchrd/reference/run_bg.md)

## Examples

``` r
if (FALSE) { # \dontrun{
pipe_on_arrive(
  "~/nbs_drops/",
  pattern  = "\\.xlsx$",
  pipeline = function(.file) {
    opennaijR::fetch("NGA", "labour_force", file = .file)
  },
  guard_fns = list(disk = disk_ok, net = net_ok)
)
} # }
```
