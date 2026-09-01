# =============================================================================
# R/health_check.R
# Check that endpoints and services are alive before a pipeline runs.
# Fast, lightweight — uses HEAD requests by default.
#
# WINDOWS SAFETY: matches run_cmd.R / artifact.R / config.R conventions —
# plain paste0() inside stop(), never cli::format_error() with named vectors,
# and all cli templates interpolate probe text via {.val {var}} so literal
# braces in an error message can't be re-evaluated as glue.
# =============================================================================

#' Check that endpoints and services are alive
#'
#' Sends lightweight probes (HTTP HEAD requests for URLs, socket tests for
#' hosts, command checks for system tools) and returns a tidy data frame
#' reporting the status of each. Designed to be called before a pipeline
#' that depends on external services so you know upfront which sources are
#' reachable.
#'
#' Each target is classified as:
#' \itemize{
#'   \item **URL** — starts with `http://` or `https://` -> HTTP HEAD probe.
#'   \item **host / host:port** — contains a dot or an explicit `:port`
#'     -> TCP socket probe (default port 80).
#'   \item **command** — a bare token with no dot, slash, or colon
#'     -> [Sys.which()] lookup.
#' }
#' The classification can be forced per target with the `types` argument.
#'
#' By default `health_check()` **does not stop** on failure — it reports
#' every result and lets you decide. Set `stop_on_fail = TRUE` to make it
#' halt the pipeline if any check fails.
#'
#' @param ... Named or unnamed character strings. Each is one endpoint to
#'   check. See Details for how each is classified.
#' @param timeout Numeric. Seconds before a probe times out (default `10`).
#' @param ok_status Integer. HTTP status codes below this are considered
#'   healthy (default `400`, so 4xx/5xx are failures). Set to `500` to
#'   treat 4xx as reachable-but-erroring.
#' @param types Optional named/positional character vector to force the
#'   probe type of a target: one of `"http"`, `"socket"`, `"cmd"`. Length
#'   must match the number of targets, or be `NULL` (default, auto-detect).
#' @param stop_on_fail Logical. If `TRUE`, throws an error after checking
#'   all endpoints if any failed (default `FALSE`).
#' @param verbose Logical. Print results to the console (default `TRUE`).
#'
#' @return A data frame with columns `name`, `target`, `type`, `ok`,
#'   `status`, `response_ms`. Invisibly returned so it can be used in a
#'   pipeline.
#'
#' @export
#' @examples
#' \dontrun{
#' health_check(
#'   CBN  = "https://www.cbn.gov.ng/rates/mprates.asp",
#'   NBS  = "https://nigerianstat.gov.ng"
#' )
#'
#' health_check("https://api.example.com", stop_on_fail = TRUE)
#'
#' health_check(git = "git", pwsh = "pwsh", gh = "gh")
#' }
health_check <- function(
    ...,
    timeout      = 10,
    ok_status    = 400L,
    types        = NULL,
    stop_on_fail = FALSE,
    verbose      = TRUE
) {
  targets <- list(...)

  empty <- data.frame(
    name = character(), target = character(), type = character(),
    ok = logical(), status = character(), response_ms = numeric(),
    stringsAsFactors = FALSE
  )

  if (length(targets) == 0L) {
    cli::cli_warn("health_check() called with no targets.")
    return(invisible(empty))
  }

  # ── Assign names to unnamed entries ────────────────────────────────────────
  nms <- names(targets)
  if (is.null(nms)) nms <- rep("", length(targets))
  for (i in seq_along(targets)) {
    if (!nzchar(nms[i])) nms[i] <- as.character(targets[[i]])
  }

  # ── Validate a forced-types vector if supplied ─────────────────────────────
  if (!is.null(types)) {
    if (length(types) != length(targets)) {
      stop(
        paste0("`types` must have one entry per target (got ",
               length(types), " for ", length(targets), " target(s))."),
        call. = FALSE
      )
    }
    bad <- setdiff(types, c("http", "socket", "cmd"))
    if (length(bad)) {
      stop(
        paste0("Invalid `types` value(s): ", paste(bad, collapse = ", "),
               ". Use \"http\", \"socket\", or \"cmd\"."),
        call. = FALSE
      )
    }
  }

  if (verbose) {
    cli::cli_rule(
      left  = cli::style_bold("health_check"),
      right = paste0(length(targets), " target(s)")
    )
  }

  # ── Probe each target ──────────────────────────────────────────────────────
  rows <- lapply(seq_along(targets), function(i) {
    nm     <- nms[i]
    target <- as.character(targets[[i]])
    type   <- if (!is.null(types)) types[i] else .classify_target(target)

    result <- switch(
      type,
      http   = .probe_http(target, timeout, ok_status),
      socket = .probe_socket(target, timeout),
      cmd    = .probe_cmd(target),
      # Defensive default — should be unreachable given classification.
      list(ok = FALSE, status = "unknown target type", response_ms = NA_real_)
    )

    if (verbose) {
      icon <- if (result$ok) cli::col_green("\u2705") else cli::col_red("\u274c")
      ms   <- if (!is.na(result$response_ms)) {
        cli::col_grey(paste0(" (", result$response_ms, "ms)"))
      } else ""
      # {.val ...} keeps literal braces in status text from crashing cli.
      cli::cli_text("  {icon} {.field {nm}}: {.val {result$status}}{ms}")
    }

    data.frame(
      name        = nm,
      target      = target,
      type        = type,
      ok          = result$ok,
      status      = result$status,
      response_ms = result$response_ms,
      stringsAsFactors = FALSE
    )
  })

  df <- do.call(rbind, rows)

  n_ok     <- sum(df$ok)
  n_failed <- nrow(df) - n_ok

  if (verbose) {
    cli::cli_rule()
    if (n_failed == 0L) {
      cli::cli_alert_success("All {nrow(df)} target(s) reachable.")
    } else {
      cli::cli_alert_warning("{n_ok} reachable, {n_failed} unreachable.")
    }
  }

  if (stop_on_fail && n_failed > 0L) {
    failed_names <- df[!df$ok, "name"]
    # paste0() only inside stop() (Windows RAWSXP safety).
    stop(
      paste0(
        "health_check() failed: ", n_failed, " target(s) unreachable\n  ",
        paste(failed_names, collapse = ", ")
      ),
      call. = FALSE
    )
  }

  invisible(df)
}

