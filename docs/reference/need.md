# Assert that a pipeline's environment is ready

Checks that required system commands, environment variables, files,
directories, and R packages all exist before a pipeline starts. If
anything is missing it stops with a clear, actionable error message
listing every missing item, not just the first one.

## Usage

``` r
need(
  cmd = character(),
  env = character(),
  file = character(),
  dir = character(),
  pkg = character(),
  r_version = NULL,
  verbose = TRUE
)
```

## Arguments

- cmd:

  Character vector. System commands that must be on PATH (e.g.
  `c("git", "pwsh", "gh")`). Windows `.cmd`/`.bat`/`.exe` wrappers are
  resolved the same way as in
  [`run_cmd()`](https://laws2020.github.io/orchrd/reference/run_cmd.md).

- env:

  Character vector. Environment variable names that must be set and
  non-empty (e.g. `c("AZURE_KEY", "OPENAFRR_REPO")`).

- file:

  Character vector. File paths that must exist (a directory at that path
  does not satisfy a `file` requirement).

- dir:

  Character vector. Directory paths that must exist.

- pkg:

  Character vector. R package names that must be installed.

- r_version:

  Character. Minimum R version required, e.g. `"4.2.0"`. `NULL`
  (default) skips this check.

- verbose:

  Logical. Print a success message if all checks pass (default `TRUE`).

## Value

Invisibly returns `TRUE` if all checks pass. Throws a descriptive error
listing every missing item if any check fails.

## Details

Call `need()` at the top of any script that will run unattended or in
CI. It is far better to fail loudly at the start than to fail silently
halfway through a pipeline after 10 minutes of work.

## Examples

``` r
if (FALSE) { # \dontrun{
need(
  cmd  = c("git", "pwsh", "gh"),
  env  = c("OPENAFRR_REPO", "AZURE_KEY"),
  file = "inst/ps/fetch.ps1",
  pkg  = c("arrow", "readxl")
)
need(r_version = "4.2.0")
} # }
```
