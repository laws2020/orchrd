# =============================================================================
# R/checkpoint.R
# State and idempotency for long-running pipelines.
#
# A pipeline that fetches 29 CBN endpoints and fails on step 18 currently
# restarts from zero. checkpoint() saves progress to disk so execution
# can resume from where it stopped.
#
# WINDOWS SAFETY: matches run_cmd.R / artifact.R / batch_exec.R / docker.R —
# plain paste0() inside stop(), never cli::format_error() with named vectors,
# and cli templates interpolate names/paths/errors via {.val}/{.path} data
# slots so literal braces can't be re-evaluated as glue templates.
#
# Public API:
#   checkpoint(value, name)  — save a step result (atomic write)
#   step_done(name)          — check if a step was already completed
#   resume_pipeline(name)    — get the saved result of a checkpoint
#   clear_checkpoint(name)   — remove a checkpoint
#   list_checkpoints()       — show all saved checkpoints
# =============================================================================

# ── Default checkpoint directory ──────────────────────────────────────────────
# Fix #4: tools::R_user_dir() (R >= 4.0) instead of Sys.getenv("HOME"),
# which is unreliable on Windows. ORCHRD_CHECKPOINT_DIR override still wins.
.checkpoint_dir <- function() {
  base <- Sys.getenv("ORCHRD_CHECKPOINT_DIR", unset = "")
  if (nzchar(base)) return(base)
  tools::R_user_dir("orchrd", which = "cache")
}

.checkpoint_path <- function(name, dir) {
  safe_name <- gsub("[^a-zA-Z0-9_-]", "_", name)
  file.path(dir, paste0(safe_name, ".rds"))
}

# ── Internal: is this .rds file actually an orchrd checkpoint payload? ─────────
.is_checkpoint_file <- function(f) {
  payload <- tryCatch(readRDS(f), error = function(e) NULL)
  is.list(payload) &&
    all(c("name", "saved_at", "value") %in% names(payload))
}


#' Save a pipeline step result as a checkpoint
#'
#' Writes the current value to disk so the pipeline can resume from this
#' point if it is interrupted. Designed to wrap the value passing through
#' [pipe_exec()] — it saves `value` and returns it unchanged so the pipeline
#' continues normally.
#'
#' The write is **atomic**: the payload is written to a temp file in the same
#' directory and then renamed into place, so an interrupted write can never
#' leave a half-written checkpoint that [step_done()] would wrongly treat as
#' complete.
#'
#' Checkpoints are stored in `tools::R_user_dir("orchrd", "cache")` by
#' default. Override with the `ORCHRD_CHECKPOINT_DIR` environment variable.
#'
#' @param value Any R object. The value to save (usually `.x` inside a
#'   [pipe_exec()] step).
#' @param name Character. A unique name for this checkpoint. Used as the
#'   filename on disk.
#' @param dir Character. Directory to save the checkpoint.
#' @param verbose Logical. Print a confirmation message (default `TRUE`).
#'
#' @return The `value` argument, invisibly. The pipeline continues
#'   unaffected — even if the save fails (a warning is issued instead of an
#'   error, so a checkpointing problem never aborts a working pipeline).
#'
#' @seealso [step_done()], [resume_pipeline()], [clear_checkpoint()]
#'
#' @export
#' @examples
#' \dontrun{
#' pipe_exec(
#'   .init = "NGA",
#'   fetch = ~ {
#'     if (step_done("nga_fetch")) return(resume_pipeline("nga_fetch"))
#'     checkpoint(get_data(.x), "nga_fetch")
#'   },
#'   clean = ~ {
#'     if (step_done("nga_clean")) return(resume_pipeline("nga_clean"))
#'     checkpoint(remove_na(.x), "nga_clean")
#'   },
#'   export = ~ save_output(.x, "data/nga.parquet")
#' )
#' }
checkpoint <- function(
    value,
    name,
    dir     = .checkpoint_dir(),
    verbose = TRUE
) {
  dir.create(dir, showWarnings = FALSE, recursive = TRUE)

  path <- .checkpoint_path(name, dir)

  payload <- list(
    name     = name,
    saved_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S"),
    class    = paste(class(value), collapse = ", "),
    value    = value
  )

  # ── Fix #2: atomic write — temp file in same dir, then rename ──────────────
  tmp <- tempfile(tmpdir = dir, fileext = ".rds.tmp")
  ok  <- tryCatch(
    {
      saveRDS(payload, tmp)
      # file.rename is atomic on the same filesystem; overwrites existing.
      if (!file.rename(tmp, path)) {
        # rename can fail across some Windows conditions; fall back to copy.
        file.copy(tmp, path, overwrite = TRUE)
      }
      TRUE
    },
    error = function(e) {
      # Fix #5: pass name + message as {.val} data, not raw template text.
      cli::cli_warn(c(
        "checkpoint() could not save {.val {name}}.",
        "x" = "{.val {conditionMessage(e)}}"
      ))
      FALSE
    }
  )
  if (file.exists(tmp)) tryCatch(unlink(tmp), error = function(e) NULL)

  # ── Fix #1: only report success if the file actually exists now ────────────
  if (ok && file.exists(path)) {
    if (verbose) {
      size_kb <- round(file.info(path)$size / 1024, 1)
      cli::cli_alert_success(
        "Checkpoint saved: {.val {name}} ({size_kb} KB \u2192 {.path {path}})"
      )
    }
  } else if (verbose) {
    cli::cli_alert_danger("Checkpoint NOT saved: {.val {name}}")
  }

  invisible(value)
}


