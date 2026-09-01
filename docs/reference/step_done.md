# Check whether a checkpoint has already been saved

Returns `TRUE` if a checkpoint file exists for `name`. Use this at the
start of a step to skip expensive work that has already been done.

## Usage

``` r
step_done(name, dir = .checkpoint_dir(), max_age = Inf)
```

## Arguments

- name:

  Character. The checkpoint name to check.

- dir:

  Character. Checkpoint directory.

- max_age:

  Numeric. Optional maximum age in seconds. If supplied and the
  checkpoint is older than this, it is treated as absent (returns
  `FALSE`), so a stale checkpoint from a previous run won't
  short-circuit a fresh one. Default `Inf` (never expires).

## Value

Logical. `TRUE` if a usable checkpoint exists, `FALSE` otherwise.

## See also

[`checkpoint()`](https://laws2020.github.io/orchrd/reference/checkpoint.md),
[`resume_pipeline()`](https://laws2020.github.io/orchrd/reference/resume_pipeline.md),
[`clear_checkpoint()`](https://laws2020.github.io/orchrd/reference/clear_checkpoint.md)

## Examples

``` r
if (FALSE) { # \dontrun{
if (step_done("nga_fetch")) {
  df <- resume_pipeline("nga_fetch")
} else {
  df <- get_data("NGA"); checkpoint(df, "nga_fetch")
}

# Ignore checkpoints older than one hour
if (step_done("nga_fetch", max_age = 3600)) { }
} # }
```
