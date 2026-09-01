# ==============================================================================
# orchrd: R/schedule.R
# on_schedule(): cron-style in-session scheduling via {later}
# (formerly tripwire GAP 4).
#
# WINDOWS SAFETY: plain paste0()/string concatenation inside stop(), never
# cli::format_error() with named vectors. ASCII-only throughout.
# ------------------------------------------------------------------------------
# Watches for TIME events alongside FILE events from a single package.
#
# Design:
#   - later::later() for non-blocking scheduling on R's event loop.
#   - Minimal 5-field cron parser (min hour dom mon dow).
#   - Returns an ID compatible with unwatch() for uniform teardown.
#   - No system cron, no daemon, no root access.
#
# Supported cron syntax (subset):
#   *       every unit
#   N       exactly N
#   */N     every N units, stepping from the field minimum
#   N,M     list
#   N-M     inclusive range
#
# Examples:
#   "* * * * *"      every minute
#   "0 8 * * 1"      08:00 every Monday
#   "*/15 * * * *"   every 15 minutes
#   "0 9,17 * * *"   09:00 and 17:00 daily
# ==============================================================================

#' Schedule an action on a cron-style time expression
#'
#' Registers a recurring in-session timer that fires \code{action} whenever the
#' current time matches the cron expression. The timer runs on R's event loop
#' via \code{later::later()}: it does not block the session and needs no system
#' cron or root access.
#'
#' The returned ID is compatible with [unwatch()] so teardown is consistent
#' with filesystem watchers.
#'
#' @param cron   Character. A 5-field cron expression
#'               (\code{"min hour dom mon dow"}). See Details.
#' @param action A zero-argument function or a one-sided formula \code{~ expr}.
#' @param id     Optional character ID. Auto-generated when \code{NULL}.
#' @param tz     Time zone for schedule evaluation. Default \code{""} (system).
#'
#' @details
#' Cron fields (left to right): minute (0-59), hour (0-23), day-of-month
#' (1-31), month (1-12), day-of-week (0-6, 0 = Sunday).
#'
#' Supported syntax per field:
#' \describe{
#'   \item{\code{*}}{Every value.}
#'   \item{\code{N}}{Exactly N.}
#'   \item{\code{*/N}}{Every N-th value, stepping from the field minimum.}
#'   \item{\code{N,M,...}}{Explicit list.}
#'   \item{\code{N-M}}{Inclusive range.}
#' }
#'
#' @return Invisibly returns the schedule ID. Pass to [unwatch()] to cancel.
#'
#' @seealso [unwatch()], [on_arrive()]
#'
#' @examples
#' \dontrun{
#' on_schedule("0 8 * * *", action = ~ fetch_cbn_rates())
#' on_schedule("*/15 9-17 * * 1-5",
#'             action = function() log_step("Heartbeat check"))
#' id <- on_schedule("* * * * *", action = ~ message(Sys.time()))
#' unwatch(id)
#' }
#'
#' @export
on_schedule <- function(cron, action, id = NULL, tz = "") {
  if (!requireNamespace("later", quietly = TRUE)) {
    stop(
      "The 'later' package is required for on_schedule().\n",
      "  Install it with: install.packages('later')",
      call. = FALSE
    )
  }
  if (!is.character(cron) || length(cron) != 1L || !nzchar(cron)) {
    stop("`cron` must be a single non-empty string.", call. = FALSE)
  }

  id <- if (is.null(id)) .tw_next_id() else as.character(id)
  if (id %in% names(.tw_state$watchers)) {
    stop("A watcher/schedule with id '", id, "' already exists. ",
         "Use unwatch('", id, "') first.", call. = FALSE)
  }

  # Resolve action to a zero-argument function.
  fn <- if (inherits(action, "formula")) {
    env  <- environment(action)
    expr <- action[[2L]]
    function() eval(expr, envir = env)
  } else if (is.function(action)) {
    fm <- formals(action)
    if (length(fm) > 0L && !"..." %in% names(fm)) {
      stop("`action` for on_schedule() must take zero arguments.", call. = FALSE)
    }
    action
  } else {
    stop("`action` must be a zero-argument function or a formula.", call. = FALSE)
  }

  fields <- .cron_parse(cron)  # validates and returns the parsed list

  .tw_state$watchers[[id]] <- list(
    id        = id,
    type      = "schedule",
    path      = cron,           # path field reused for the cron string
    pattern   = NA_character_,
    events    = "time",
    recursive = FALSE,
    debounce  = 0L,
    callback  = fn,
    status    = "active",
    created   = Sys.time(),
    n_fired   = 0L
  )

  message("[orchrd] Schedule registered: '", id, "' [", cron, "]")
  .schedule_tick(id, fields, fn, tz)
  invisible(id)
}


