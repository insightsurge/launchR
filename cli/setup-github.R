# The one R line behind the site's "with R" route: fetches the kit at a version, then sets up GitHub for the package in
# the current folder. Needs gh signed in.
local({
  version <- "0.0.1"
  url <- sprintf("https://github.com/insightsurge/r-pkg-kit/archive/refs/tags/v%s.tar.gz", version)
  folder <- tempfile("r-pkg-kit")
  dir.create(folder)
  archive <- file.path(folder, "kit.tar.gz")
  utils::download.file(url, archive, quiet = TRUE)
  utils::untar(archive, exdir = folder)
  root <- list.dirs(folder, recursive = FALSE)[1]
  options(kit.root = root)
  scripts <- list.files(file.path(root, "cli", "R"), pattern = "[.]R$", full.names = TRUE)
  for (script in scripts) sys.source(script, envir = globalenv())
  invisible(cmd_github(character()))
})
