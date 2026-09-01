# Remove a saved checkpoint

Deletes the checkpoint file for `name`. Call this after a pipeline has
run successfully end-to-end and you want to reset for the next run.

## Usage

``` r
clear_checkpoint(name, dir = .checkpoint_dir(), verbose = TRUE)
```

## Arguments

- name:

  Character. Checkpoint name to remove. `"all"` removes every recognised
  checkpoint in `dir` (unrelated `.rds` files are left untouched).

- dir:

  Character. Checkpoint directory.

- verbose:

  Logical. Print confirmation (default `TRUE`).

## Value

Invisibly returns `TRUE`.

## See also

[`checkpoint()`](https://laws2020.github.io/orchrd/reference/checkpoint.md),
[`list_checkpoints()`](https://laws2020.github.io/orchrd/reference/list_checkpoints.md)

## Examples

``` r
if (FALSE) { # \dontrun{
clear_checkpoint("nga_fetch")
clear_checkpoint("all")
} # }
```
