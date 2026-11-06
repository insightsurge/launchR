# Turns choices into files. site/src/form/engine.js follows the same steps, and tests/compare-routes.mjs compares them.
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
  # The spelling check splits a name at digits and dots (demoPkg2 is read as demoPkg), so the parts go in the word list.
  parts <- unique(strsplit(choices$package, "[^A-Za-z]+")[[1]])
  parts <- parts[nchar(parts) > 1 & parts != choices$package]
  values <- list(
    package = choices$package,
    name_words = if (length(parts) > 0) paste0(parts, "\n", collapse = "") else "",
    title = clean_title(choices$title),
    description = description_text(choices),
    author = author,
    given = choices$given,
    family = choices$family,
    email = if (nzchar(choices$email)) choices$email else kit_setting("placeholder_email"),
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
    license_line = if (choices$licence == "mit") "License: MIT + file LICENSE" else "License: file LICENSE",
    ci_report = if (isTRUE(choices$ci_report)) "true" else "false",
    credit_line = sprintf("\nSet up with [launchR](%s).", site_url)
  )
  # The oldest R supported: in DESCRIPTION, and in place of 4.1 in the default platforms.
  min_r <- if (nzchar(choices$min_r %||% "")) choices$min_r else kit_setting("min_r")
  # DESCRIPTION takes major.minor.0: R CMD check warns about any other patch level. CI runs the newest patch of it.
  values$min_r <- paste0(min_r, ".0")
  ci_on <- "ci" %in% choices$parts
  check_on <- function(key) ci_on && isTRUE(choices$checks[[key]]$on)
  on_rows <- which(vapply(checks$key, check_on, logical(1)))
  values$checks_table <- paste(
    sprintf("| `%s.yaml` | %s | %s |", checks$check[on_rows], checks$label[on_rows],
      vapply(checks$key[on_rows], function(key) when_text(choices$checks[[key]]), character(1))),
    collapse = "\n"
  )
  # Which checks run each kind of test file (the test_kinds column of lists/checks.tsv), for tests/README.md.
  kind_lists <- strsplit(checks$test_kinds, ",", fixed = TRUE)
  for (kind in unique(unlist(kind_lists))) {
    rows <- on_rows[vapply(kind_lists[on_rows], function(kinds) kind %in% kinds, logical(1))]
    values[[paste0("runs_", kind)]] <- if (length(rows) > 0) paste0("`", checks$check[rows], "`", collapse = ", ") else "none of the checks yet"
  }
  # .Renviron runs the extended tests locally when a check runs them in CI.
  values$extended_env <- if (any(vapply(c("full_tests", "coverage", "r_cmd_check_extended"), check_on, logical(1)))) "EXTENDED_TESTS=true" else "# EXTENDED_TESTS=true"
  # What the template's {{#has_...}} blocks ask. The paragraphs themselves are in the template.
  yes <- function(on) if (on) "yes" else ""
  values$has_skeleton <- yes("skeleton" %in% choices$parts)
  values$has_frontend <- yes(frontend)
  values$has_checks <- yes(length(on_rows) > 0)
  values$has_coverage <- yes(check_on("coverage"))
  values$has_full_tests <- yes(check_on("full_tests"))
  values$has_time_limit <- yes(check_on("r_cmd_check"))
  values$is_internal <- yes(choices$release == "internal")
  values$is_private <- yes(!public)
  values$is_mit <- yes(choices$licence == "mit")
  # README badges: the chosen ones whose needs are met, in lists/badges.tsv order.
  badges <- read_list("badges.tsv")
  keep <- badges$key %in% choices$badges & vapply(badges$needs, badge_offered, logical(1), choices = choices)
  lines <- badges$line[keep]
  for (from in c("{repository}", "{owner}", "{package}", "{site_url}")) {
    to <- switch(from, "{repository}" = repository, "{owner}" = owner, "{package}" = choices$package, "{site_url}" = site_url)
    lines <- gsub(from, to, lines, fixed = TRUE)
  }
  values$badges <- paste(lines, collapse = "\n")
  values$has_badges <- yes(length(lines) > 0)
  navbar <- read_list("navbar.tsv")
  for (side in c("left", "right")) {
    values[[paste0("navbar_", side)]] <- paste(navbar$name[navbar$side == side & navbar$key %in% choices$navbar], collapse = ", ")
  }
  forms <- read_list("forms.tsv")
  for (key in forms$key) values[[paste0("form_", key)]] <- yes(key %in% choices$forms)
  # DESCRIPTION records a choice of labels and of stage checklists, for the Set up this repository step (cli/R/github.R).
  labels <- chosen_labels(choices)
  github <- "github" %in% choices$parts
  values$labels_line <- if (github && length(labels) < nrow(read_list("labels.tsv"))) paste0("Config/launchR/labels: ", paste(labels, collapse = ", ")) else ""
  values$checklist_line <- checklist_line(choices, public)
  for (i in seq_len(nrow(checks))) {
    key <- checks$key[i]
    check <- choices$checks[[key]]
    for (event in c("pr", "push", "schedule", "manual")) {
      values[[sprintf("c_%s_%s", key, event)]] <- if (event %in% check$events) "" else "# "
    }
    values[[paste0("cron_", key)]] <- check$cron
    default <- checks[[paste0("platforms_", choices$visibility)]][i]
    # The default oldest R (4.1) in a check's systems becomes the chosen one, and R CMD check runs on it on Linux, as
    # the site's settings steps do. engine.js has the same.
    default <- gsub(paste0("/", kit_setting("min_r")), paste0("/", min_r), default, fixed = TRUE)
    if (key == "r_cmd_check" && min_r != kit_setting("min_r") && !grepl(paste0("ubuntu/", min_r), default, fixed = TRUE)) {
      default <- paste0(default, ", ubuntu/", min_r)
    }
    values[[paste0("platforms_", key)]] <- if (is.null(check$platforms)) default else check$platforms
  }
  values
}

