# =============================================================================
# R/run_cmd.R
# Run any system command. Get structured output back.
#
# WINDOWS FIX (2026-04-19): processx can return a RAWSXP (type 29) exit code
# on Windows. cli::format_error() with named vectors then triggers a recursive
# error crash. Fix: coerce status with as.integer() and use plain paste()
# inside stop() calls.
# =============================================================================

#' Run a system command cleanly
#'
#' A unified, cross-platform interface for running system commands.
#' Returns a structured \code{orchrd_result} object — exit code, stdout,
#' stderr, and elapsed time.
#'
#' @param cmd Character. The command to run, e.g. \code{"git status"}.
#'   For arguments containing spaces or quotes, use \code{args} instead.
#' @param args Character vector. Arguments passed separately — safer for
#'   paths with spaces or special characters.
#' @param dir Character. Working directory. Defaults to current directory.
#' @param env Named character vector. Extra environment variables. These are
#'   \emph{merged} into the current environment (PATH etc. are preserved).
#' @param timeout Numeric. Seconds before the process is killed. Default 60.
#'   Use \code{Inf} for long-running operations (large pushes, uploads).
#' @param echo Logical. Stream output in real-time (default FALSE).
#' @param error_ok Logical. Return result even on failure (default FALSE).
#'
#' @return An S3 object of class \code{orchrd_result} with fields:
#'   \code{$ok}, \code{$status}, \code{$stdout}, \code{$stderr},
#'   \code{$elapsed_sec}, \code{$cmd}.
#'
#' @export
#' @examples
#' \dontrun{
#' run_cmd("git status")
#' run_cmd("git", args = c("commit", "-m", "my commit message"))
#' }
run_cmd <- function(
    cmd,
    args     = character(),
    dir      = ".",
    env      = character(),
    timeout  = 60,
    echo     = FALSE,
    error_ok = FALSE
) {
  # ── Fix #1: refuse fragile parsing of quoted commands ──────────────────────
  # Splitting on spaces silently mangles quoted arguments. If the caller
  # passes a quoted string inside `cmd` (and no explicit `args`), stop and
  # point them at the safe `args =` form.
  if (length(args) == 0L && grepl("[\"']", cmd)) {
    stop(
      paste0(
        "Quoted arguments detected in `cmd`. Space-splitting would ",
        "mis-parse them. Pass arguments via `args` instead, e.g.\n",
        "  run_cmd(\"git\", args = c(\"commit\", \"-m\", \"my message\"))"
      ),
      call. = FALSE
    )
  }

  if (length(args) == 0L && grepl(" ", cmd)) {
    parts <- .split_cmd(cmd)
    exe   <- parts[[1]]
    args  <- parts[-1]
  } else {
    exe <- cmd
  }

  # ── Fix #2: resolve executable, tolerant of Windows .cmd/.bat wrappers ─────
  exe_path <- .which_exe(exe)
  if (!nzchar(exe_path)) {
    stop(
      paste0("Command not found: '", exe, "'. Is it installed and on your PATH?"),
      call. = FALSE
    )
  }

  # ── Fix #3: merge env into the current environment (don't replace it) ──────
  # processx::run(env = ...) REPLACES the whole environment. Merging with
  # Sys.getenv() preserves PATH and everything else. Later keys win, so the
  # caller's `env` overrides existing values.
  run_env <- NULL
  if (length(env)) {
    current <- Sys.getenv()
    merged  <- c(current, env)
    merged  <- merged[!duplicated(names(merged), fromLast = TRUE)]
    run_env <- merged
  }

  # ── Execute via processx ───────────────────────────────────────────────────
  start <- proc.time()[["elapsed"]]

  proc <- tryCatch(
    processx::run(
      command         = exe_path,
      args            = args,
      wd              = dir,
      env             = run_env,
      timeout         = if (is.infinite(timeout)) NULL else timeout,
      echo            = echo,
      error_on_status = FALSE
    ),
    error = function(e) {
      stop(
        paste0("Failed to run '", exe, "': ", conditionMessage(e)),
        call. = FALSE
      )
    }
  )

  elapsed <- round(proc.time()[["elapsed"]] - start, 3)

  # ── Coerce exit code to plain integer (Windows RAWSXP safety) ──────────────
  safe_status <- tryCatch(
    {
      s <- as.integer(proc$status)
      if (length(s) == 0L || is.na(s)) -1L else s
    },
    error   = function(e) -1L,
    warning = function(w) -1L
  )

  # ── Build structured result ────────────────────────────────────────────────
  result <- structure(
    list(
      cmd         = paste(c(exe, args), collapse = " "),
      status      = safe_status,
      ok          = (safe_status == 0L),
      stdout      = .split_lines(proc$stdout),
      stderr      = .split_lines(proc$stderr),
      elapsed_sec = elapsed
    ),
    class = "orchrd_result"
  )

  # ── Surface failure ────────────────────────────────────────────────────────
  if (!result$ok && !error_ok) {
    err_lines  <- if (length(result$stderr)) result$stderr else result$stdout
    first_line <- if (length(err_lines)) paste0("\n  ", err_lines[1]) else ""
    stop(
      paste0(
        "Command failed (exit ", result$status, "): ",
        result$cmd, first_line
      ),
      call. = FALSE
    )
  }

  # ── Fix #5: interpolate values explicitly, not from the calling frame ──────
  if (!echo && result$ok) {
    cli::cli_inform(
      c("v" = "Done in {.val {elapsed}}s: {.code {result$cmd}}"),
      .frequency = "always"
    )
  }

  invisible(result)
}

#' @export
print.orchrd_result <- function(x, ...) {
  icon <- if (x$ok) cli::col_green("\u2705") else cli::col_red("\u274c")
  cli::cli_text("{icon} [{x$status}] {.code {x$cmd}}  ({x$elapsed_sec}s)")
  if (length(x$stdout)) {
    cli::cli_text("{cli::col_grey(paste(x$stdout, collapse = '\n'))}")
  }
  if (!x$ok && length(x$stderr)) {
    n <- min(3L, length(x$stderr))
    cli::cli_text(
      "{cli::col_red(paste(x$stderr[seq_len(n)], collapse = '\n'))}"
    )
  }
  invisible(x)
}

# ── Internal helper: Windows-tolerant executable resolution (Fix #2) ─────────
.which_exe <- function(exe) {
  p <- Sys.which(exe)
  if (nzchar(p)) return(unname(p))

  # On Windows, aws/npm/etc. ship as .cmd / .bat wrappers that Sys.which()
  # may miss if the bare name is given. Try common extensions.
  if (.Platform$OS.type == "windows") {
    for (ext in c(".cmd", ".bat", ".exe")) {
      p2 <- Sys.which(paste0(exe, ext))
      if (nzchar(p2)) return(unname(p2))
    }
  }
  ""
}
