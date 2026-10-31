# Copies the kit's CI into the package, so nothing depends on the kit any more. The short caller files keep their
# triggers and settings; only the line that names the kit changes.
eject_copy <- function(from, to) {
  for (file in list.files(from, recursive = TRUE, all.files = TRUE, no.. = TRUE)) {
    target <- file.path(to, file)
    dir.create(dirname(target), recursive = TRUE, showWarnings = FALSE)
    file.copy(file.path(from, file), target, overwrite = TRUE)
  }
}

remove_kit_fetch <- function(text) {
  gsub("(?s)      # kit-fetch-start\n.*?      # kit-fetch-end\n", "", text, perl = TRUE)
}

cmd_eject <- function(args) {
  workflows <- file.path(".github", "workflows")
  if (!dir.exists(workflows)) {
    message("Run this from the package's folder: there's no .github/workflows here.")
    return(1L)
  }
  eject_copy(kit_path(".github", "actions"), file.path(".kit", ".github", "actions"))
  eject_copy(kit_path(".github", "scripts"), file.path(".kit", ".github", "scripts"))
  eject_copy(kit_path("quality-gate"), file.path(".kit", "quality-gate"))
  eject_copy(kit_path("cli"), file.path(".kit", "cli"))
  eject_copy(kit_path("lists"), file.path(".kit", "lists"))
  file.copy(kit_path(".github", "pr-report.json"), file.path(".kit", ".github", "pr-report.json"), overwrite = TRUE)
  pattern <- "uses: insightsurge/r-pkg-kit/\\.github/workflows/([a-z-]+)\\.yaml@v[0-9.]+"
  changed <- character()
  for (file in list.files(workflows, pattern = "[.]yaml$", full.names = TRUE)) {
    text <- read_text(file)
    if (!grepl(pattern, text)) next
    check <- sub(pattern, "\\1", regmatches(text, regexpr(pattern, text)))
    write_text(remove_kit_fetch(read_text(kit_path(".github", "workflows", paste0(check, ".yaml")))),
      file.path(workflows, sprintf("kit-%s-full.yaml", check)))
    write_text(gsub(pattern, sprintf("uses: ./.github/workflows/kit-%s-full.yaml", check), text), file)
    changed <- c(changed, basename(file))
  }
  ignore <- ".Rbuildignore"
  if (file.exists(ignore) && !any(grepl("\\.kit", readLines(ignore)))) write("^\\.kit$", ignore, append = TRUE)
  cat("Copied the kit's CI into .kit/ and .github/workflows/. Files now independent of the kit:\n")
  cat(paste0("  ", changed), sep = "\n")
  0L
}
