# Create a reversible deployment step

A convenience wrapper around
[`with_rollback()`](https://laws2020.github.io/orchrd/reference/with_rollback.md)
for the common pattern where a deployment step writes something (a file,
a tag, a remote resource) and the rollback deletes it.

## Usage

``` r
deploy_step(deploy_expr, revert_expr = NULL, label = "", verbose = TRUE)
```

## Arguments

- deploy_expr:

  The deployment expression.

- revert_expr:

  The revert (undo) expression. `NULL` means nothing to undo.

- label:

  Character. Label for log messages.

- verbose:

  Logical. Log rollback activity (default `TRUE`).

## Value

The value of `deploy_expr` if it succeeds.

## See also

[`with_rollback()`](https://laws2020.github.io/orchrd/reference/with_rollback.md)

## Examples

``` r
if (FALSE) { # \dontrun{
pipe_exec(
  upload = ~ deploy_step(
    deploy_expr = upload_to_server("data/out.parquet"),
    revert_expr = delete_from_server("data/out.parquet"),
    label       = "upload parquet"
  )
)
} # }
```
