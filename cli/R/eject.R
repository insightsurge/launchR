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
  file.copy(kit_path(".github", "gitleaks.toml"), file.path(".launchr", ".github", "gitleaks.toml"), overwrite = TRUE)
  # A caller names launchR's check by a tag (@v0.0.12) or by a commit (@ and 40 letters or digits, often followed by a
  # comment with the version). One already ejected names its local copy, which a second eject refreshes.
  remote <- "uses: insightsurge/launchR/\\.github/workflows/([a-z-]+)\\.yaml@(v[0-9][0-9.]*|[0-9a-f]{40})([ \t]+#[^\n]*)?"
  local <- "uses: \\./\\.github/workflows/launchr-([a-z-]+)\\.yaml"
  changed <- character()
  for (file in list.files(workflows, pattern = "[.]yaml$", full.names = TRUE)) {
    text <- read_text(file)
    pattern <- if (grepl(remote, text)) remote else if (grepl(local, text)) local else next
    check <- sub(pattern, "\\1", regmatches(text, regexpr(pattern, text)))
    write_text(remove_launchr_fetch(read_text(kit_path(".github", "workflows", paste0(check, ".yaml")))),
      file.path(workflows, sprintf("launchr-%s.yaml", check)))
    if (pattern == remote) write_text(sub(remote, sprintf("uses: ./.github/workflows/launchr-%s.yaml", check), text), file)
    changed <- c(changed, basename(file))
  }
  # The workflows README's local run downloads launchR's gate; point it at the package's own copy instead. Its opening
  # paragraph and its sections on updates and leaving describe launchR's checks, so they now say where the checks are.
  readme <- file.path(workflows, "README.md")
  if (file.exists(readme)) {
    text <- sub(paste0("gate <- tempfile\\(fileext = \"\\.R\"\\)\ndownload\\.file\\(\"https://raw\\.githubusercontent\\.com/",
      "insightsurge/launchR/v[0-9.]+/quality-gate/quality-gate\\.R\", gate\\)\n"),
      "gate <- \".launchr/quality-gate/quality-gate.R\"\n", read_text(readme))
    text <- sub("The check itself lives in the launchR repository and this file only says when\nand where it runs, so it stays short.",
      "The checks' own code is in this repository (the `launchr-*.yaml` files here and `.launchr/`);\nthe other files only say when and where each runs, so they stay short.", text, fixed = TRUE)
    text <- sub("(?s)## Updates\n.*$", paste0(
      "## Updates\n\nThe checks were copied from launchR and no longer change by themselves. To take a newer launchR\n",
      "release, run `eject` again from the package's folder with that release: it refreshes the `launchr-*.yaml` files\nand `.launchr/`.\n"), text, perl = TRUE)
    write_text(text, readme)
  }
  # No caller names launchR any more, so Dependabot has no launchR group or rule to keep.
  dependabot <- file.path(".github", "dependabot.yml")
  if (file.exists(dependabot)) {
    text <- read_text(dependabot)
    text <- sub("    groups:\n      launchr:\n        patterns: \\[\"insightsurge/launchR\\*\"\\]\n", "", text)
    text <- sub("    ignore:\n      # launchR patch releases arrive with the next minor release.\n      - dependency-name: \"insightsurge/launchR\\*\"\n        update-types: \\[\"version-update:semver-patch\"\\]\n", "", text)
    write_text(text, dependabot)
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