# ------------------------------------------------------------------------------
# Internal: parse a cron expression into per-field integer vectors.
# ------------------------------------------------------------------------------

#' @noRd
.cron_parse <- function(cron) {
  parts <- strsplit(trimws(cron), "\\s+")[[1L]]
  if (length(parts) != 5L) {
    stop("Cron expression must have exactly 5 fields (min hour dom mon dow).\n",
         "  Got: '", cron, "'", call. = FALSE)
  }
  names(parts) <- c("min", "hour", "dom", "mon", "dow")

  ranges <- list(min = 0:59, hour = 0:23, dom = 1:31, mon = 1:12, dow = 0:6)

  out <- lapply(names(parts), function(nm) {
    .cron_field_values(parts[[nm]], ranges[[nm]], nm)
  })
  stats::setNames(out, names(parts))
}


#' @noRd
.cron_field_values <- function(field, rng, nm) {
  if (field == "*") return(rng)

  # */N steps from the field minimum (correct for dom/mon whose min is 1).
  if (grepl("^\\*/[0-9]+$", field)) {
    n <- as.integer(sub("\\*/", "", field))
    if (is.na(n) || n <= 0L) {
      stop("Invalid step '/", n, "' in cron field '", nm, "'.", call. = FALSE)
    }
    return(rng[((rng - min(rng)) %% n) == 0L])
  }

  atoms <- strsplit(field, ",")[[1L]]
  vals  <- integer(0)
  for (a in atoms) {
    if (grepl("^[0-9]+-[0-9]+$", a)) {
      bounds <- as.integer(strsplit(a, "-")[[1L]])
      if (bounds[1L] > bounds[2L]) {
        stop("Descending range '", a, "' in cron field '", nm, "'.",
             call. = FALSE)
      }
      vals <- c(vals, seq(bounds[1L], bounds[2L]))
    } else if (grepl("^[0-9]+$", a)) {
      vals <- c(vals, as.integer(a))
    } else {
      stop("Invalid cron field value '", a, "' in field '", nm, "'.",
           call. = FALSE)
    }
  }

  bad <- setdiff(vals, rng)
  if (length(bad)) {
    stop("Cron field '", nm, "' values out of range: ",
         paste(bad, collapse = ", "), call. = FALSE)
  }
  sort(unique(vals))
}


# ------------------------------------------------------------------------------
# Internal: the tick function; reschedules itself via later::later().
# ------------------------------------------------------------------------------

#' @noRd
.schedule_tick <- function(id, fields, fn, tz) {
  now     <- as.POSIXlt(Sys.time(), tz = tz)
  delay_s <- 60 - now$sec           # align to the top of the next minute
  if (delay_s <= 0) delay_s <- 60

  later::later(function() {
    w <- .tw_state$watchers[[id]]
    if (is.null(w) || !identical(w$status, "active")) return(invisible(NULL))

    t   <- as.POSIXlt(Sys.time(), tz = tz)
    hit <- (t$min       %in% fields$min)  &&
      (t$hour      %in% fields$hour) &&
      (t$mday      %in% fields$dom)  &&
      ((t$mon + 1L) %in% fields$mon) &&   # POSIXlt mon is 0-based
      (t$wday      %in% fields$dow)

    if (isTRUE(hit)) {
      tryCatch(
        {
          fn()
          .tw_state$watchers[[id]]$n_fired <-
            (.tw_state$watchers[[id]]$n_fired %||% 0L) + 1L
          .tw_log(id, "FIRED", as.character(Sys.time()))
        },
        error = function(e) {
          .tw_log(id, paste0("SCHEDULE_ERROR:", conditionMessage(e)),
                  as.character(Sys.time()))
          warning("[orchrd] Schedule '", id, "' error: ",
                  conditionMessage(e), call. = FALSE)
        }
      )
    }

    .schedule_tick(id, fields, fn, tz)  # arm the next minute
  }, delay = delay_s)
}
