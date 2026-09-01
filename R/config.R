# =============================================================================
# R/config.R
# Configuration loading for pipelines.
#
# Load YAML, JSON, or .env config files. Access values safely.
# Works alongside secret() — config handles non-sensitive settings,
# secret() handles credentials.
#
# WINDOWS SAFETY: matches run_cmd.R / artifact.R / batch_exec.R / docker.R /
# checkpoint.R — plain paste0() inside stop(), never cli::format_error() with
# named vectors, and cli templates interpolate names/paths/errors via
# {.val}/{.file} data slots so literal braces can't be re-evaluated as glue.
#
# Public API:
#   load_config(path)     — load a YAML/JSON/.env config file into memory
#   config_get(...)       — retrieve a config value by (possibly nested) key
#   config_has(...)       — TRUE/FALSE whether a (nested) key exists
#   config_all()          — return the full config as a named list
#   config_clear()        — clear the in-memory config
# =============================================================================

# ── Session-level config store ────────────────────────────────────────────────
.orchrd_config        <- new.env(parent = emptyenv())
.orchrd_config$store  <- list()
.orchrd_config$source <- NULL

# Local null-coalescing helper (avoids depending on rlang's %||% being in scope)
`%||%` <- function(a, b) if (is.null(a)) b else a

# Sentinel so config_get() can tell "no default supplied" from default = NULL.
.no_default <- local({ e <- new.env(); class(e) <- "orchrd_no_default"; e })


#' Load a configuration file into memory
#'
#' Reads a YAML, JSON, or `.env` format file and stores the values in memory
#' so they can be retrieved with [config_get()] anywhere in the session. Call
#' once at the top of a script — then use [config_get()] throughout.
#'
#' For sensitive values (API keys, passwords) use [secret()] instead — it
#' validates presence, masks the value, and prevents logging. `load_config()`
#' is for non-sensitive configuration: paths, URLs, feature flags, endpoint
#' names, dataset names.
#'
#' Supported formats:
#' \itemize{
#'   \item **YAML** (`.yml`, `.yaml`) — requires the `yaml` package.
#'   \item **JSON** (`.json`) — uses `jsonlite`, already a dependency.
#'   \item **env** (`.env`, `config.env`) — `KEY=value`, one per line. Lines
#'     starting with `#`, inline `# comments`, and an `export ` prefix are
#'     handled.
#' }
#'
#' @param path Character. Path to the config file.
#' @param env Character. If the file contains multiple environments
#'   (e.g. `default:`, `production:`), load this one. `NULL` (default) loads
#'   the top-level keys. Requesting an environment that does not exist is an
#'   error (no silent fallback to the whole document).
#' @param override Logical. If `TRUE` (default), the new config replaces any
#'   config already in memory. If `FALSE`, the new config is **deep-merged**
#'   under the existing one — existing keys (at any depth) win.
#' @param verbose Logical. Print a confirmation message (default `TRUE`).
#'
#' @return Invisibly returns the loaded config as a named list.
#'
#' @seealso [config_get()], [config_all()], [secret()] for credentials.
#'
#' @export
#' @examples
#' \dontrun{
#' load_config("config.yml")
#' config_get("cache_dir")
#' config_get("sources", "cbn")
#' load_config("config.yml", env = "production")
#' }
load_config <- function(
    path,
    env      = NULL,
    override = TRUE,
    verbose  = TRUE
) {
  if (!file.exists(path)) {
    stop(paste0("Config file not found: '", path, "'"), call. = FALSE)
  }
  path <- normalizePath(path, mustWork = TRUE)
  ext  <- tolower(tools::file_ext(path))

  # ── Pick + apply the named environment, erroring if it's absent ────────────
  pick_env <- function(raw) {
    if (is.null(env)) return(raw)
    if (!is.list(raw) || !env %in% names(raw)) {
      avail <- paste(names(raw), collapse = ", ")
      stop(
        paste0("Environment '", env, "' not found in config. ",
               "Available: ", avail),
        call. = FALSE
      )
    }
    raw[[env]]
  }

  cfg <- switch(ext,
                yml  = ,
                yaml = {
                  if (!requireNamespace("yaml", quietly = TRUE)) {
                    stop("yaml package required for YAML config: install.packages('yaml')",
                         call. = FALSE)
                  }
                  pick_env(yaml::read_yaml(path))
                },
                json = pick_env(jsonlite::fromJSON(path, simplifyDataFrame = FALSE)),
                env  = .parse_env_file(path),
                {
                  # Extensionless files named like .env / config -> try env format.
                  if (grepl("\\.env$|^config$", basename(path), ignore.case = TRUE)) {
                    .parse_env_file(path)
                  } else {
                    stop(
                      paste0("Unsupported config format: '.", ext, "'. ",
                             "Supported: .yml, .yaml, .json, .env"),
                      call. = FALSE
                    )
                  }
                }
  )

  if (!is.list(cfg)) {
    stop("Config file did not produce a named list. Check the file format.",
         call. = FALSE)
  }

  if (override) {
    .orchrd_config$store <- cfg
  } else {
    # Deep-merge: existing keys win at every depth.
    .orchrd_config$store <- .merge_config(cfg, .orchrd_config$store)
  }

  .orchrd_config$source <- path

  if (verbose) {
    n_keys <- length(.orchrd_config$store)
    cli::cli_alert_success(
      "Config loaded: {n_keys} key(s) from {.file {basename(path)}}"
    )
  }

  invisible(.orchrd_config$store)
}


