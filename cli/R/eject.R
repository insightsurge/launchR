# Copies launchR's CI into the package, so nothing depends on launchR any more. The short caller files keep their
# triggers and settings; only the line that names launchR changes.
eject_copy <- function(from, to) {
  for (file in list.files(from, recursive = TRUE, all.files = TRUE, no.. = TRUE)) {
    target <- file.path(to, file)
    dir.create(dirname(target), recursive = TRUE, showWarnings = FALSE)
    file.copy(file.path(from, file), target, overwrite = TRUE)
  }
}

remove_launchr_fetch <- function(text) {
  gsub("(?s)      # launchr-fetch-start\n.*?      # launchr-fetch-end\n", "", text, perl = TRUE)
}

cmd_eject <- function(args) {
  workflows <- file.path(".github", "workflows")
  if (!dir.exists(workflows)) {
    message("Run this from the package's folder: there's no .github/workflows here.")
    return(1L)
  }
  eject_copy(kit_path(".github", "actions"), file.path(".launchr", ".github", "actions"))
  eject_copy(kit_path(".github", "scripts"), file.path(".launchr", ".github", "scripts"))
  eject_copy(kit_path("quality-gate"), file.path(".launchr", "quality-gate"))
  eject_copy(kit_path("cli"), file.path(".launchr", "cli"))
  eject_copy(kit_path("lists"), file.path(".launchr", "lists"))
  file.copy(kit_path(".github", "pr-report.json"), file.path(".launchr", ".github", "pr-report.json"), overwrite = TRUE)
  pattern <- "uses: insightsurge/launchR/\\.github/workflows/([a-z-]+)\\.yaml@v[0-9.]+"
  changed <- character()
  for (file in list.files(workflows, pattern = "[.]yaml$", full.names = TRUE)) {
    text <- read_text(file)
    if (!grepl(pattern, text)) next
    check <- sub(pattern, "\\1", regmatches(text, regexpr(pattern, text)))
    write_text(remove_launchr_fetch(read_text(kit_path(".github", "workflows", paste0(check, ".yaml")))),
      file.path(workflows, sprintf("launchr-%s.yaml", check)))
    write_text(gsub(pattern, sprintf("uses: ./.github/workflows/launchr-%s.yaml", check), text), file)
    changed <- c(changed, basename(file))
  }
  # The workflows README's local run downloads launchR's gate; point it at the package's own copy instead.
  readme <- file.path(workflows, "README.md")
  if (file.exists(readme)) {
    write_text(sub(paste0("gate <- tempfile\\(fileext = \"\\.R\"\\)\ndownload\\.file\\(\"https://raw\\.githubusercontent\\.com/",
      "insightsurge/launchR/v[0-9.]+/quality-gate/quality-gate\\.R\", gate\\)\n"),
      "gate <- \".launchr/quality-gate/quality-gate.R\"\n", read_text(readme)), readme)
  }
  ignore <- ".Rbuildignore"
  if (file.exists(ignore) && !any(grepl("\\.launchr", readLines(ignore, warn = FALSE)))) {
    # write_text keeps the file's \n line endings; write() would add \r\n on Windows.
    write_text(paste0(sub("\n*$", "\n", read_text(ignore)), "^\\.launchr$\n"), ignore)
  }
  cat("Copied launchR's CI into .launchr/ and .github/workflows/. Files now independent of launchR:\n")
  cat(paste0("  ", changed), sep = "\n")
  0L
}
