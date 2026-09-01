# =============================================================================
# R/docker.R
# Docker scaffolding for ANY project - R Shiny, static web, or Node.
#
# WINDOWS SAFETY: matches run_cmd.R / artifact.R / batch_exec.R - plain
# paste0() inside stop(), never cli::format_error() with named vectors.
#
# Public API:
#   generate_dockerfile()    - write a stack-aware, reproducible Dockerfile
#   generate_r_dockerfile()  - thin back-compat wrapper (stack = "r-shiny")
#   optimize_build_speed()   - write a project .Rprofile (CRAN mirror)
#   minify_r_dependencies()  - write Rprofile.site (leaner installs)
#   secure_secrets()         - write a .dockerignore excluding secrets
#   secure_r_secrets()       - back-compat alias of secure_secrets()
# =============================================================================

# -- Internal: write a file, guarding against accidental overwrite ------------
.write_guarded <- function(lines, path, overwrite, label) {
  if (file.exists(path) && !overwrite) {
    cli::cli_warn(c(
      "{label} already exists at {.path {path}} - leaving it untouched.",
      "i" = "Pass {.code overwrite = TRUE} to replace it."
    ))
    return(invisible(FALSE))
  }
  tryCatch(
    writeLines(lines, path),
    error = function(e) {
      stop(
        paste0("Failed to write ", label, " to '", path, "': ",
               conditionMessage(e)),
        call. = FALSE
      )
    }
  )
  invisible(TRUE)
}


# -- Internal: detect the project stack from files on disk -------------------
.detect_stack <- function(dir = ".") {
  has <- function(...) any(file.exists(file.path(dir, c(...))))
  if (has("app.R", "server.R", "ui.R", "DESCRIPTION")) return("r-shiny")
  if (has("package.json"))                              return("node")
  if (has("index.html"))                                return("static")
  # Default to static - a plain HTML/CSS/JS bundle is the safest fallback.
  "static"
}


#' Auto-generate an optimized, reproducible Dockerfile for any project
#'
#' Writes a `Dockerfile` tailored to the project stack. Supported stacks:
#'
#' \describe{
#'   \item{`"r-shiny"`}{Shiny app on **`rocker/shiny-verse`** (Shiny +
#'     tidyverse preinstalled). Extra packages install as PPM binaries. The
#'     app binds to `0.0.0.0` and the Shiny port is exposed.}
#'   \item{`"static"`}{Plain HTML/CSS/JS served by **nginx** (`nginx:alpine`).
#'     Your files are copied into the nginx web root and served on port 80.}
#'   \item{`"node"`}{Node.js app on **`node:<lts>-alpine`**. Installs
#'     dependencies from `package.json` and runs the `start` script, binding
#'     to `0.0.0.0`.}
#'   \item{`"auto"`}{Detect the stack from files present (`app.R`/`server.R`
#'     to R, `package.json` to node, else static).}
#' }
#'
#' Regardless of stack the generated image runs a real web server bound to
#' `0.0.0.0` and `EXPOSE`s its port, so the app is reachable from the host.
#'
#' @param stack Character. One of `"auto"` (default), `"r-shiny"`,
#'   `"static"`, or `"node"`.
#' @param packages Character vector of R packages to add (r-shiny only).
#'   Default `character()`; shiny-verse already ships shiny + tidyverse.
#' @param r_version Character. Tag for `rocker/shiny-verse`, e.g. `"4.4.1"`.
#' @param node_version Character. Major Node version tag, e.g. `"20"`.
#' @param port Integer. Port the app listens on. Defaults per stack:
#'   `3838` (r-shiny), `80` (static), `3000` (node).
#' @param sysdeps Character vector of apt system libraries (r-shiny only).
#' @param dir Character. Directory to write the `Dockerfile` into. Also the
#'   directory scanned when `stack = "auto"`. Default `"."`.
#' @param overwrite Logical. Overwrite an existing `Dockerfile` (default
#'   `FALSE`).
#'
#' @return Invisibly returns the path to the written `Dockerfile`.
#'
#' @seealso [optimize_build_speed()], [minify_r_dependencies()],
#'   [secure_secrets()]
#'
#' @examples
#' \dontrun{
#' generate_dockerfile()                       # auto-detect
#' generate_dockerfile(stack = "static")       # HTML/CSS/JS via nginx
#' generate_dockerfile(stack = "node", node_version = "20")
#' generate_dockerfile(stack = "r-shiny", packages = c("plotly"))
#' # docker build -t my-app . && docker run -p 8080:80 my-app
#' }
#'
#' @export
generate_dockerfile <- function(
    stack        = c("auto", "r-shiny", "static", "node"),
    packages     = character(),
    r_version    = "4.4.1",
    node_version = "20",
    port         = NULL,
    sysdeps      = c("libxml2-dev", "libssl-dev", "libcurl4-openssl-dev"),
    dir          = ".",
    overwrite    = FALSE
) {
  stack <- match.arg(stack)
  if (identical(stack, "auto")) {
    stack <- .detect_stack(dir)
    message("Auto-detected stack: ", stack)
  }

  path <- file.path(dir, "Dockerfile")

  dockerfile_content <- switch(
    stack,
    "r-shiny" = .dockerfile_r_shiny(packages, r_version, port, sysdeps),
    "static"  = .dockerfile_static(port),
    "node"    = .dockerfile_node(node_version, port)
  )

  written <- .write_guarded(dockerfile_content, path, overwrite, "Dockerfile")
  if (written) message("Success! ", stack, " Dockerfile written to ", path, ".")
  invisible(path)
}


