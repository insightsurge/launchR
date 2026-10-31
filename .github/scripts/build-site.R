#!/usr/bin/env Rscript
# Builds the pkgdown site into site/ (see _pkgdown.yml): Rscript tools/build-site.R
#
# pkgdown renders every top-level Markdown file and has no way to leave one out, so CLAUDE.md and AGENTS.md
# (instructions for coding tools, not user docs) are moved aside for the build and always put back.

agent_files <- c("CLAUDE.md", "AGENTS.md")

# Renames `from` to `to`, stopping with a clear message if it fails.
move <- function(from, to) {
  checkmate::assert_file_exists(from)
  checkmate::assert_path_for_output(to)
  if (!file.rename(from, to)) {
    cli::cli_abort("Couldn't move {.path {from}} to {.path {to}}.")
  }
  invisible(to)
}

build_site <- function(install) {
  checkmate::assert_flag(install)
  if (!file.exists("_pkgdown.yml")) {
    cli::cli_abort("Run from the package root (no {.path _pkgdown.yml} in {.path {getwd()}}).")
  }
  present <- agent_files[file.exists(agent_files)]
  held <- paste0(".", present, ".hold")
  on.exit(
    for (i in seq_along(present)) {
      move(held[i], present[i])
    },
    add = TRUE
  )
  for (i in seq_along(present)) {
    move(present[i], held[i])
  }
  pkgdown::build_site(preview = FALSE, install = install, new_process = FALSE)
  invisible(TRUE)
}

build_site(install = TRUE)
