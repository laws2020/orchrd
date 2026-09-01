# =============================================================================
# R/portal_debug.R
# Portal <-> API communication diagnostics for Dockerized web projects.
#
# Cross-platform: talks to the Docker CLI directly via processx (never through
# PowerShell), with a bounded timeout so a wedged daemon cannot hang R.
# ASCII-only: no smart quotes, arrows, em-dashes or emoji anywhere.
#
# Public API:
#   debug_portal_api()     - inspect network + recent logs for two containers
#   audit_portal_ids()     - cross-check HTML element IDs against JS references
#   audit_portal_networks()- flag localhost / 127.0.0.1 refs in portal JS
# =============================================================================

# ---- Internal: run a docker subcommand with a bounded timeout ----------------
.docker_run <- function(args, timeout = 20) {
  exe <- Sys.which("docker")
  if (!nzchar(exe)) {
    return(list(ok = FALSE, status = -1L, stdout = character(),
                stderr = "docker not found on PATH"))
  }

  proc <- tryCatch(
    processx::run(
      command         = "docker",
      args            = args,
      timeout         = if (is.infinite(timeout)) NULL else timeout,
      error_on_status = FALSE
    ),
    error = function(e) NULL
  )

  if (is.null(proc)) {
    return(list(ok = FALSE, status = 124L, stdout = character(),
                stderr = "docker call timed out or failed to start"))
  }

  # Defensive integer coercion (Windows can return a RAWSXP status).
  status <- tryCatch({
    s <- as.integer(proc$status)
    if (length(s) == 0L || is.na(s)) -1L else s
  }, error = function(e) -1L, warning = function(w) -1L)

  split_lines <- function(x) {
    if (is.null(x) || !nzchar(x)) character() else strsplit(x, "\r?\n")[[1]]
  }

  list(
    ok     = (status == 0L),
    status = status,
    stdout = split_lines(proc$stdout),
    stderr = split_lines(proc$stderr)
  )
}


#' Debug Portal and API Communication
#'
#' Inspects Docker networking and recent container logs to help diagnose
#' communication problems between a web portal and its API. Talks to the
#' Docker CLI directly (cross-platform) with a bounded timeout.
#'
#' @param portal_container Name or ID of the portal container.
#' @param api_container Name or ID of the API container.
#' @param tail Integer. Number of recent log lines to fetch per container.
#' @param timeout Numeric. Seconds before a docker call is abandoned.
#' @param verbose Logical. Print progress and output (default TRUE).
#'
#' @return Invisibly, a named list with elements network, portal_logs,
#'   api_logs (each a structured result list with ok/status/stdout/stderr).
#'
#' @export
#' @examples
#' \dontrun{
#' debug_portal_api()
#' d <- debug_portal_api("my-portal", "my-api")
#' d$network$stdout
#' }
debug_portal_api <- function(
    portal_container = "trsbs-portal",
    api_container    = "trsbs-api",
    tail             = 20L,
    timeout          = 20,
    verbose          = TRUE
) {
  if (!nzchar(Sys.which("docker"))) {
    stop(paste0("docker not found on PATH. Install Docker or start it, ",
                "then re-run debug_portal_api()."), call. = FALSE)
  }

  if (verbose) message("STEP 1: checking Docker networks for ", portal_container)
  network <- .docker_run(
    c("inspect", portal_container,
      "--format", "{{json .NetworkSettings.Networks}}"),
    timeout = timeout
  )
  if (verbose) {
    if (network$ok) cat(network$stdout, sep = "\n")
    else message("  network inspect failed: ",
                 paste(network$stderr, collapse = " "))
  }

  if (verbose) message("STEP 2: reading recent portal logs (", portal_container, ")")
  portal_logs <- .docker_run(
    c("logs", "--tail", as.character(tail), portal_container),
    timeout = timeout
  )
  if (verbose) cat(c(portal_logs$stdout, portal_logs$stderr), sep = "\n")

  if (verbose) message("STEP 3: reading recent API logs (", api_container, ")")
  api_logs <- .docker_run(
    c("logs", "--tail", as.character(tail), api_container),
    timeout = timeout
  )
  if (verbose) cat(c(api_logs$stdout, api_logs$stderr), sep = "\n")

  invisible(list(
    network     = network,
    portal_logs = portal_logs,
    api_logs    = api_logs
  ))
}


