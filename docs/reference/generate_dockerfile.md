# Auto-generate an optimized, reproducible Dockerfile for any project

Writes a `Dockerfile` tailored to the project stack. Supported stacks:

## Usage

``` r
generate_dockerfile(
  stack = c("auto", "r-shiny", "static", "node"),
  packages = character(),
  r_version = "4.4.1",
  node_version = "20",
  port = NULL,
  sysdeps = c("libxml2-dev", "libssl-dev", "libcurl4-openssl-dev"),
  dir = ".",
  overwrite = FALSE
)

generate_r_dockerfile(...)
```

## Arguments

- stack:

  Character. One of `"auto"` (default), `"r-shiny"`, `"static"`, or
  `"node"`.

- packages:

  Character vector of R packages to add (r-shiny only). Default
  [`character()`](https://rdrr.io/r/base/character.html); shiny-verse
  already ships shiny + tidyverse.

- r_version:

  Character. Tag for `rocker/shiny-verse`, e.g. `"4.4.1"`.

- node_version:

  Character. Major Node version tag, e.g. `"20"`.

- port:

  Integer. Port the app listens on. Defaults per stack: `3838`
  (r-shiny), `80` (static), `3000` (node).

- sysdeps:

  Character vector of apt system libraries (r-shiny only).

- dir:

  Character. Directory to write the `Dockerfile` into. Also the
  directory scanned when `stack = "auto"`. Default `"."`.

- overwrite:

  Logical. Overwrite an existing `Dockerfile` (default `FALSE`).

- ...:

  Passed through to `generate_dockerfile()`.

## Value

Invisibly returns the path to the written `Dockerfile`.

## Details

- `"r-shiny"`:

  Shiny app on **`rocker/shiny-verse`** (Shiny + tidyverse
  preinstalled). Extra packages install as PPM binaries. The app binds
  to `0.0.0.0` and the Shiny port is exposed.

- `"static"`:

  Plain HTML/CSS/JS served by **nginx** (`nginx:alpine`). Your files are
  copied into the nginx web root and served on port 80.

- `"node"`:

  Node.js app on **`node:<lts>-alpine`**. Installs dependencies from
  `package.json` and runs the `start` script, binding to `0.0.0.0`.

- `"auto"`:

  Detect the stack from files present (`app.R`/`server.R` to R,
  `package.json` to node, else static).

Regardless of stack the generated image runs a real web server bound to
`0.0.0.0` and `EXPOSE`s its port, so the app is reachable from the host.

## See also

[`optimize_build_speed()`](https://laws2020.github.io/orchrd/reference/optimize_build_speed.md),
[`minify_r_dependencies()`](https://laws2020.github.io/orchrd/reference/minify_r_dependencies.md),
[`secure_secrets()`](https://laws2020.github.io/orchrd/reference/secure_secrets.md)

## Examples

``` r
if (FALSE) { # \dontrun{
generate_dockerfile()                       # auto-detect
generate_dockerfile(stack = "static")       # HTML/CSS/JS via nginx
generate_dockerfile(stack = "node", node_version = "20")
generate_dockerfile(stack = "r-shiny", packages = c("plotly"))
# docker build -t my-app . && docker run -p 8080:80 my-app
} # }
```
