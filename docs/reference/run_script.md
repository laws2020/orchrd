# Run an external script file

A single function that runs any script type - R, Python, PowerShell,
bash - by detecting the file extension and invoking the right
interpreter automatically. Returns the same structured `orchrd_result`
as
[`run_cmd()`](https://laws2020.github.io/orchrd/reference/run_cmd.md).

## Usage

``` r
run_script(
  path,
  args = character(),
  interpreter = NULL,
  dir = NULL,
  env = character(),
  timeout = 300,
  echo = TRUE,
  error_ok = FALSE
)
```

## Arguments

- path:

  Character. Path to the script file.

- args:

  Character vector. Arguments passed to the script.

- interpreter:

  Character. Override the detected interpreter, e.g. `"python3"`,
  `"pwsh"`, `"Rscript"`.

- dir:

  Character. Working directory. Defaults to the script's parent
  directory - almost always the right choice.

- env:

  Named character vector. Extra environment variables.

- timeout:

  Numeric. Seconds before kill (default `300`). Scripts take longer than
  single commands.

- echo:

  Logical. Stream output to the R console (default `TRUE` for scripts -
  you usually want to see progress).

- error_ok:

  Logical. Return result even on failure (default `FALSE`).

## Value

An `orchrd_result` object. See
[`run_cmd()`](https://laws2020.github.io/orchrd/reference/run_cmd.md)
for field details.

## Details

You never need to remember whether it is `Rscript --vanilla`,
`pwsh -NoProfile -NonInteractive -File`, or `python3`. One call handles
all of them.

**Interpreter resolution order:**

1.  The `interpreter` argument if explicitly supplied.

2.  File extension: `.R`/`.Rmd` to `Rscript`, `.py` to `python3`, `.ps1`
    to `pwsh`, `.qmd` to `quarto`, `.sh` to `bash`, `.js` to `node`.

3.  Shebang line (`#!`) at the top of the file. Interpreter flags on the
    shebang (e.g. `#!/usr/bin/env python3 -u`) are preserved as leading
    args.

## See also

[`run_cmd()`](https://laws2020.github.io/orchrd/reference/run_cmd.md) to
run commands rather than script files.

## Examples

``` r
if (FALSE) { # \dontrun{
run_script("scripts/build_registry.R")
run_script("inst/ps/fetch.ps1", args = c("-Source", "cbn"))
run_script("etl/clean.py", args = c("--year", "2024"))
run_script("deploy.sh", env = c(ENV = "production"))
run_script("pipeline", interpreter = "python3")
run_script("report.qmd")
} # }
```
