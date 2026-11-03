# The optional R line on the site's next-steps page: fetches launchR at a version, then sets up GitHub for the package in
# the current folder. Needs gh signed in. Asks before it changes anything; add --yes to skip the question.
local({
  version <- "0.0.9"
  url <- Sys.getenv("KIT_ARCHIVE_URL", sprintf("https://github.com/insightsurge/launchR/archive/refs/tags/v%s.tar.gz", version))
  folder <- tempfile("launchR")
  dir.create(folder)
  archive <- file.path(folder, "launchR.tar.gz")
  utils::download.file(url, archive, quiet = TRUE, mode = "wb")
  utils::untar(archive, exdir = folder)
  root <- list.dirs(folder, recursive = FALSE)[1]
  options(kit.root = root)
  scripts <- list.files(file.path(root, "cli", "R"), pattern = "[.]R$", full.names = TRUE)
  for (script in scripts) sys.source(script, envir = globalenv())
  invisible(cmd_github(commandArgs(trailingOnly = TRUE)))
})