# When a check runs, in words for the workflows README: "pull requests, pushes, Mondays at 05:17 UTC, by hand". The
# weekday names are in lists/settings.tsv, which site/src/form/engine.js reads too.
when_text <- function(check) {
  parts <- c(
    if ("pr" %in% check$events) "pull requests",
    if ("push" %in% check$events) "pushes",
    if ("schedule" %in% check$events) {
      cron <- strsplit(check$cron, " ", fixed = TRUE)[[1]]
      time <- sprintf("%02d:%02d UTC", as.integer(cron[2]), as.integer(cron[1]))
      weekdays <- strsplit(kit_setting("weekdays"), ", ", fixed = TRUE)[[1]]
      if (cron[5] == "*") paste("every day at", time) else paste(weekdays[as.integer(cron[5]) + 1], "at", time)
    },
    if ("manual" %in% check$events) "by hand"
  )
  paste(parts, collapse = ", ")
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

# Keeps or drops the template's blocks. A block is a line {{#name}} (kept when the value called name is not empty) or
# {{^name}} (kept when it is empty), the lines under it, and a line {{/name}}. Blocks nest. site/src/form/engine.js does
# the same.
apply_blocks <- function(text, values) {
  keep <- TRUE
  out <- character()
  for (line in strsplit(text, "\n", fixed = TRUE)[[1]]) {
    open <- regmatches(line, regexec("^\\{\\{([#^])(\\w+)\\}\\}$", line))[[1]]
    if (length(open) > 0) {
      if (!open[3] %in% names(values)) stop("No value for the block ", open[3], call. = FALSE)
      keep <- c(keep, tail(keep, 1) && (nzchar(values[[open[3]]]) == (open[2] == "#")))
    } else if (grepl("^\\{\\{/\\w+\\}\\}$", line)) {
      keep <- head(keep, -1)
    } else if (tail(keep, 1)) {
      out <- c(out, line)
    }
  }
  paste0(paste(out, collapse = "\n"), if (endsWith(text, "\n")) "\n")
}

render_text <- function(text, values) {
  missing <- names(values)[vapply(values, function(value) length(value) != 1 || is.na(value), logical(1))]
  if (length(missing) > 0) stop("No value for: ", paste(missing, collapse = ", "), call. = FALSE)
  text <- apply_blocks(text, values)
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

selected_files <- function(choices, values = list()) {
  files <- read_list("files.tsv")
  checks <- read_list("checks.tsv")
  on_checks <- checks$check[vapply(checks$key, function(key) choices$checks[[key]]$on, logical(1))]
  # A check column of "any" means at least one check is on. (The existing column is for the site's route for a package
  # that already exists; the command line only makes new packages.)
  check_ok <- !nzchar(files$check) |
    ("ci" %in% choices$parts & ifelse(files$check == "any", length(on_checks) > 0, files$check %in% on_checks))
  # needs: a value that must not be empty (the licence, a chosen issue form).
  needs_ok <- !nzchar(files$needs) | vapply(files$needs, function(name) nzchar(values[[name]] %||% ""), logical(1))
  keep <- files$part %in% choices$parts & check_ok & (files$release == "any" | files$release == choices$release) & needs_ok
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
  for (path in selected_files(choices, values)) {
    text <- render_text(read_text(kit_path("template", path)), values)
    write_text(text, file.path(out, render_text(path, values)))
  }
  invisible(out)
}
