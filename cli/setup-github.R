# The one R line behind the site's "with R" route: fetches the kit at a version, then sets up GitHub for the package in
# the current folder. Needs gh signed in. Asks before it changes anything; add --yes to skip the question.
local({
  version <- "0.0.3"
  url <- Sys.getenv("KIT_ARCHIVE_URL", sprintf("https://github.com/insightsurge/launchR/archive/refs/tags/v%s.tar.gz", version))
  folder <- tempfile("launchR")
  dir.create(folder)
  archive <- file.path(folder, "kit.tar.gz")
  utils::download.file(url, archive, quiet = TRUE, mode = "wb")
  utils::untar(archive, exdir = folder)
  root <- list.dirs(folder, recursive = FALSE)[1]
  options(kit.root = root)
  scripts <- list.files(file.path(root, "cli", "R"), pattern = "[.]R$", full.names = TRUE)
  for (script in scripts) sys.source(script, envir = globalenv())
  invisible(cmd_github(commandArgs(trailingOnly = TRUE)))
})