#' Audit Portal HTML IDs Against JavaScript References
#'
#' Extracts every element ID from the portal index.html and reports IDs that
#' are not referenced by any JavaScript file in the js/ directory. Matching is
#' aggregated across all .js files and uses word boundaries to avoid the
#' "foo matches foobar" false positive.
#'
#' @param portal_path Path to the portal project. Default "trsbs-portal".
#' @param html_file Character. HTML file to scan, relative to portal_path.
#' @param verbose Logical. Print findings (default TRUE).
#'
#' @return Invisibly, a data frame with columns id and referenced (logical).
#'
#' @export
#' @examples
#' \dontrun{
#' audit_portal_ids()
#' audit_portal_ids("C:/projects/trsbs-portal")
#' }
audit_portal_ids <- function(
    portal_path = "trsbs-portal",
    html_file   = "index.html",
    verbose     = TRUE
) {
  html_path <- file.path(portal_path, html_file)
  js_dir    <- file.path(portal_path, "js")

  if (!file.exists(html_path)) {
    stop(paste0("Could not find ", html_file, " at: ", html_path), call. = FALSE)
  }
  if (!dir.exists(js_dir)) {
    stop(paste0("Could not find JavaScript directory at: ", js_dir), call. = FALSE)
  }

  html_lines <- readLines(html_path, warn = FALSE, encoding = "UTF-8")

  # Capture EVERY id="..." / id='...' occurrence, including several per line.
  matches  <- regmatches(
    html_lines,
    gregexpr("id\\s*=\\s*[\"']([^\"']+)[\"']", html_lines, perl = TRUE)
  )
  flat     <- unlist(matches, use.names = FALSE)
  html_ids <- unique(sub("id\\s*=\\s*[\"']([^\"']+)[\"'].*", "\\1", flat,
                         perl = TRUE))

  if (length(html_ids) == 0L) {
    if (verbose) message("No element IDs found in ", html_file, ".")
    return(invisible(data.frame(id = character(), referenced = logical(),
                                stringsAsFactors = FALSE)))
  }

  js_files <- list.files(js_dir, pattern = "\\.js$", full.names = TRUE)
  js_blob  <- unlist(lapply(js_files, function(f) {
    tryCatch(readLines(f, warn = FALSE, encoding = "UTF-8"),
             error = function(e) character())
  }), use.names = FALSE)
  js_text  <- paste(js_blob, collapse = "\n")

  # Word-boundary match so "foo" does not match "foobar".
  referenced <- vapply(html_ids, function(id) {
    grepl(paste0("\\b", .escape_regex(id), "\\b"), js_text, perl = TRUE)
  }, logical(1))

  df <- data.frame(id = html_ids, referenced = referenced,
                   stringsAsFactors = FALSE, row.names = NULL)

  if (verbose) {
    missing <- df$id[!df$referenced]
    if (length(missing) == 0L) {
      message("All ", nrow(df), " HTML ID(s) are referenced in js/.")
    } else {
      message(length(missing), " HTML ID(s) not referenced in any js/ file:")
      for (id in missing) message("  - ", id)
    }
  }

  invisible(df)
}


#' Audit Portal JavaScript for localhost API References
#'
#' Scans every .js file under the portal js/ directory for hardcoded
#' localhost / 127.0.0.1 endpoints, which break when the API runs in a
#' separate Docker container. Findings are returned as a data frame instead
#' of a stream of warnings.
#'
#' @param portal_path Path to the portal project. Default "trsbs-portal".
#' @param warn Logical. Emit a single summary warning if hits are found
#'   (default TRUE).
#'
#' @return Invisibly, a data frame with columns file, line, text.
#'
#' @export
#' @examples
#' \dontrun{
#' audit_portal_networks()
#' hits <- audit_portal_networks("../trsbs-portal")
#' }
audit_portal_networks <- function(
    portal_path = "trsbs-portal",
    warn        = TRUE
) {
  js_dir <- file.path(portal_path, "js")
  if (!dir.exists(js_dir)) {
    stop(paste0("Could not find JavaScript directory at: ", js_dir), call. = FALSE)
  }

  js_files <- list.files(js_dir, pattern = "\\.js$", full.names = TRUE)
  pattern  <- "localhost:|127\\.0\\.0\\.1:"

  rows <- list()
  for (f in js_files) {
    lines <- tryCatch(readLines(f, warn = FALSE, encoding = "UTF-8"),
                      error = function(e) character())
    hits  <- grep(pattern, lines)
    for (ln in hits) {
      rows[[length(rows) + 1L]] <- data.frame(
        file = basename(f),
        line = ln,
        text = trimws(lines[ln]),
        stringsAsFactors = FALSE
      )
    }
  }

  df <- if (length(rows)) do.call(rbind, rows) else
    data.frame(file = character(), line = integer(), text = character(),
               stringsAsFactors = FALSE)

  if (nrow(df) > 0L && warn) {
    warning(nrow(df), " localhost/127.0.0.1 API reference(s) found across ",
            length(unique(df$file)), " file(s). Replace with the container ",
            "service name or an environment-driven endpoint.", call. = FALSE)
  } else if (nrow(df) == 0L) {
    message("No localhost/127.0.0.1 API references found in js/.")
  }

  invisible(df)
}


# ---- Internal: escape regex metacharacters in a literal id -------------------
.escape_regex <- function(x) {
  gsub("([.\\\\+*?\\[^\\]$(){}=!<>|:#/-])", "\\\\\\1", x, perl = TRUE)
}
