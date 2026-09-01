# Load a saved checkpoint value

Reads the value saved by
[`checkpoint()`](https://laws2020.github.io/orchrd/reference/checkpoint.md)
and returns it. Typically used after
[`step_done()`](https://laws2020.github.io/orchrd/reference/step_done.md)
confirms the checkpoint exists.

## Usage

``` r
resume_pipeline(name, dir = .checkpoint_dir(), verbose = TRUE)
```

## Arguments

- name:

  Character. The checkpoint name to load.

- dir:

  Character. Checkpoint directory.

- verbose:

  Logical. Print a message when loading (default `TRUE`).

## Value

The R object that was passed to
[`checkpoint()`](https://laws2020.github.io/orchrd/reference/checkpoint.md).

## See also

[`checkpoint()`](https://laws2020.github.io/orchrd/reference/checkpoint.md),
[`step_done()`](https://laws2020.github.io/orchrd/reference/step_done.md)

## Examples

``` r
if (FALSE) { # \dontrun{
if (step_done("nga_fetch")) df <- resume_pipeline("nga_fetch")
} # }
```
