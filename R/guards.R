# ==============================================================================
# orchrd: R/guards.R
# Conditional safeguards that can block a watcher callback from firing.
# ------------------------------------------------------------------------------
# guard() attaches a condition to any watcher so the callback only fires when
# the system is healthy enough to handle it. Pure R/shell for now, upgradeable
# to C++ sensors later.
#
# WINDOWS SAFETY: matches run_cmd.R / artifact.R - plain paste0()/string
# concatenation inside stop(), never cli::format_error() with named vectors.
# ASCII-only: no smart quotes, em-dashes, arrows, or emoji.
#
# Depends on internals brought over from tripwire: .tw_assert_exists(),
# .tw_state, .tw_log(), and the Rcpp stub .tw_update_callback().
# ==============================================================================


# ==============================================================================
# guard()
# ==============================================================================

#' Attach a safety condition to a watcher
#'
#' Wraps the watcher's existing callback so it only fires when
#' \code{condition()} returns \code{TRUE}. If the condition fails, the event
#' is logged and the \code{on_fail} action is taken instead.
#'
#' Multiple guards can be attached to the same watcher. They are evaluated
#' in the order they were added, and \emph{all} must pass for the callback to
#' fire.
#'
#' @param id        Character. Watcher ID to protect.
#' @param condition A zero-argument function that returns \code{TRUE} (safe to
#'                  fire) or \code{FALSE} (hold back), or a one-sided formula
#'                  \code{~ expr}.
#' @param message   Character. Human-readable reason shown when the guard
#'                  blocks the callback.
#' @param on_fail   One of \code{"warn"} (default), \code{"stop"}, or
#'                  \code{"silent"}. What to do when the guard blocks.
#'
#' @return Invisibly \code{TRUE}.
#'
#' @seealso [throttle()], [disk_ok()], [mem_ok()], [net_ok()]
#'
#' @examples
#' \dontrun{
#' id <- on_arrive("~/cbn_feeds/", action = function(event, path) {
#'   opennaijR::fetch("NGA", "inflation")
#' })
#'
#' # Only fetch if disk is not critically full
#' guard(id,
#'       condition = ~ disk_ok(threshold = 0.90),
#'       message   = "Disk over 90 percent full - skipping fetch")
#'
#' # Only fetch if available memory > 500 MB
#' guard(id,
#'       condition = ~ mem_ok(min_mb = 500),
#'       message   = "Low memory - pipeline paused")
#' }
#'
#' @export
guard <- function(id, condition, message = "Guard condition failed",
                  on_fail = c("warn", "stop", "silent")) {

  if (!is.character(id) && !is.numeric(id) || length(id) != 1L) {
    stop("`id` must be a single watcher id.", call. = FALSE)
  }
  id      <- as.character(id)
  on_fail <- match.arg(on_fail)

  if (!is.character(message) || length(message) != 1L || is.na(message)) {
    stop("`message` must be a single character string.", call. = FALSE)
  }
  .tw_assert_exists(id)

  # Accept a formula (~ expr) or a zero-argument function.
  cond_fn <- if (inherits(condition, "formula")) {
    env  <- environment(condition)
    expr <- condition[[length(condition)]]  # rhs of one- or two-sided formula
    function() eval(expr, envir = env)
  } else if (is.function(condition)) {
    condition
  } else {
    stop("`condition` must be a zero-argument function or a formula.",
         call. = FALSE)
  }

  old_cb <- .tw_state$watchers[[id]]$callback
  msg    <- message  # capture the reason before building the closure

  new_cb <- function(event, path) {
    ok <- tryCatch(
      isTRUE(cond_fn()),
      error = function(e) {
        warning("[orchrd] guard condition error: ", conditionMessage(e),
                call. = FALSE)
        FALSE
      }
    )

    if (ok) {
      old_cb(event, path)
    } else {
      .tw_log(id, paste0("GUARDED:", event), path)
      switch(on_fail,
             warn   = warning("[orchrd] Guard blocked event (", event, "): ",
                              msg, call. = FALSE),
             stop   = stop("[orchrd] Guard blocked event (", event, "): ",
                           msg, call. = FALSE),
             silent = invisible(NULL)
      )
    }
  }

  .tw_state$watchers[[id]]$callback <- new_cb
  # Update the live C++ callback reference.
  .tw_update_callback(id, new_cb)

  base::message("[orchrd] Guard attached to watcher '", id, "'")
  invisible(TRUE)
}


# ==============================================================================
# Built-in condition helpers (pure R - no C++ required yet)
# ==============================================================================

