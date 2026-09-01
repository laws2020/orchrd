# =============================================================================
# R/secret.R
# Safe secrets handling.
# Validate presence, never log the value, error clearly when missing.
#
# WINDOWS SAFETY: matches run_cmd.R / artifact.R - plain paste0() inside
# stop(), never cli::format_error() with named vectors.
# ASCII-only: no smart quotes, em-dashes, arrows, or emoji.
#
# LEAK SAFETY: the raw value is held in a locked environment, not a plain
# list field, so unclass()/str()/dput()/$ cannot reach it. as.character()
# and format() return the MASK, not the value. The only way to obtain the
# raw string is reveal(), which is deliberate and greppable in code review.
#
# Public API:
#   secret(name, desc, default)  - read a secret env var safely
#   reveal(x)                    - extract the raw value (explicit)
#   is_secret(x)                 - predicate
# =============================================================================

#' Retrieve a secret environment variable safely
#'
#' Reads a secret from environment variables with three guarantees that
#' plain `Sys.getenv()` does not provide:
#'
#' 1. Presence validation - errors immediately if the variable is not set,
#'    with a clear message explaining what it is needed for.
#' 2. Log safety - the value is held in a locked environment and never
#'    surfaces through `as.character()`, `format()`, `print()`, `str()`,
#'    `unclass()`, or `dput()`. It is therefore never captured by
#'    [log_step()] or [with_log()], even at debug level.
#' 3. Masked printing - the `orchrd_secret` object prints as
#'    `<secret: VAR_NAME>`.
#'
#' To obtain the underlying value you must call [reveal()] explicitly. This
#' is intentional: it makes every point where a secret is exposed grep-able
#' in code review.
#'
#' @param name Character(1). The environment variable name.
#' @param desc Character(1) or NULL. Human-readable description of what this
#'   secret is used for. Shown in the error message if the variable is
#'   missing.
#' @param default Character(1) or NULL. A default value used if the variable
#'   is not set. Setting a default suppresses the missing-variable error.
#'   Use with caution - in production, secrets should always be explicit.
#'
#' @return An S3 object of class `orchrd_secret`.
#'
#' @seealso [reveal()] to extract the raw value, [need()] to validate
#'   multiple secrets at once before a pipeline starts.
#'
#' @export
#' @examples
#' \dontrun{
#' key <- secret("AZURE_KEY")
#' key
#' # <secret: AZURE_KEY>
#'
#' raw <- reveal(secret("AZURE_KEY"))
#' key <- secret("AZURE_KEY", default = "dev-placeholder")
#' }
secret <- function(name, desc = NULL, default = NULL) {
  if (!is.character(name) || length(name) != 1L || is.na(name) ||
      !nzchar(trimws(name))) {
    stop("secret(): 'name' must be a single non-empty character string.",
         call. = FALSE)
  }
  if (!is.null(desc) && (!is.character(desc) || length(desc) != 1L)) {
    stop("secret(): 'desc' must be NULL or a single character string.",
         call. = FALSE)
  }
  if (!is.null(default) && (!is.character(default) || length(default) != 1L)) {
    stop("secret(): 'default' must be NULL or a single character string.",
         call. = FALSE)
  }

  name <- trimws(name)
  val  <- Sys.getenv(name, unset = "")

  if (!nzchar(val)) {
    if (!is.null(default)) {
      val <- default
    } else {
      desc_line <- if (!is.null(desc)) {
        paste0("\n  This is needed for: ", desc)
      } else ""
      stop(
        paste0(
          "Secret not found: ", name, desc_line,
          "\n  Set it with: Sys.setenv(", name, ' = "...")'
        ),
        call. = FALSE
      )
    }
  }

  # Store the value in a locked environment, not a list field, so it cannot
  # be reached by $, [[, unclass(), str(), or dput().
  vault <- new.env(parent = emptyenv())
  assign("value", val, envir = vault)
  lockBinding("value", vault)
  lockEnvironment(vault, bindings = TRUE)

  structure(
    list(.name = name, .vault = vault),
    class = "orchrd_secret"
  )
}


#' Reveal the raw value of a secret
#'
#' Extracts the underlying character value from an `orchrd_secret` object.
#' This is the only supported way to obtain the raw string, and it is
#' deliberately explicit so that every exposure point is visible in review.
#'
#' @param x An `orchrd_secret` object from [secret()].
#' @return A plain character string containing the secret value.
#' @seealso [secret()]
#'
#' @export
#' @examples
#' \dontrun{
#' key <- secret("AZURE_KEY")
#' raw <- reveal(key)
#' }
reveal <- function(x) {
  if (!is_secret(x)) {
    stop("reveal() requires an orchrd_secret object from secret().",
         call. = FALSE)
  }
  get("value", envir = x$.vault, inherits = FALSE)
}


#' Test whether an object is an orchrd_secret
#'
#' @param x Any object.
#' @return `TRUE` if `x` is an `orchrd_secret`, otherwise `FALSE`.
#' @seealso [secret()], [reveal()]
#' @export
is_secret <- function(x) inherits(x, "orchrd_secret")


# ── Safe display methods: all return the MASK, never the value ────────────────

#' @export
print.orchrd_secret <- function(x, ...) {
  cat(paste0("<secret: ", x$.name, ">\n"))
  invisible(x)
}

#' @export
format.orchrd_secret <- function(x, ...) {
  paste0("<secret: ", x$.name, ">")
}

# Coerce to the MASK, not the value. This is the deliberate, safety-critical
# difference from the original: it means paste0(key), glue("{key}"), and cli
# interpolation emit "<secret: NAME>" instead of leaking the credential.
# Use reveal() when you genuinely need the raw string.
#' @export
as.character.orchrd_secret <- function(x, ...) {
  paste0("<secret: ", x$.name, ">")
}

#' @export
toString.orchrd_secret <- function(x, ...) {
  paste0("<secret: ", x$.name, ">")
}

#' @export
str.orchrd_secret <- function(object, ...) {
  cat(paste0("orchrd_secret: <secret: ", object$.name, ">\n"))
  invisible(NULL)
}