# -- r-shiny recipe: rocker/shiny-verse (shiny + tidyverse preinstalled) -----
.dockerfile_r_shiny <- function(packages, r_version, port, sysdeps) {
  port <- as.integer(port %||% 3838L)

  install_line <- if (length(packages)) {
    pkg_vec <- paste0("c(", paste0("'", packages, "'", collapse = ", "), ")")
    c(
      "",
      "# shiny-verse already has shiny + tidyverse; add only the extras as",
      "# PPM binaries (fast, no source compilation).",
      "RUN echo \"options(repos = c(CRAN = 'https://packagemanager.posit.co/cran/__linux__/jammy/latest'))\" \\",
      "    >> \"${R_HOME}/etc/Rprofile.site\"",
      paste0("RUN R -e \"install.packages(", pkg_vec, ")\"")
    )
  } else character()

  c(
    paste0("FROM rocker/shiny-verse:", r_version),
    "",
    "# System libraries: no recommends, and clean the apt cache afterwards.",
    paste0(
      "RUN apt-get update && apt-get install -y --no-install-recommends \\\n",
      "    ", paste(sysdeps, collapse = " "), " \\\n",
      "    && apt-get clean \\\n",
      "    && rm -rf /var/lib/apt/lists/*"
    ),
    install_line,
    "",
    "# Apply project-level lean-install settings if present.",
    "COPY Rprofile.site* ${R_HOME}/etc/",
    "",
    "COPY . /app",
    "WORKDIR /app",
    "",
    paste0("EXPOSE ", port),
    paste0(
      "CMD [\"R\", \"-e\", ",
      "\"shiny::runApp(host = '0.0.0.0', port = ", port, ")\"]"
    )
  )
}


# -- static recipe: nginx serves HTML/CSS/JS ---------------------------------
.dockerfile_static <- function(port) {
  port <- as.integer(port %||% 80L)
  c(
    "# Static HTML/CSS/JS served by nginx.",
    "FROM nginx:alpine",
    "",
    "# Copy the site into the default nginx web root.",
    "COPY . /usr/share/nginx/html",
    "",
    "# Remove files that shouldn't be served (in case .dockerignore missed).",
    "RUN rm -f /usr/share/nginx/html/Dockerfile \\",
    "          /usr/share/nginx/html/.dockerignore",
    "",
    paste0("EXPOSE ", port),
    "# nginx already runs in the foreground bound to 0.0.0.0.",
    "CMD [\"nginx\", \"-g\", \"daemon off;\"]"
  )
}


# -- node recipe: node:<lts>-alpine runs the start script --------------------
.dockerfile_node <- function(node_version, port) {
  port <- as.integer(port %||% 3000L)
  c(
    paste0("FROM node:", node_version, "-alpine"),
    "",
    "WORKDIR /app",
    "",
    "# Install deps first (layer-cached): copy lockfiles before source.",
    "COPY package*.json ./",
    "RUN npm ci --omit=dev || npm install --omit=dev",
    "",
    "COPY . .",
    "",
    "# Build step if the project defines one (safe no-op otherwise).",
    "RUN npm run build --if-present",
    "",
    paste0("ENV PORT=", port),
    paste0("ENV HOST=0.0.0.0"),
    paste0("EXPOSE ", port),
    "CMD [\"npm\", \"start\"]"
  )
}


#' @rdname generate_dockerfile
#' @param ... Passed through to [generate_dockerfile()].
#' @export
generate_r_dockerfile <- function(...) {
  # Back-compat: original name always meant an R Shiny app.
  generate_dockerfile(stack = "r-shiny", ...)
}