#' Check available disk space
#'
#' Returns \code{TRUE} if disk usage on the partition containing \code{path}
#' is at or below \code{threshold}. Fails open: if disk stats cannot be read,
#' returns \code{TRUE} so a guard never blocks purely because of a probe error.
#'
#' @param path      Character. Path on the partition to check. Default
#'                  \code{"."} (current working directory).
#' @param threshold Numeric in \eqn{[0, 1]}. Maximum acceptable usage
#'                  fraction. Default \code{0.90} (90 percent).
#'
#' @return Logical scalar.
#'
#' @examples
#' disk_ok()          # TRUE if under 90 percent used on current partition
#' disk_ok(threshold = 0.95)
#'
#' @export
disk_ok <- function(path = ".", threshold = 0.90) {
  info <- tryCatch(
    {
      if (.Platform$OS.type == "windows") {
        # Resolve to an absolute path first: Split-Path -Qualifier needs a
        # drive letter.
        abs_path <- normalizePath(path, mustWork = FALSE)
        cmd <- sprintf(
          paste0("powershell -NoProfile -Command \"$d = Get-PSDrive -Name ",
                 "(Split-Path -Qualifier '%s').TrimEnd(':'); ",
                 "$d.Used / ($d.Used + $d.Free)\""),
          abs_path
        )
        result <- suppressWarnings(system(cmd, intern = TRUE))
        # Take only the last line, guarding against warning/info lines.
        as.numeric(trimws(tail(result, 1L)))
      } else {
        lines <- system(
          paste("df -k", shQuote(normalizePath(path, mustWork = FALSE))),
          intern = TRUE
        )
        parts <- strsplit(trimws(lines[length(lines)]), "\\s+")[[1L]]
        used  <- as.numeric(parts[3L])
        avail <- as.numeric(parts[4L])
        used / (used + avail)
      }
    },
    error = function(e) {
      warning("[orchrd] disk_ok() could not read disk stats: ",
              conditionMessage(e), call. = FALSE)
      NA_real_
    }
  )

  # Collapse to a single numeric regardless of what the probe returned.
  info <- suppressWarnings(as.numeric(info))
  info <- if (length(info) != 1L || is.nan(info)) NA_real_ else info

  if (is.na(info)) return(TRUE)  # fail open
  isTRUE(info <= threshold)
}


#' Check available system memory
#'
#' Returns \code{TRUE} if free/available memory is at least \code{min_mb}
#' megabytes. Fails open on probe error.
#'
#' @param min_mb Numeric. Minimum megabytes of free memory required.
#'               Default \code{500}.
#'
#' @return Logical scalar.
#'
#' @export
mem_ok <- function(min_mb = 500) {
  free_mb <- tryCatch(
    {
      if (.Platform$OS.type == "windows") {
        cmd <- paste0("powershell -NoProfile -Command ",
                      "\"(Get-CimInstance Win32_OperatingSystem)",
                      ".FreePhysicalMemory / 1024\"")
        as.numeric(trimws(tail(system(cmd, intern = TRUE), 1L)))
      } else if (file.exists("/proc/meminfo")) {
        lines <- readLines("/proc/meminfo", warn = FALSE)
        avail <- grep("^MemAvailable:", lines, value = TRUE)
        if (length(avail)) {
          as.numeric(gsub("[^0-9]", "", avail)) / 1024  # kB to MB
        } else {
          NA_real_
        }
      } else {
        # macOS: vm_stat
        raw  <- system("vm_stat", intern = TRUE)
        free <- grep("Pages free", raw, value = TRUE)
        spec <- grep("Pages speculative", raw, value = TRUE)
        page_size  <- 4096  # bytes (standard on macOS)
        pages_free <- as.numeric(gsub("[^0-9]", "", free))
        pages_spec <- as.numeric(gsub("[^0-9]", "", spec))
        ((pages_free + pages_spec) * page_size) / 1024^2
      }
    },
    error = function(e) {
      warning("[orchrd] mem_ok() could not read memory stats: ",
              conditionMessage(e), call. = FALSE)
      NA_real_
    }
  )

  free_mb <- suppressWarnings(as.numeric(free_mb))
  free_mb <- if (length(free_mb) != 1L || is.nan(free_mb)) NA_real_ else free_mb

  if (is.na(free_mb)) return(TRUE)  # fail open
  isTRUE(free_mb >= min_mb)
}


#' Check network reachability
#'
#' Pings \code{host} and returns \code{TRUE} if it responds within
#' \code{timeout} seconds. Fails open on probe error.
#'
#' @param host    Character. Hostname or IP to ping. Default
#'                \code{"8.8.8.8"} (Google DNS - quick, reliable).
#' @param timeout Numeric. Seconds to wait. Default \code{3}.
#'
#' @return Logical scalar.
#'
#' @export
net_ok <- function(host = "8.8.8.8", timeout = 3) {
  tryCatch(
    {
      sysname <- Sys.info()[["sysname"]]
      if (.Platform$OS.type == "windows") {
        # Windows: -w is per-reply timeout in milliseconds.
        cmd <- sprintf("ping -n 1 -w %d %s",
                       as.integer(timeout * 1000), shQuote(host))
      } else if (identical(sysname, "Darwin")) {
        # macOS: -W is milliseconds; -t is overall timeout in seconds.
        cmd <- sprintf("ping -c 1 -t %d %s",
                       max(1L, as.integer(timeout)), shQuote(host))
      } else {
        # Linux: -W is seconds to wait for a reply.
        cmd <- sprintf("ping -c 1 -W %d %s",
                       max(1L, as.integer(timeout)), shQuote(host))
      }
      ret <- system(cmd, ignore.stdout = TRUE, ignore.stderr = TRUE)
      identical(ret, 0L)
    },
    error = function(e) {
      warning("[orchrd] net_ok() ping failed: ", conditionMessage(e),
              call. = FALSE)
      TRUE  # fail open
    }
  )
}
