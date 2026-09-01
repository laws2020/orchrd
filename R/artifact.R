# =============================================================================
# R/artifact.R
# Artifact management — store and reload pipeline outputs consistently.
#
# Treats pipeline outputs (data frames, models, plots, files) as tracked
# artifacts with metadata: what was saved, when, how big, and what format.
# Simpler than pins for local use, but pins-compatible for shared storage.
#
# WINDOWS SAFETY: matches the run_cmd.R fix — no cli::format_error() with
# named vectors inside stop(). Plain paste0() only, to avoid the recursive
# RAWSXP crash on Windows during error unwinding.
#
# Public API:
#   store_artifact(x, name, ...)  — save an object as a named artifact
#   load_artifact(name, ...)      — retrieve a previously stored artifact
#   list_artifacts()              — show all stored artifacts
#   delete_artifact(name)         — remove a stored artifact
# =============================================================================

# ── Default artifact directory ────────────────────────────────────────────────
# Fix #2: use tools::R_user_dir() (R >= 4.0) instead of Sys.getenv("HOME"),
# which is unreliable on Windows. ORCHRD_ARTIFACT_DIR override still wins.
.artifact_dir <- function() {
  base <- Sys.getenv("ORCHRD_ARTIFACT_DIR", unset = "")
  if (nzchar(base)) return(base)
  tools::R_user_dir("orchrd", which = "cache")
}

.artifact_safe_name <- function(name) {
  gsub("[^a-zA-Z0-9_-]", "_", name)
}

.artifact_path <- function(name, format, dir) {
  file.path(dir, paste0(.artifact_safe_name(name), ".", format))
}

.artifact_meta_path <- function(name, dir) {
  file.path(dir, paste0(.artifact_safe_name(name), ".meta.json"))
}


#' Store a pipeline output as a named artifact
#'
#' Saves an R object to disk with metadata tracking. Supports multiple
#' formats: `"rds"` (any R object), `"parquet"` (data frames, requires
#' `arrow`), `"csv"` (data frames), and `"json"`.
#'
#' The artifact is saved with a metadata sidecar (`.meta.json`) recording
#' the name, format, dimensions (for data frames), timestamp, and size.
#' Use [load_artifact()] to retrieve it and [list_artifacts()] to see
#' what is stored.
#'
#' Designed to sit at the end of a [pipe_exec()] step so every significant
#' output is tracked and reloadable without re-running the pipeline.
#'
#' @param x The R object to save.
#' @param name Character. A unique name for this artifact.
#' @param format Character. Storage format: `"rds"` (default), `"parquet"`,
#'   `"csv"`, or `"json"`. Only `"rds"` and `"parquet"` preserve R types
#'   faithfully; `"csv"` and `"json"` are lossy for factors, dates, and
#'   list-columns.
#' @param dir Character. Artifact directory. Defaults to
#'   `tools::R_user_dir("orchrd", "cache")`.
#' @param overwrite Logical. Replace an existing artifact with the same
#'   name (default `TRUE`).
#' @param verbose Logical. Print confirmation (default `TRUE`).
#'
#' @return `x` invisibly so the function can be used at the end of a
#'   [pipe_exec()] step without breaking the flow.
#'
#' @seealso [load_artifact()], [list_artifacts()], [delete_artifact()]
#'
#' @export
#' @examples
#' \dontrun{
#' pipe_exec(
#'   fetch  = ~ get_data("source"),
#'   clean  = ~ remove_na(.x),
#'   save   = ~ store_artifact(.x, "nga_cpi_clean", format = "parquet")
#' )
#'
#' model <- lm(value ~ year, data = df)
#' store_artifact(model, "nga_cpi_model")
#'
#' df    <- load_artifact("nga_cpi_clean")
#' model <- load_artifact("nga_cpi_model")
#' }
store_artifact <- function(
    x,
    name,
    format    = "rds",
    dir       = .artifact_dir(),
    overwrite = TRUE,
    verbose   = TRUE
) {
  format <- match.arg(format, c("rds", "parquet", "csv", "json"))
  dir.create(dir, showWarnings = FALSE, recursive = TRUE)

  path      <- .artifact_path(name, format, dir)
  meta_path <- .artifact_meta_path(name, dir)

  if (file.exists(path) && !overwrite) {
    cli::cli_warn(
      "Artifact '{name}' already exists. Use overwrite = TRUE to replace."
    )
    return(invisible(x))
  }

  # ── Fix #6: warn on lossy formats for objects they can't round-trip ────────
  if (format %in% c("csv", "json") && !is.data.frame(x)) {
    cli::cli_warn(c(
      "Saving a non-data-frame as {.val {format}} is lossy.",
      "i" = "Use {.val rds} or {.val parquet} to preserve R types faithfully."
    ))
  }

  # ── Write artifact ─────────────────────────────────────────────────────────
  # Fix #1: plain paste0() inside stop(), not cli::format_error() with named
  # vectors (matches the run_cmd.R Windows RAWSXP fix).
  tryCatch({
    switch(format,
           rds     = saveRDS(x, path),
           parquet = {
             if (!requireNamespace("arrow", quietly = TRUE)) {
               stop("arrow is required for parquet format: install.packages('arrow')")
             }
             arrow::write_parquet(x, path)
           },
           csv  = utils::write.csv(x, path, row.names = FALSE),
           json = jsonlite::write_json(x, path, auto_unbox = TRUE, pretty = TRUE)
    )
  }, error = function(e) {
    stop(
      paste0("store_artifact() failed to write '", name, "': ", conditionMessage(e)),
      call. = FALSE
    )
  })

  # ── Write metadata sidecar ─────────────────────────────────────────────────
  # Fix #3: store only the file name, not an absolute path, for portability.
  meta <- list(
    name       = name,
    format     = format,
    file       = basename(path),
    saved_at   = format(Sys.time(), "%Y-%m-%dT%H:%M:%S"),
    size_kb    = round(file.info(path)$size / 1024, 1),
    is_df      = is.data.frame(x),
    nrow       = if (is.data.frame(x)) nrow(x) else NA,
    ncol       = if (is.data.frame(x)) ncol(x) else NA,
    class      = paste(class(x), collapse = ", ")
  )
  jsonlite::write_json(meta, meta_path, auto_unbox = TRUE, pretty = TRUE)

  if (verbose) {
    dims <- if (is.data.frame(x)) {
      paste0(" (", nrow(x), " rows \u00d7 ", ncol(x), " cols)")
    } else ""
    cli::cli_alert_success(
      "Artifact stored: {.field {name}}{dims} [{format}] \u2192 {meta$size_kb} KB"
    )
  }

  invisible(x)
}


