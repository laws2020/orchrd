# ==============================================================================
# tripwire: tests/testthat/test-gaps.R
# Test coverage for all 9 gaps
# ==============================================================================
# FIXES applied vs original:
#  1. .tw_state accessed via tripwire:::.tw_state (internal, not exported)
#  2. log_step("error") wrapped in suppressMessages() — cli_alert_danger
#     prints to stderr which testthat captures as unexpected output
#  3. GAP 9 tail test seeds under a unique id to avoid log pollution
#     from other tests running in the same session
#  4. tmp_dir() dirs cleaned up with on.exit() so they don't accumulate
#  5. GAP 1 uses suppressMessages() — unwatch_all() prints a message
# ==============================================================================

library(testthat)

# ── Internal state accessor (not exported — must use :::) ─────────────────────
tw_state <- function() tripwire:::.tw_state

# ── Helper: temp dir with automatic cleanup ───────────────────────────────────
tmp_dir <- function() {
  d <- tempfile("tw_test_")
  dir.create(d)
  # Schedule cleanup in the CALLING test frame
  parent <- parent.frame()
  do.call(
    on.exit,
    list(call("unlink", d, recursive = TRUE), add = TRUE),
    envir = parent
  )
  d
}


# ── GAP 1: .onUnload cleanup ──────────────────────────────────────────────────

test_that("GAP 1: unwatch_all() is safe to call with no watchers", {
  # First unwatch anything left from a previous test
  suppressMessages(unwatch_all())
  # Now call again on an empty registry — must not error
  expect_no_error(suppressMessages(unwatch_all()))
})


# ── GAP 3: throttle() ────────────────────────────────────────────────────────

test_that("GAP 3: throttle() suppresses subsequent firings within window", {
  d    <- tmp_dir()
  hits <- 0L

  id <- on_arrive(d, action = function(e, p) hits <<- hits + 1L)
  on.exit(suppressMessages(unwatch(id)), add = TRUE)

  throttle(id, ms = 500)

  watcher_test(id, silent = TRUE)          # fires  — hits == 1
  watcher_test(id, silent = TRUE)          # blocked — still 1

  expect_equal(hits, 1L)
})

test_that("GAP 3: throttle() allows firing after the window expires", {
  d    <- tmp_dir()
  hits <- 0L

  id <- on_arrive(d, action = function(e, p) hits <<- hits + 1L)
  on.exit(suppressMessages(unwatch(id)), add = TRUE)

  throttle(id, ms = 1)   # 1 ms window — expires almost immediately

  watcher_test(id, silent = TRUE)
  Sys.sleep(0.05)                          # ensure window has passed
  watcher_test(id, silent = TRUE)

  expect_equal(hits, 2L)
})


# ── GAP 4: on_schedule() ─────────────────────────────────────────────────────

test_that("GAP 4: on_schedule() registers a schedule watcher", {
  skip_if_not_installed("later")

  id <- on_schedule("* * * * *", action = ~ invisible(NULL))
  on.exit(suppressMessages(unwatch(id)), add = TRUE)

  expect_true(id %in% names(tw_state()$watchers))
  expect_equal(tw_state()$watchers[[id]]$type, "schedule")
})

test_that("GAP 4: on_schedule() rejects too few cron fields", {
  skip_if_not_installed("later")
  expect_error(on_schedule("* * * *",  action = ~ NULL), "5 fields")
})

test_that("GAP 4: on_schedule() rejects minute value out of range", {
  skip_if_not_installed("later")
  expect_error(on_schedule("60 * * * *", action = ~ NULL), "out of range")
})

test_that("GAP 4: schedule_test() fires action immediately", {
  skip_if_not_installed("later")

  fired <- FALSE
  id    <- on_schedule("0 3 * * *",
                       action = function() { fired <<- TRUE })
  on.exit(suppressMessages(unwatch(id)), add = TRUE)

  schedule_test(id)

  expect_true(fired)
})


# ── GAP 5: callback error isolation ──────────────────────────────────────────

test_that("GAP 5: throwing callback issues warning, does not crash watcher", {
  d  <- tmp_dir()
  id <- on_arrive(d, action = function(e, p) stop("boom"))
  on.exit(suppressMessages(unwatch(id)), add = TRUE)

  expect_warning(
    watcher_test(id, silent = TRUE),
    regexp = "boom"
  )

  # Watcher still alive after the error
  expect_true(id %in% names(tw_state()$watchers))
})

test_that("GAP 5: n_fired not incremented on callback error", {
  d  <- tmp_dir()
  id <- on_arrive(d, action = function(e, p) stop("boom"))
  on.exit(suppressMessages(unwatch(id)), add = TRUE)

  suppressWarnings(watcher_test(id, silent = TRUE))

  expect_equal(tw_state()$watchers[[id]]$n_fired, 0L)
})

