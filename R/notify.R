# =============================================================================
# R/notify.R
# Pipeline completion notifications.
# A pipeline that runs unattended must signal when it is done.
#
# WINDOWS SAFETY: matches run_cmd.R / artifact.R - plain paste0() inside
# stop(), never cli::format_error() with named vectors. All cli templates
# interpolate resolved text via {.val ...} data slots so literal braces in a
# message can never be re-evaluated as glue.
# ASCII-only throughout: no smart quotes, em-dashes, arrows, or emoji.
#
# Public API:
#   notify(result, ...)  - signal completion of an orchrd_pipeline
# =============================================================================

#' Send a notification when a pipeline finishes
#'
#' Sends a message when an `orchrd_pipeline` result is passed to it.
#' Designed to be piped after [pipe_exec()] so unattended pipelines signal
#' completion without manual checking.
#'
#' Supports desktop notifications (all platforms), Slack webhooks, Microsoft
#' Teams webhooks, and plain console output. More than one channel may be
#' supplied to `via`; all channels except `"console"` require a webhook or
#' the relevant system tool.
#'
#' Message strings support glue-style interpolation. Available variables:
#' - `{ok}` - TRUE/FALSE
#' - `{n_steps}` - total number of steps
#' - `{n_failed}` - number of failed steps
#' - `{elapsed}` - total elapsed seconds across all steps
#' - `{failed_steps}` - comma-separated names of failed steps
#'
#' @param result An `orchrd_pipeline` object from [pipe_exec()].
#' @param on_success Character. Message to send on full success.
#' @param on_failure Character. Message to send when any step failed.
#' @param via Character vector. One or more of `"console"` (default),
#'   `"desktop"`, `"slack"`, `"teams"`.
#' @param webhook An `orchrd_secret` or character. Webhook URL for Slack or
#'   Teams. Use [secret()] to pass this safely.
#' @param title Character. Notification title. Default `"orchrd pipeline"`.
#' @param timeout Numeric. Seconds before a webhook request is abandoned.
#'   Default `10`.
#' @param ... Reserved for future channel-specific arguments.
#'
#' @return The `result` object, invisibly, so `notify()` can end a chain.
#'
#' @export
notify <- function(
    result,
    on_success = "Pipeline complete: {n_steps} steps, {elapsed}s",
    on_failure = "Pipeline failed. Step(s) with errors: {failed_steps}",
    via        = "console",
    webhook    = NULL,
    title      = "orchrd pipeline",
    timeout    = 10,
    ...
) {
  if (!inherits(result, "orchrd_pipeline")) {
    stop(
      "notify() requires an orchrd_pipeline object from pipe_exec().",
      call. = FALSE
    )
  }

  valid <- c("console", "desktop", "slack", "teams")
  via   <- unique(via)
  bad   <- setdiff(via, valid)
  if (length(bad) > 0L) {
    stop(
      paste0("Unknown notification channel(s): ", paste(bad, collapse = ", "),
             ". Valid: ", paste(valid, collapse = ", ")),
      call. = FALSE
    )
  }

  # ---- Build interpolation context (column-guarded) --------------------------
  steps   <- result$steps
  ok       <- isTRUE(result$ok)
  n_steps  <- if (is.data.frame(steps)) nrow(steps) else 0L

  status_col  <- if (is.data.frame(steps) && !is.null(steps$status)) {
    steps$status
  } else character(0)
  elapsed_col <- if (is.data.frame(steps) && !is.null(steps$elapsed_sec)) {
    steps$elapsed_sec
  } else numeric(0)
  step_col    <- if (is.data.frame(steps) && !is.null(steps$step)) {
    steps$step
  } else character(0)

  is_err       <- status_col == "error"
  n_failed     <- sum(is_err, na.rm = TRUE)
  elapsed      <- round(sum(elapsed_col, na.rm = TRUE), 1)
  failed_steps <- paste(step_col[is_err], collapse = ", ")
  if (!nzchar(failed_steps)) failed_steps <- "none"

  msg_template <- if (ok) on_success else on_failure
  msg <- tryCatch(
    as.character(glue::glue(msg_template, .envir = environment())),
    error = function(e) msg_template
  )

  # ---- Dispatch to every requested channel -----------------------------------
  for (channel in via) {
    switch(channel,
           console = .notify_console(msg, ok, title),
           desktop = .notify_desktop(msg, ok, title),
           slack   = .notify_slack(msg, ok, title, webhook, timeout),
           teams   = .notify_teams(msg, ok, title, webhook, timeout)
    )
  }

  invisible(result)
}

# ---- Channel implementations ------------------------------------------------

#' @noRd
.notify_console <- function(msg, ok, title) {
  # Pass title/msg as data slots so braces in either cannot re-interpolate.
  if (ok) {
    cli::cli_alert_success("{.val {title}}: {.val {msg}}")
  } else {
    cli::cli_alert_danger("{.val {title}}: {.val {msg}}")
  }
}

# Strip characters that would break shell/AppleScript/PowerShell string
# literals. Deterministic and lossless enough for a notification body.
#' @noRd
.notify_sanitize <- function(x) {
  x <- gsub('"', "'", x, fixed = TRUE)
  x <- gsub("[\r\n]+", " ", x)
  x
}