#' Load a previously stored artifact
#'
#' Retrieves an artifact saved by [store_artifact()]. The format is
#' detected automatically from the metadata sidecar — you do not need
#' to specify it.
#'
#' @param name Character. The artifact name to load.
#' @param dir Character. Artifact directory.
#' @param verbose Logical. Print a loading message (default `TRUE`).
#'
#' @return The R object that was stored.
#'
#' @seealso [store_artifact()], [list_artifacts()]
#'
#' @export
#' @examples
#' \dontrun{
#' df    <- load_artifact("nga_cpi_clean")
#' model <- load_artifact("nga_cpi_model")
#' }
load_artifact <- function(name, dir = .artifact_dir(), verbose = TRUE) {
  meta_path <- .artifact_meta_path(name, dir)

  if (!file.exists(meta_path)) {
    available <- gsub("\\.meta\\.json$", "",
                      list.files(dir, pattern = "\\.meta\\.json$"))
    stop(
      paste0(
        "Artifact not found: '", name, "'.\n",
        "  Available artifacts: ",
        if (length(available)) paste(available, collapse = ", ") else "(none)"
      ),
      call. = FALSE
    )
  }

  meta <- jsonlite::fromJSON(meta_path)

  # ── Fix #3: reconstruct path from name + format + dir, not stored abspath ──
  # Fall back to legacy metadata that stored `path`/`file` if present.
  path <- .artifact_path(name, meta$format, dir)
  if (!file.exists(path) && !is.null(meta$file)) {
    path <- file.path(dir, meta$file)
  }
  if (!file.exists(path) && !is.null(meta$path)) {
    path <- meta$path  # legacy artifacts
  }

  if (!file.exists(path)) {
    stop(
      paste0(
        "Artifact file missing: '", name, "'.\n",
        "  Expected at: ", path, "\n",
        "  Re-run the pipeline to regenerate it."
      ),
      call. = FALSE
    )
  }

  # ── Fix #5: switch() with an explicit default for unknown formats ──────────
  obj <- tryCatch({
    switch(meta$format,
           rds     = readRDS(path),
           parquet = {
             if (!requireNamespace("arrow", quietly = TRUE)) {
               stop("arrow is required for parquet format: install.packages('arrow')")
             }
             arrow::read_parquet(path)
           },
           csv     = utils::read.csv(path, stringsAsFactors = FALSE),
           json    = jsonlite::fromJSON(path),
           stop(paste0("Unknown artifact format: '", meta$format, "'"))
    )
  }, error = function(e) {
    stop(
      paste0("Could not load artifact '", name, "': ", conditionMessage(e)),
      call. = FALSE
    )
  })

  if (verbose) {
    dims <- if (!is.null(meta$nrow) && !is.na(meta$nrow)) {
      paste0(" (", meta$nrow, " rows \u00d7 ", meta$ncol, " cols)")
    } else ""
    cli::cli_inform(c(
      "v" = "Artifact loaded: {.field {name}}{dims} [saved {meta$saved_at}]"
    ))
  }

  obj
}