#' Check whether a checkpoint has already been saved
#'
#' Returns `TRUE` if a checkpoint file exists for `name`. Use this at the
#' start of a step to skip expensive work that has already been done.
#'
#' @param name Character. The checkpoint name to check.
#' @param dir Character. Checkpoint directory.
#' @param max_age Numeric. Optional maximum age in seconds. If supplied and
#'   the checkpoint is older than this, it is treated as absent (returns
#'   `FALSE`), so a stale checkpoint from a previous run won't short-circuit
#'   a fresh one. Default `Inf` (never expires).
#'
#' @return Logical. `TRUE` if a usable checkpoint exists, `FALSE` otherwise.
#'
#' @seealso [checkpoint()], [resume_pipeline()], [clear_checkpoint()]
#'
#' @export
#' @examples
#' \dontrun{
#' if (step_done("nga_fetch")) {
#'   df <- resume_pipeline("nga_fetch")
#' } else {
#'   df <- get_data("NGA"); checkpoint(df, "nga_fetch")
#' }
#'
#' # Ignore checkpoints older than one hour
#' if (step_done("nga_fetch", max_age = 3600)) { }
#' }
step_done <- function(name, dir = .checkpoint_dir(), max_age = Inf) {
  path <- .checkpoint_path(name, dir)
  if (!file.exists(path)) return(FALSE)
  if (is.finite(max_age)) {
    age_sec <- as.numeric(difftime(Sys.time(), file.info(path)$mtime,
                                   units = "secs"))
    if (isTRUE(age_sec > max_age)) return(FALSE)
  }
  TRUE
}


#' Load a saved checkpoint value
#'
#' Reads the value saved by [checkpoint()] and returns it. Typically used
#' after [step_done()] confirms the checkpoint exists.
#'
#' @param name Character. The checkpoint name to load.
#' @param dir Character. Checkpoint directory.
#' @param verbose Logical. Print a message when loading (default `TRUE`).
#'
#' @return The R object that was passed to [checkpoint()].
#'
#' @seealso [checkpoint()], [step_done()]
#'
#' @export
#' @examples
#' \dontrun{
#' if (step_done("nga_fetch")) df <- resume_pipeline("nga_fetch")
#' }
resume_pipeline <- function(name, dir = .checkpoint_dir(), verbose = TRUE) {
  path <- .checkpoint_path(name, dir)

  if (!file.exists(path)) {
    # Fix #3: plain paste0() inside stop(), not cli::format_error().
    stop(
      paste0(
        "Checkpoint not found: '", name, "'.\n",
        "  Run the pipeline at least once to create checkpoints."
      ),
      call. = FALSE
    )
  }

  payload <- tryCatch(
    readRDS(path),
    error = function(e) {
      stop(
        paste0("Could not read checkpoint '", name, "': ", conditionMessage(e)),
        call. = FALSE
      )
    }
  )

  if (verbose) {
    saved_at <- if (is.list(payload) && !is.null(payload$saved_at)) {
      payload$saved_at
    } else "unknown"
    cli::cli_inform(c(
      "v" = "Resuming from checkpoint: {.val {name}} (saved {.val {saved_at}})"
    ))
  }

  # Tolerate both new payloads (list with $value) and any legacy bare object.
  if (is.list(payload) && "value" %in% names(payload)) payload$value else payload
}