# ── Internal: classify a target into a probe type ─────────────────────────────
# Fix: previous inline logic misrouted bare commands (e.g. "git") to the
# socket prober due to && binding tighter than ||. Explicit and testable now.
#' @noRd
.classify_target <- function(target) {
  if (grepl("^https?://", target)) return("http")
  # Explicit port -> socket. Guard against a leading ":" only.
  if (grepl(":[0-9]+$", target))   return("socket")
  # A dotted name (domain or IP) with no path -> socket.
  if (grepl("\\.", target) && !grepl("[/\\\\]", target)) return("socket")
  # Everything else (bare token, no dot/slash/colon) -> command.
  "cmd"
}

# ── Internal probes ────────────────────────────────────────────────────────────

#' @noRd
.probe_http <- function(url, timeout, ok_status = 400L) {
  start <- proc.time()[["elapsed"]]

  result <- tryCatch({
    if (requireNamespace("httr2", quietly = TRUE)) {
      req <- httr2::request(url)
      req <- httr2::req_method(req, "HEAD")
      req <- httr2::req_timeout(req, timeout)
      req <- httr2::req_error(req, is_error = function(r) FALSE)
      resp <- httr2::req_perform(req)
      code <- httr2::resp_status(resp)
      list(ok = code < ok_status, status = paste0("HTTP ", code))
    } else {
      # Fallback: only open a connection here (no wasted url() otherwise).
      con <- url(url, open = "")
      on.exit(tryCatch(close(con), error = function(e) NULL), add = TRUE)
      readLines(con, n = 1L, warn = FALSE)
      list(ok = TRUE, status = "reachable")
    }
  }, error = function(e) {
    msg <- conditionMessage(e)
    if (grepl("timeout|timed out|time out", msg, ignore.case = TRUE)) {
      list(ok = FALSE, status = paste0("timeout after ", timeout, "s"))
    } else {
      list(ok = FALSE, status = substr(msg, 1L, 60L))
    }
  }, warning = function(w) {
    list(ok = FALSE, status = substr(conditionMessage(w), 1L, 60L))
  })

  elapsed_ms <- round((proc.time()[["elapsed"]] - start) * 1000)
  list(ok = result$ok, status = result$status, response_ms = elapsed_ms)
}

#' @noRd
.probe_socket <- function(target, timeout) {
  # Split off an optional :port from the right so IPv6-ish inputs are safer.
  if (grepl(":[0-9]+$", target)) {
    port <- as.integer(sub(".*:([0-9]+)$", "\\1", target))
    host <- sub(":[0-9]+$", "", target)
  } else {
    host <- target
    port <- 80L
  }

  start <- proc.time()[["elapsed"]]
  result <- tryCatch({
    # blocking = TRUE so the TCP handshake actually completes within timeout.
    con <- socketConnection(
      host     = host,
      port     = port,
      timeout  = timeout,
      open     = "r+",
      blocking = TRUE
    )
    close(con)
    list(ok = TRUE, status = paste0("port ", port, " open"))
  }, error = function(e) {
    msg <- conditionMessage(e)
    list(
      ok     = FALSE,
      status = if (grepl("timeout|refused|connect|cannot open",
                         msg, ignore.case = TRUE)) {
        paste0("port ", port, " unreachable")
      } else substr(msg, 1L, 60L)
    )
  }, warning = function(w) {
    list(ok = FALSE, status = paste0("port ", port, " unreachable"))
  })

  elapsed_ms <- round((proc.time()[["elapsed"]] - start) * 1000)
  list(ok = result$ok, status = result$status, response_ms = elapsed_ms)
}

#' @noRd
.probe_cmd <- function(cmd) {
  path <- Sys.which(cmd)
  if (nzchar(path)) {
    list(ok = TRUE, status = paste0("found at ", path), response_ms = 0)
  } else {
    list(ok = FALSE, status = "not found on PATH", response_ms = NA_real_)
  }
}