test_that("GAP 5: n_fired incremented on successful callback", {
  d  <- tmp_dir()
  id <- on_arrive(d, action = function(e, p) invisible(NULL))
  on.exit(suppressMessages(unwatch(id)), add = TRUE)

  watcher_test(id, silent = TRUE)
  watcher_test(id, silent = TRUE)

  expect_equal(tw_state()$watchers[[id]]$n_fired, 2L)
})


# ── GAP 6: watcher_test() ────────────────────────────────────────────────────

test_that("GAP 6: watcher_test() fires callback with correct args", {
  d       <- tmp_dir()
  got_evt <- NULL
  got_pth <- NULL

  id <- on_arrive(d, action = function(e, p) {
    got_evt <<- e
    got_pth <<- p
  })
  on.exit(suppressMessages(unwatch(id)), add = TRUE)

  watcher_test(id, event = "modified", path = "/fake/file.csv", silent = TRUE)

  expect_equal(got_evt, "modified")
  expect_equal(got_pth, "/fake/file.csv")
})

test_that("GAP 6: watcher_test() errors on unknown id", {
  expect_error(watcher_test("nonexistent_id_xyz987"), "No watcher")
})

test_that("GAP 6: watcher_test() rejects schedule watcher", {
  skip_if_not_installed("later")

  id <- on_schedule("* * * * *", action = ~ NULL)
  on.exit(suppressMessages(unwatch(id)), add = TRUE)

  expect_error(watcher_test(id), "schedule watchers")
})


# ── GAP 7: get_log() retains .data list-column ───────────────────────────────

test_that("GAP 7: get_log() returns a data list-column", {
  log_config(reset = TRUE)
  log_step("test entry", .data = list(source = "cbn", rows = 42L))

  df <- get_log()

  expect_true("data" %in% names(df))
  expect_type(df$data, "list")
  expect_equal(df$data[[1]]$rows, 42L)
  expect_equal(df$data[[1]]$source, "cbn")
})

test_that("GAP 7: get_log(since=) filters by timestamp", {
  log_config(reset = TRUE)
  log_step("before")

  cutoff <- Sys.time()
  Sys.sleep(0.05)          # ensure the second entry is strictly after cutoff

  log_step("after")

  df <- get_log(since = cutoff)

  expect_equal(nrow(df), 1L)
  expect_equal(df$message, "after")
})

test_that("GAP 7: get_log(level=) filters by level", {
  log_config(reset = TRUE)

  log_step("info msg",  level = "info")
  suppressWarnings(log_step("warn msg",  level = "warn"))
  # level="error" uses cli_alert_danger — suppress its stderr output
  suppressMessages(suppressWarnings(
    log_step("error msg", level = "error")
  ))

  df <- get_log(level = c("warn", "error"))

  expect_equal(nrow(df), 2L)
  expect_true(all(df$level %in% c("warn", "error")))
})


# ── GAP 8: DESCRIPTION ───────────────────────────────────────────────────────

test_that("GAP 8: package does not list orchrd or openafrR as a dependency", {
  desc <- packageDescription("tripwire")
  deps <- paste(
    desc$Imports  %||% "",
    desc$Suggests %||% "",
    desc$Depends  %||% "",
    sep = "\n"
  )

  expect_false(grepl("orchrd",   deps, ignore.case = TRUE))
  expect_false(grepl("openafrR", deps, ignore.case = TRUE))
})


# ── GAP 9: watcher_log(since=) ───────────────────────────────────────────────

test_that("GAP 9: watcher_log(since=) filters by time", {
  d  <- tmp_dir()
  id <- on_arrive(d, action = function(e, p) invisible(NULL))
  on.exit(suppressMessages(unwatch(id)), add = TRUE)

  # Inject a stale entry (2 hours ago)
  old_entry <- list(
    id        = id,
    event     = "created",
    path      = "/old_file.csv",
    timestamp = Sys.time() - 7200
  )
  tw_state()$log <- c(tw_state()$log, list(old_entry))

  # Inject a fresh entry
  new_entry <- list(
    id        = id,
    event     = "created",
    path      = "/new_file.csv",
    timestamp = Sys.time()
  )
  tw_state()$log <- c(tw_state()$log, list(new_entry))

  df <- watcher_log(id, since = Sys.time() - 3600)

  expect_true(all(df$path != "/old_file.csv"))
  expect_true(any(df$path == "/new_file.csv"))
})

test_that("GAP 9: watcher_log() default tail n= unchanged", {
  # Seed 25 entries under a unique id so other tests don't inflate the count
  seed_id <- paste0("tw_gap9_seed_", as.integer(Sys.time()))

  for (i in seq_len(25)) {
    tw_state()$log <- c(tw_state()$log, list(
      list(
        id        = seed_id,
        event     = "created",
        path      = paste0("/f", i, ".csv"),
        timestamp = Sys.time()
      )
    ))
  }

  df <- watcher_log(seed_id, n = 5)
  expect_equal(nrow(df), 5L)
})
