# =============================================================================
# R/run_script.R
# Run any script file. One interface for R, Python, PowerShell, bash.
#
# WINDOWS SAFETY: matches run_cmd.R / artifact.R - plain paste0() inside
# stop(), never cli::format_error() with named vectors.
# ASCII-only: no smart quotes, em-dashes, arrows, or emoji.
# All cli::* templates interpolate paths/interpreter names via {.file}/{.code}
# data slots so literal braces in values cannot be re-evaluated as glue.
#
# Public API:
#   run_script(path, ...) - run an R / Python / PowerShell / bash / etc. script
# =============================================================================

#' Run an external script file
#'
#' A single function that runs any script type - R, Python, PowerShell,
#' bash - by detecting the file extension and invoking the right interpreter
#' automatically. Returns the same structured `orchrd_result` as [run_cmd()].
#'
#' You never need to remember whether it is `Rscript --vanilla`,
#' `pwsh -NoProfile -NonInteractive -File`, or `python3`. One call handles
#' all of them.
#'
#' **Interpreter resolution order:**
#' 1. The `interpreter` argument if explicitly supplied.
#' 2. File extension: `.R`/`.Rmd` to `Rscript`, `.py` to `python3`,
#'    `.ps1` to `pwsh`, `.qmd` to `quarto`, `.sh` to `bash`, `.js` to `node`.
#' 3. Shebang line (`#!`) at the top of the file. Interpreter flags on the
#'    shebang (e.g. `#!/usr/bin/env python3 -u`) are preserved as leading args.
#'
#' @param path Character. Path to the script file.
#' @param args Character vector. Arguments passed to the script.
#' @param interpreter Character. Override the detected interpreter,
#'   e.g. `"python3"`, `"pwsh"`, `"Rscript"`.
#' @param dir Character. Working directory. Defaults to the script's
#'   parent directory - almost always the right choice.
#' @param env Named character vector. Extra environment variables.
#' @param timeout Numeric. Seconds before kill (default `300`).
#'   Scripts take longer than single commands.
#' @param echo Logical. Stream output to the R console (default `TRUE`
#'   for scripts - you usually want to see progress).
#' @param error_ok Logical. Return result even on failure (default `FALSE`).
#'
#' @return An `orchrd_result` object. See [run_cmd()] for field details.
#'
#' @seealso [run_cmd()] to run commands rather than script files.
#'
#' @export
#' @examples
#' \dontrun{
#' run_script("scripts/build_registry.R")
#' run_script("inst/ps/fetch.ps1", args = c("-Source", "cbn"))
#' run_script("etl/clean.py", args = c("--year", "2024"))
#' run_script("deploy.sh", env = c(ENV = "production"))
#' run_script("pipeline", interpreter = "python3")
#' run_script("report.qmd")
#' }
run_script <- function(
    path,
    args        = character(),
    interpreter = NULL,
    dir         = NULL,
    env         = character(),
    timeout     = 300,
    echo        = TRUE,
    error_ok    = FALSE
) {
  # -- validate path ---------------------------------------------------------
  if (!is.character(path) || length(path) != 1L || is.na(path) ||
      !nzchar(trimws(path))) {
    stop("path must be a single non-empty character value.", call. = FALSE)
  }
  path <- tryCatch(
    normalizePath(path, mustWork = TRUE),
    error = function(e) {
      stop(paste0("Script file not found: ", path), call. = FALSE)
    }
  )
  if (is.null(dir)) dir <- dirname(path)

  # -- resolve interpreter (+ any shebang interpreter flags) -----------------
  if (!is.null(interpreter)) {
    interp       <- interpreter
    interp_flags <- character()
  } else {
    detected     <- .detect_interpreter(path)
    interp       <- detected$interp
    interp_flags <- detected$flags
  }

  exe <- .which_exe(interp)
  if (!nzchar(exe)) {
    stop(
      paste0(
        "Interpreter not found: ", interp, "\n",
        "  ", .interpreter_hint(interp)
      ),
      call. = FALSE
    )
  }

  cli::cli_inform(c(
    ">" = "Running {.file {basename(path)}} via {.code {interp}}"
  ))

  run_cmd(
    cmd      = interp,
    args     = c(interp_flags, .interpreter_args(interp, path, args)),
    dir      = dir,
    env      = env,
    timeout  = timeout,
    echo     = echo,
    error_ok = error_ok
  )
}

# ---- Internal helpers -------------------------------------------------------

#' @noRd
.detect_interpreter <- function(path) {
  ext <- tolower(tools::file_ext(path))

  interp <- switch(ext,
                   r    = "Rscript",
                   rmd  = "Rscript",
                   qmd  = "quarto",
                   py   = .python_cmd(),
                   ps1  = "pwsh",
                   sh   = "bash",
                   bash = "bash",
                   zsh  = "zsh",
                   fish = "fish",
                   js   = "node",
                   mjs  = "node",
                   ts   = "ts-node",
                   NULL
  )

  if (!is.null(interp)) return(list(interp = interp, flags = character()))

  # Fall back to the shebang line.
  first_line <- tryCatch(
    readLines(path, n = 1L, warn = FALSE),
    error = function(e) character()
  )
  if (length(first_line) && grepl("^#!", first_line)) {
    shebang <- sub("^#!/usr/bin/env\\s+", "", first_line)
    shebang <- sub("^#!", "", shebang)
    tokens  <- strsplit(trimws(shebang), "\\s+")[[1]]
    tokens  <- tokens[nzchar(tokens)]
    if (length(tokens)) {
      exe <- basename(tokens[1])            # /usr/bin/python3 -> python3
      return(list(interp = exe, flags = tokens[-1]))
    }
  }

  stop(
    paste0(
      "Cannot detect interpreter for: ", path, "\n",
      '  Use the interpreter argument, e.g. ',
      'run_script(path, interpreter = "python3")'
    ),
    call. = FALSE
  )
}

#' @noRd
.python_cmd <- function() {
  if (nzchar(.which_exe("python3"))) "python3" else "python"
}

#' @noRd
.interpreter_args <- function(interp, path, user_args) {
  base <- switch(interp,
                 Rscript = c("--vanilla", path),
                 pwsh    = c("-NoProfile", "-NonInteractive", "-File", path),
                 quarto  = c("render", path),
                 c(path)
  )
  c(base, user_args)
}

#' @noRd
.interpreter_hint <- function(interp) {
  switch(interp,
         pwsh    = "Install PowerShell 7+: https://aka.ms/powershell",
         python3 = "Install Python 3: https://python.org",
         python  = "Install Python 3: https://python.org",
         quarto  = "Install Quarto: https://quarto.org",
         node    = "Install Node.js: https://nodejs.org",
         Rscript = "Install R: https://www.r-project.org",
         `ts-node` = "Install ts-node: npm install -g ts-node",
         paste0("Install ", interp, " and ensure it is on your PATH")
  )
}