#' Retrieve a configuration value
#'
#' Returns a value from the config loaded by [load_config()]. Supports nested
#' access by passing multiple keys.
#'
#' @param ... One or more character keys forming a path through the config.
#'   Single key for top-level values; multiple keys for nested values.
#' @param default Any. Value to return if the key is not found. If omitted,
#'   a missing key is an error. Supplying `default = NULL` is honored — it
#'   returns `NULL` instead of erroring.
#'
#' @return The config value, or `default` if the key is not found.
#'
#' @seealso [load_config()], [config_all()], [config_has()]
#'
#' @export
#' @examples
#' \dontrun{
#' config_get("throttle")
#' config_get("sources", "cbn")
#' config_get("missing_key", default = "fallback")
#' config_get("maybe_missing", default = NULL)   # returns NULL, no error
#' }
config_get <- function(..., default = .no_default) {
  if (length(.orchrd_config$store) == 0L) {
    stop(
      paste0("No config loaded. Call load_config(\"path/to/config.yml\") first."),
      call. = FALSE
    )
  }

  keys <- c(...)
  if (length(keys) == 0L) {
    stop("config_get() requires at least one key.", call. = FALSE)
  }

  val   <- .orchrd_config$store
  found <- TRUE
  for (key in keys) {
    if (!is.list(val) || !key %in% names(val)) { found <- FALSE; break }
    val <- val[[key]]
  }

  if (!found) {
    if (!inherits(default, "orchrd_no_default")) return(default)
    key_path <- paste(keys, collapse = " > ")
    avail    <- paste(names(.orchrd_config$store), collapse = ", ")
    # paste0() inside stop(); no glue re-evaluation of key names.
    stop(
      paste0("Config key not found: ", key_path, ". Top-level keys: ", avail),
      call. = FALSE
    )
  }

  val
}


#' Check whether a configuration key exists
#'
#' Non-throwing predicate — returns `TRUE` if the (possibly nested) key path
#' resolves in the loaded config, `FALSE` otherwise. Useful for feature flags
#' and optional settings.
#'
#' @param ... One or more character keys forming a path through the config.
#'
#' @return Logical, length 1.
#'
#' @seealso [config_get()]
#'
#' @export
#' @examples
#' \dontrun{
#' if (config_has("features", "beta")) enable_beta()
#' }
config_has <- function(...) {
  keys <- c(...)
  if (length(keys) == 0L || length(.orchrd_config$store) == 0L) return(FALSE)
  val <- .orchrd_config$store
  for (key in keys) {
    if (!is.list(val) || !key %in% names(val)) return(FALSE)
    val <- val[[key]]
  }
  TRUE
}


#' Return the full in-memory config
#'
#' @return A named list containing all loaded config values.
#' @seealso [load_config()], [config_get()]
#'
#' @export
#' @examples
#' \dontrun{
#' load_config("config.yml")
#' str(config_all())
#' }
config_all <- function() {
  if (length(.orchrd_config$store) == 0L) {
    message("No config loaded. Call load_config() first.")
    return(invisible(list()))
  }
  .orchrd_config$store
}


#' Clear the in-memory config
#'
#' @return Invisibly returns `TRUE`.
#' @seealso [load_config()]
#'
#' @export
#' @examples
#' \dontrun{
#' config_clear()
#' }
config_clear <- function() {
  .orchrd_config$store  <- list()
  .orchrd_config$source <- NULL
  cli::cli_inform(c("i" = "Config cleared."))
  invisible(TRUE)
}


# ── Internal: deep-merge two named lists (existing keys win) ──────────────────
#' @noRd
.merge_config <- function(new, existing) {
  if (!is.list(new) || !is.list(existing)) return(existing %||% new)
  out <- new
  for (k in names(existing)) {
    if (is.list(out[[k]]) && is.list(existing[[k]])) {
      out[[k]] <- .merge_config(out[[k]], existing[[k]])
    } else {
      out[[k]] <- existing[[k]]   # existing wins
    }
  }
  out
}


# ── Internal: parse .env format files ─────────────────────────────────────────
#' @noRd
.parse_env_file <- function(path) {
  lines <- readLines(path, warn = FALSE)
  cfg   <- list()

  for (raw_line in lines) {
    line <- trimws(raw_line)
    if (!nzchar(line) || grepl("^#", line)) next        # blank / full-line comment
    line <- sub("^export[[:space:]]+", "", line)        # drop `export ` prefix

    eq <- regexpr("=", line, fixed = TRUE)
    if (eq < 1L) next                                    # no key=value -> skip
    key <- trimws(substr(line, 1L, eq - 1L))
    val <- trimws(substr(line, eq + 1L, nchar(line)))
    if (!nzchar(key)) next

    # Strip an inline # comment only when the value is NOT quoted.
    is_quoted <- grepl('^".*"$|^\'.*\'$', val)
    if (!is_quoted) val <- trimws(sub("[[:space:]]+#.*$", "", val))

    val <- gsub('^"|"$|^\'|\'$', "", val)                # strip surrounding quotes
    cfg[[key]] <- val
  }
  cfg
}
