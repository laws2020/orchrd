# Clean Docker Storage Bloat

Removes unused Docker resources to reclaim disk space by running
`docker system prune`. Cross-platform (Windows, Linux, macOS).

## Usage

``` r
clean_docker_storage(
  all = FALSE,
  volumes = FALSE,
  dry_run = FALSE,
  confirm = TRUE,
  timeout = 300,
  verbose = TRUE
)
```

## Arguments

- all:

  Logical. Also remove all unused images, not just dangling ones
  (`--all`). Default `FALSE`.

- volumes:

  Logical. Also remove unused volumes (`--volumes`). This can
  permanently delete data. Default `FALSE`.

- dry_run:

  Logical. If `TRUE`, report what would be removed via
  `docker system df` without deleting anything. Default `FALSE`.

- confirm:

  Logical. Must be `TRUE` to actually prune when `volumes = TRUE`. A
  guardrail against accidental data loss. Default `TRUE` (interactive
  sessions still proceed; set to `FALSE` in scripts to force an explicit
  re-check).

- timeout:

  Numeric. Seconds before the command is killed. Default `300` (pruning
  large caches can be slow).

- verbose:

  Logical. Print progress and reclaimed-space output (default `TRUE`).

## Value

Invisibly, a list with `ok`, `status`, `stdout`, `stderr`.

## Details

By default this removes stopped containers, unused networks, and
dangling images only. Set `all = TRUE` to also remove unused images not
associated with any container, and `volumes = TRUE` to also remove
unused volumes. Because volumes may contain application data, volume
pruning requires an explicit opt-in.

## Examples

``` r
if (FALSE) { # \dontrun{
# Safe default: stopped containers, unused networks, dangling images
clean_docker_storage()

# Aggressive: also remove all unused images and volumes
clean_docker_storage(all = TRUE, volumes = TRUE)

# Preview only
clean_docker_storage(dry_run = TRUE)
} # }
```