#' Remove a saved checkpoint
#'
#' Deletes the checkpoint file for `name`. Call this after a pipeline has run
#' successfully end-to-end and you want to reset for the next run.
#'
#' @param name Character. Checkpoint name to remove. `"all"` removes every
#'   recognised checkpoint in `dir` (unrelated `.rds` files are left
#'   untouched).
#' @param dir Character. Checkpoint directory.
#' @param verbose Logical. Print confirmation (default `TRUE`).
#'
#' @return Invisibly returns `TRUE`.
#'
#' @seealso [checkpoint()], [list_checkpoints()]
#'
#' @export
#' @examples
#' \dontrun{
#' clear_checkpoint("nga_fetch")
#' clear_checkpoint("all")
#' }
clear_checkpoint <- function(
    name,
    dir     = .checkpoint_dir(),
    verbose = TRUE
) {
  if (identical(name, "all")) {
    files <- list.files(dir, pattern = "\\.rds$", full.names = TRUE)
    # Fix #6: only remove files that are actually checkpoint payloads.
    files <- Filter(.is_checkpoint_file, files)
    if (length(files) == 0L) {
      if (verbose) message("No checkpoints to clear.")
      return(invisible(TRUE))
    }
    file.remove(files)
    if (verbose) cli::cli_alert_success("Cleared {length(files)} checkpoint(s).")
  } else {
    path <- .checkpoint_path(name, dir)
    if (!file.exists(path)) {
      if (verbose) cli::cli_warn("Checkpoint not found: {.val {name}}")
      return(invisible(FALSE))
    }
    file.remove(path)
    if (verbose) cli::cli_alert_success("Checkpoint removed: {.val {name}}")
  }

  invisible(TRUE)
}


#' List all saved checkpoints
#'
#' Returns a data frame showing every checkpoint saved in the checkpoint
#' directory — name, saved timestamp, file size, and full path.
#'
#' @param dir Character. Checkpoint directory.
#'
#' @return A data frame with columns `name`, `saved_at`, `size_kb`, `path`.
#'   Returns an empty data frame if no checkpoints exist.
#'
#' @seealso [checkpoint()], [clear_checkpoint()]
#'
#' @export
#' @examples
#' \dontrun{
#' list_checkpoints()
#' }
list_checkpoints <- function(dir = .checkpoint_dir()) {
  empty <- data.frame(
    name = character(), saved_at = character(),
    size_kb = numeric(), path = character(),
    stringsAsFactors = FALSE
  )

  if (!dir.exists(dir)) {
    message("Checkpoint directory does not exist yet: ", dir)
    return(invisible(empty))
  }

  files <- list.files(dir, pattern = "\\.rds$", full.names = TRUE)
  if (length(files) == 0L) {
    message("No checkpoints found in: ", dir)
    return(invisible(empty))
  }

  rows <- lapply(files, function(f) {
    payload <- tryCatch(readRDS(f), error = function(e) NULL)
    # Skip .rds files that aren't checkpoint payloads.
    if (!is.list(payload) || !all(c("name", "saved_at") %in% names(payload))) {
      return(NULL)
    }
    data.frame(
      name     = payload$name,
      saved_at = payload$saved_at %||% NA_character_,
      size_kb  = round(file.info(f)$size / 1024, 1),
      path     = f,
      stringsAsFactors = FALSE
    )
  })

  df <- do.call(rbind, Filter(Negate(is.null), rows))
  if (is.null(df) || nrow(df) == 0L) {
    message("No checkpoints found in: ", dir)
    return(invisible(empty))
  }
  print(df, row.names = FALSE)
  invisible(df)
}


# Local null-coalescing helper (avoids depending on rlang's %||% being in scope)
`%||%` <- function(a, b) if (is.null(a)) b else a
