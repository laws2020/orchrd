# List all saved checkpoints

Returns a data frame showing every checkpoint saved in the checkpoint
directory — name, saved timestamp, file size, and full path.

## Usage

``` r
list_checkpoints(dir = .checkpoint_dir())
```

## Arguments

- dir:

  Character. Checkpoint directory.

## Value

A data frame with columns `name`, `saved_at`, `size_kb`, `path`. Returns
an empty data frame if no checkpoints exist.

## See also

[`checkpoint()`](https://laws2020.github.io/orchrd/reference/checkpoint.md),
[`clear_checkpoint()`](https://laws2020.github.io/orchrd/reference/clear_checkpoint.md)

## Examples

``` r
if (FALSE) { # \dontrun{
list_checkpoints()
} # }
```
