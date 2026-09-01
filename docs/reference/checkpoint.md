# Save a pipeline step result as a checkpoint

Writes the current value to disk so the pipeline can resume from this
point if it is interrupted. Designed to wrap the value passing through
[`pipe_exec()`](https://laws2020.github.io/orchrd/reference/pipe_exec.md)
— it saves `value` and returns it unchanged so the pipeline continues
normally.

## Usage

``` r
checkpoint(value, name, dir = .checkpoint_dir(), verbose = TRUE)
```

## Arguments

- value:

  Any R object. The value to save (usually `.x` inside a
  [`pipe_exec()`](https://laws2020.github.io/orchrd/reference/pipe_exec.md)
  step).

- name:

  Character. A unique name for this checkpoint. Used as the filename on
  disk.

- dir:

  Character. Directory to save the checkpoint.

- verbose:

  Logical. Print a confirmation message (default `TRUE`).

## Value

The `value` argument, invisibly. The pipeline continues unaffected —
even if the save fails (a warning is issued instead of an error, so a
checkpointing problem never aborts a working pipeline).

## Details

The write is **atomic**: the payload is written to a temp file in the
same directory and then renamed into place, so an interrupted write can
never leave a half-written checkpoint that
[`step_done()`](https://laws2020.github.io/orchrd/reference/step_done.md)
would wrongly treat as complete.

Checkpoints are stored in `tools::R_user_dir("orchrd", "cache")` by
default. Override with the `ORCHRD_CHECKPOINT_DIR` environment variable.

## See also

[`step_done()`](https://laws2020.github.io/orchrd/reference/step_done.md),
[`resume_pipeline()`](https://laws2020.github.io/orchrd/reference/resume_pipeline.md),
[`clear_checkpoint()`](https://laws2020.github.io/orchrd/reference/clear_checkpoint.md)

## Examples

``` r
if (FALSE) { # \dontrun{
pipe_exec(
  .init = "NGA",
  fetch = ~ {
    if (step_done("nga_fetch")) return(resume_pipeline("nga_fetch"))
    checkpoint(get_data(.x), "nga_fetch")
  },
  clean = ~ {
    if (step_done("nga_clean")) return(resume_pipeline("nga_clean"))
    checkpoint(remove_na(.x), "nga_clean")
  },
  export = ~ save_output(.x, "data/nga.parquet")
)
} # }
```