#' List all stored artifacts
#'
#' Scans the artifact directory and returns a data frame describing every
#' stored artifact — name, format, size, dimensions, and timestamp.
#'
#' @param dir Character. Artifact directory.
#'
#' @return A data frame. Printed and returned invisibly.
#'
#' @seealso [store_artifact()], [delete_artifact()]
#'
#' @export
#' @examples
#' \dontrun{
#' list_artifacts()
#' }
list_artifacts <- function(dir = .artifact_dir()) {
  if (!dir.exists(dir)) {
    message("Artifact directory does not exist yet: ", dir)
    return(invisible(data.frame()))
  }

  meta_files <- list.files(dir, pattern = "\\.meta\\.json$", full.names = TRUE)

  if (length(meta_files) == 0L) {
    message("No artifacts found in: ", dir)
    return(invisible(data.frame()))
  }

  rows <- lapply(meta_files, function(f) {
    m <- tryCatch(jsonlite::fromJSON(f), error = function(e) NULL)
    if (is.null(m)) return(NULL)
    data.frame(
      name     = m$name,
      format   = m$format,
      size_kb  = m$size_kb,
      nrow     = if (!is.null(m$nrow)) m$nrow else NA_integer_,
      ncol     = if (!is.null(m$ncol)) m$ncol else NA_integer_,
      saved_at = m$saved_at,
      stringsAsFactors = FALSE
    )
  })

  df <- do.call(rbind, Filter(Negate(is.null), rows))
  print(df, row.names = FALSE)
  invisible(df)
}


#' Delete a stored artifact
#'
#' Removes the artifact file and its metadata sidecar.
#'
#' @param name Character. Artifact name to delete. `"all"` removes every
#'   artifact in `dir` (only recognised artifact + `.meta.json` files —
#'   unrelated files are left untouched).
#' @param dir Character. Artifact directory.
#' @param verbose Logical. Print confirmation (default `TRUE`).
#'
#' @return Invisibly returns `TRUE`.
#' @seealso [store_artifact()], [list_artifacts()]
#'
#' @export
#' @examples
#' \dontrun{
#' delete_artifact("nga_cpi_clean")
#' delete_artifact("all")
#' }
delete_artifact <- function(name, dir = .artifact_dir(), verbose = TRUE) {
  if (identical(name, "all")) {
    # ── Fix #4: only remove artifacts we recognise, not every file in dir ────
    meta_files <- list.files(dir, pattern = "\\.meta\\.json$", full.names = TRUE)
    if (length(meta_files) == 0L) {
      message("No artifacts to delete.")
      return(invisible(TRUE))
    }
    for (mf in meta_files) {
      m <- tryCatch(jsonlite::fromJSON(mf), error = function(e) NULL)
      if (!is.null(m)) {
        data_path <- .artifact_path(m$name, m$format, dir)
        if (file.exists(data_path)) file.remove(data_path)
        # legacy fallbacks
        if (!is.null(m$file) && file.exists(file.path(dir, m$file))) {
          file.remove(file.path(dir, m$file))
        }
        if (!is.null(m$path) && file.exists(m$path)) file.remove(m$path)
      }
      file.remove(mf)
    }
    if (verbose) cli::cli_alert_success("Deleted all artifacts in: {dir}")
    return(invisible(TRUE))
  }

  meta_path <- .artifact_meta_path(name, dir)
  if (!file.exists(meta_path)) {
    cli::cli_warn("Artifact not found: {.field {name}}")
    return(invisible(FALSE))
  }

  meta <- tryCatch(jsonlite::fromJSON(meta_path), error = function(e) NULL)
  if (!is.null(meta)) {
    data_path <- .artifact_path(name, meta$format, dir)
    if (file.exists(data_path)) file.remove(data_path)
    if (!is.null(meta$file) && file.exists(file.path(dir, meta$file))) {
      file.remove(file.path(dir, meta$file))
    }
    if (!is.null(meta$path) && file.exists(meta$path)) file.remove(meta$path)
  }
  file.remove(meta_path)

  if (verbose) cli::cli_alert_success("Artifact deleted: {.field {name}}")
  invisible(TRUE)
}