#' @noRd
.notify_desktop <- function(msg, ok, title) {
  sysname <- Sys.info()[["sysname"]]
  s_msg   <- .notify_sanitize(msg)
  s_title <- .notify_sanitize(title)

  sent <- tryCatch({
    if (sysname == "Darwin") {
      if (!nzchar(Sys.which("osascript"))) stop("osascript not found")
      script <- sprintf('display notification "%s" with title "%s"',
                        s_msg, s_title)
      system2("osascript", c("-e", shQuote(script)),
              stdout = FALSE, stderr = FALSE)
      TRUE

    } else if (sysname == "Windows") {
      # Prefer Windows PowerShell (always present), fall back to pwsh.
      ps_exe <- if (nzchar(Sys.which("powershell"))) "powershell" else "pwsh"
      if (!nzchar(Sys.which(ps_exe))) stop("no PowerShell on PATH")
      # Non-blocking balloon tip (NotifyIcon) instead of a modal MessageBox.
      ps_cmd <- sprintf(paste0(
        "Add-Type -AssemblyName System.Windows.Forms; ",
        "$n = New-Object System.Windows.Forms.NotifyIcon; ",
        "$n.Icon = [System.Drawing.SystemIcons]::Information; ",
        "$n.Visible = $true; ",
        "$n.ShowBalloonTip(5000, '%s', '%s', ",
        "[System.Windows.Forms.ToolTipIcon]::%s)"),
        s_title, s_msg, if (ok) "Info" else "Error")
      system2(ps_exe, c("-NoProfile", "-Command", ps_cmd),
              stdout = FALSE, stderr = FALSE)
      TRUE

    } else {
      if (!nzchar(Sys.which("notify-send"))) stop("notify-send not found")
      icon <- if (ok) "dialog-information" else "dialog-error"
      system2("notify-send",
              c(shQuote(s_title), shQuote(s_msg), "-i", icon),
              stdout = FALSE, stderr = FALSE)
      TRUE
    }
  }, error = function(e) {
    cli::cli_warn("Desktop notification failed: {.val {conditionMessage(e)}}")
    FALSE
  })

  if (isTRUE(sent)) {
    cli::cli_inform(c("i" = "Desktop notification sent."))
  } else {
    .notify_console(msg, ok, title)   # always fall back to console
  }
  invisible(sent)
}

# Shared webhook POST with timeout + retry; returns TRUE on 2xx.
#' @noRd
.notify_post <- function(url, payload, timeout, channel) {
  tryCatch({
    httr2::request(url) |>
      httr2::req_body_json(payload) |>
      httr2::req_timeout(timeout) |>
      httr2::req_retry(max_tries = 3) |>
      httr2::req_error(is_error = function(resp) FALSE) |>
      httr2::req_perform() -> resp
    code <- httr2::resp_status(resp)
    if (code >= 200 && code < 300) {
      cli::cli_inform(c("i" = paste0(channel, " notification sent.")))
      TRUE
    } else {
      cli::cli_warn(paste0(channel, " notification failed: HTTP {.val {code}}"))
      FALSE
    }
  }, error = function(e) {
    cli::cli_warn(paste0(channel,
                         " notification failed: {.val {conditionMessage(e)}}"))
    FALSE
  })
}

#' @noRd
.notify_slack <- function(msg, ok, title, webhook, timeout) {
  if (is.null(webhook)) {
    cli::cli_warn(c(
      "No webhook supplied for Slack notification.",
      "i" = 'Pass: notify(..., webhook = secret("SLACK_WEBHOOK_URL"))'
    ))
    return(invisible(FALSE))
  }
  if (!requireNamespace("httr2", quietly = TRUE)) {
    stop("httr2 is required for Slack notifications: install.packages('httr2')",
         call. = FALSE)
  }

  url   <- if (inherits(webhook, "orchrd_secret")) reveal(webhook) else webhook
  color <- if (ok) "#0F6E56" else "#993C1D"
  emoji <- if (ok) ":white_check_mark:" else ":x:"

  payload <- list(
    text        = paste0(emoji, " *", title, "*"),
    attachments = list(list(
      color  = color,
      text   = msg,
      footer = paste0("orchrd | ", format(Sys.time(), "%Y-%m-%d %H:%M:%S"))
    ))
  )

  ok_sent <- .notify_post(url, payload, timeout, "Slack")
  if (!ok_sent) .notify_console(msg, ok, title)
  invisible(ok_sent)
}

#' @noRd
.notify_teams <- function(msg, ok, title, webhook, timeout) {
  if (is.null(webhook)) {
    cli::cli_warn(c(
      "No webhook supplied for Teams notification.",
      "i" = 'Pass: notify(..., webhook = secret("TEAMS_WEBHOOK_URL"))'
    ))
    return(invisible(FALSE))
  }
  if (!requireNamespace("httr2", quietly = TRUE)) {
    stop("httr2 is required for Teams notifications: install.packages('httr2')",
         call. = FALSE)
  }

  url   <- if (inherits(webhook, "orchrd_secret")) reveal(webhook) else webhook
  # ASCII status marker instead of emoji.
  marker <- if (ok) "[OK]" else "[FAILED]"

  payload <- list(
    `@type`    = "MessageCard",
    `@context` = "http://schema.org/extensions",
    summary    = title,
    themeColor = if (ok) "0F6E56" else "993C1D",
    title      = paste0(marker, " ", title),
    text       = msg,
    sections   = list(list(
      activitySubtitle = format(Sys.time(), "%Y-%m-%d %H:%M:%S"),
      activityText     = paste0("Status: ", if (ok) "Good" else "Attention")
    ))
  )

  ok_sent <- .notify_post(url, payload, timeout, "Teams")
  if (!ok_sent) .notify_console(msg, ok, title)
  invisible(ok_sent)
}
