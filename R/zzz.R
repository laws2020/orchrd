# ==============================================================================
# orchrd: R/zzz.R
# Session lifecycle - load, attach, detach, and unload hooks.
#
# WINDOWS SAFETY: ASCII-only throughout.
# This is the single canonical home for the package lifecycle hooks.
# Do not define .onLoad, .onAttach, .onUnload, or .onDetach elsewhere.
# ==============================================================================

# ------------------------------------------------------------------------------
# Namespace load hook
# ------------------------------------------------------------------------------

.onLoad <- function(libname, pkgname) {
  # C++ watcher state is static; nothing needs to be initialized at load time.
  invisible(NULL)
}

# ------------------------------------------------------------------------------
# Package attach hook
# ------------------------------------------------------------------------------

.onAttach <- function(libname, pkgname) {
  packageStartupMessage("[orchrd] orchrd loaded.")
}

# ------------------------------------------------------------------------------
# Package unload hook
# ------------------------------------------------------------------------------

.onUnload <- function(libpath) {
  .tw_cleanup_watchers()

  tryCatch(
    library.dynam.unload("orchrd", libpath),
    error = function(e) invisible(NULL)
  )

  invisible(NULL)
}

# ------------------------------------------------------------------------------
# Package detach hook
# ------------------------------------------------------------------------------

.onDetach <- function(libpath) {
  .tw_cleanup_watchers()
  invisible(NULL)
}