#' Point a project at a fast, reliable CRAN mirror
#'
#' Writes a project-level `.Rprofile` setting `repos` to the CRAN cloud
#' mirror. R-specific; only relevant for the `"r-shiny"` stack.
#'
#' @param dir Character. Directory to write `.Rprofile` into. Default `"."`.
#' @param overwrite Logical. Overwrite an existing `.Rprofile` (default
#'   `FALSE`).
#'
#' @return Invisibly returns the path to the written `.Rprofile`.
#' @seealso [generate_dockerfile()]
#' @export
optimize_build_speed <- function(dir = ".", overwrite = FALSE) {
  path <- file.path(dir, ".Rprofile")
  message("Configuring the CRAN cloud mirror...")
  written <- .write_guarded(
    "options(repos = c(CRAN = 'https://cloud.r-project.org'))",
    path, overwrite, ".Rprofile"
  )
  if (written) message("Success! CRAN mirror configured in ", path, ".")
  invisible(path)
}


#' Write leaner R install/runtime settings for containers
#'
#' Writes an `Rprofile.site`. R-specific; only takes effect when copied to
#' `$R_HOME/etc/` inside the image, which [generate_dockerfile()] does for the
#' `"r-shiny"` stack.
#'
#' @param dir Character. Directory to write `Rprofile.site` into. Default `"."`.
#' @param overwrite Logical. Overwrite an existing file (default `FALSE`).
#'
#' @return Invisibly returns the path to the written `Rprofile.site`.
#' @seealso [generate_dockerfile()]
#' @export
minify_r_dependencies <- function(dir = ".", overwrite = FALSE) {
  path <- file.path(dir, "Rprofile.site")
  message("Writing lean R configuration...")
  clean_settings <- c(
    "# Prefer binaries; fall back to source only when unavailable.",
    "options(install.packages.compile.from.source = 'never')",
    "options(keep.source = FALSE)",
    "options(help_type = 'text')"
  )
  written <- .write_guarded(clean_settings, path, overwrite, "Rprofile.site")
  if (written) {
    message("Success! Lean settings written to ", path, ".")
    message("  Note: only applies in the image once copied to $R_HOME/etc/ ",
            "(generate_dockerfile(stack = 'r-shiny') does this for you).")
  }
  invisible(path)
}


#' Create a .dockerignore that keeps secrets out of the build context
#'
#' Writes a `.dockerignore` excluding credential files, environment files,
#' build output, dependency caches, and VCS metadata for **any** stack
#' (R, JS/web, Node). Existing entries are preserved; only missing recommended
#' entries are appended (deduplicated); your custom rules are never dropped.
#'
#' @param dir Character. Directory to write `.dockerignore` into. Default `"."`.
#'
#' @return Invisibly returns the path to the written `.dockerignore`.
#' @seealso [generate_dockerfile()]
#' @export
secure_secrets <- function(dir = ".") {
  path <- file.path(dir, ".dockerignore")
  message("Building a .dockerignore to keep secrets out of the image...")

  recommended <- c(
    # -- secrets / env --
    ".Renviron", ".env", ".env.*", "*.secret", "*.pem", "*.key",
    "config.yml", "secrets.*",
    # -- R clutter --
    ".Rhistory", ".RData", ".Rproj.user", "renv/library",
    # -- JS / web clutter --
    "node_modules", "npm-debug.log*", "yarn-error.log*",
    "dist", "build", ".cache", ".parcel-cache", ".next", ".nuxt",
    "coverage",
    # -- VCS / OS --
    ".git", ".gitignore", ".DS_Store", "Thumbs.db",
    # -- docker itself --
    "Dockerfile", ".dockerignore"
  )

  existing <- if (file.exists(path)) {
    tryCatch(readLines(path, warn = FALSE), error = function(e) character())
  } else character()

  merged <- unique(c(existing, setdiff(recommended, existing)))
  .write_guarded(merged, path, overwrite = TRUE, ".dockerignore")

  added <- setdiff(recommended, existing)
  if (length(added)) {
    message("Success! .dockerignore updated (", length(added), " rule(s) added).")
  } else {
    message("Success! .dockerignore already covered all recommended rules.")
  }
  invisible(path)
}


#' @rdname secure_secrets
#' @export
secure_r_secrets <- function(dir = ".") secure_secrets(dir = dir)


# Local null-coalescing helper (avoids depending on rlang's %||% being in scope)
`%||%` <- function(a, b) if (is.null(a)) b else a
