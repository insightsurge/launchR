# Turns choices into files. site/src/form/engine.js follows the same steps, and tests/compare-routes.sh compares them.
placeholder_values <- function(choices) {
  checks <- read_list("checks.tsv")
  has_owner <- nzchar(choices$owner)
  public <- choices$visibility == "public"
  site_url <- kit_setting("site_url")
  owner <- if (has_owner) choices$owner else "your-github-name"
  author <- paste(choices$given, choices$family)
  frontend <- "frontend" %in% choices$parts
  repository <- sprintf("https://github.com/%s/%s", owner, choices$package)
  site <- sprintf("https://%s.github.io/%s", owner, choices$package)
  urls <- c(if ("website" %in% choices$parts) paste0(site, "/"), repository)
  values <- list(
    package = choices$package,
    title = choices$title,
    description = paste0(choices$title, "."),
    author = author,
    given = choices$given,
    family = choices$family,
    email = choices$email,
    owner = owner,
    owner_or_you = owner,
    year = choices$year,
    kit_version = kit_setting("kit_version"),
    branches = choices$branches,
    url_line = if (has_owner) paste0("URL: ", paste(urls, collapse = ", ")) else "",
    man_seealso = if (has_owner) man_seealso(urls, repository) else "",
    pkgdown_url_line = if (has_owner) paste0("url: ", site, "/") else "",
    bugreports_line = if (has_owner) sprintf("BugReports: https://github.com/%s/%s/issues", owner, choices$package) else "",
    chromote_line = if (frontend) "    chromote," else "",
    target_line = if (choices$release == "internal") "Config/quality-gate/target: internal" else "",
    credit_badge = if (public) sprintf("[![Set up with launchR](https://img.shields.io/badge/set%%20up%%20with-launchR-f6ab85)](%s)\n", site_url) else "",
    credit_line = if (public) sprintf("\nSet up with [launchR](%s).", site_url) else "",
    js_css_tests = if (frontend) "true" else "false"
  )
  for (i in seq_len(nrow(checks))) {
    key <- checks$key[i]
    check <- choices$checks[[key]]
    for (event in c("pr", "push", "weekly", "manual")) {
      values[[sprintf("c_%s_%s", key, event)]] <- if (event %in% check$events) "" else "# "
    }
    values[[paste0("cron_", key)]] <- check$cron
    default <- checks[[paste0("platforms_", choices$visibility)]][i]
    values[[paste0("platforms_", key)]] <- if (is.null(check$platforms)) default else check$platforms
  }
  values
}

# The help page's links, as roxygen2 writes them from URL and BugReports.
man_seealso <- function(urls, repository) {
  paste(c(
    "\\seealso{", "Useful links:", "\\itemize{",
    sprintf("  \\item \\url{%s}", urls),
    sprintf("  \\item Report bugs at \\url{%s/issues}", repository),
    "}", "", "}"
  ), collapse = "\n")
}

render_text <- function(text, values) {
  lines <- strsplit(text, "\n", fixed = TRUE)[[1]]
  ends_with_newline <- endsWith(text, "\n")
  empty <- names(values)[vapply(values, function(value) !nzchar(value), logical(1))]
  lines <- lines[!lines %in% sprintf("{{%s}}", empty)]
  text <- paste0(paste(lines, collapse = "\n"), if (ends_with_newline) "\n")
  for (key in names(values)) {
    text <- gsub(sprintf("{{%s}}", key), values[[key]], text, fixed = TRUE)
  }
  text
}

selected_files <- function(choices) {
  files <- read_list("files.tsv")
  checks <- read_list("checks.tsv")
  on_checks <- checks$check[vapply(checks$key, function(key) choices$checks[[key]]$on, logical(1))]
  keep <- files$part %in%
    choices$parts &
    (!nzchar(files$check) | files$check %in% on_checks) &
    (files$release == "any" | files$release == choices$release)
  files$path[keep]
}

# A website needs a GitHub owner for its address, so without one the part is left out.
settle_choices <- function(choices) {
  if (!nzchar(choices$owner)) choices$parts <- setdiff(choices$parts, "website")
  choices
}

build_package <- function(choices, out) {
  choices <- settle_choices(choices)
  values <- placeholder_values(choices)
  for (path in selected_files(choices)) {
    text <- render_text(read_text(kit_path("template", path)), values)
    write_text(text, file.path(out, render_text(path, values)))
  }
  invisible(out)
}
