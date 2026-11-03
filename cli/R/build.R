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
    check_badge = if (public && has_owner && "ci" %in% choices$parts && isTRUE(choices$checks$r_cmd_check$on)) {
      sprintf("[![R-CMD-check](%s/actions/workflows/r-cmd-check.yaml/badge.svg)](%s/actions/workflows/r-cmd-check.yaml)", repository, repository)
    } else {
      ""
    },
    credit_badge = if (public) sprintf("[![Set up with launchR](https://img.shields.io/badge/set%%20up%%20with-launchR-f6ab85)](%s)\n", site_url) else "",
    credit_line = sprintf("\nSet up with [launchR](%s).", site_url)
  )
  # The oldest R supported: in DESCRIPTION, and in place of 4.1 in the default platforms.
  min_r <- if (nzchar(choices$min_r %||% "")) choices$min_r else kit_setting("min_r")
  # DESCRIPTION takes major.minor.0: R CMD check warns about any other patch level. CI runs the newest patch of it.
  values$min_r <- paste0(min_r, ".0")
  ci_on <- "ci" %in% choices$parts
  on_rows <- if (ci_on) which(vapply(checks$key, function(key) isTRUE(choices$checks[[key]]$on), logical(1))) else integer()
  values$checks_table <- paste(
    sprintf("| `%s.yaml` | %s | %s |", checks$check[on_rows], checks$label[on_rows],
      vapply(checks$key[on_rows], function(key) when_text(choices$checks[[key]]), character(1))),
    collapse = "\n"
  )
  if (length(on_rows) == 0) values$checks_table <- "| None yet | Come back to the site to add one | |"
  for (kind in names(test_kinds)) {
    rows <- on_rows[checks$key[on_rows] %in% test_kinds[[kind]]]
    values[[paste0("runs_", kind)]] <- if (length(rows) > 0) paste0("`", checks$check[rows], "`", collapse = ", ") else "none of the checks yet"
  }
  # .Renviron runs the extended tests locally when a check runs them in CI.
  extended_in_ci <- ci_on && any(vapply(c("full_tests", "coverage", "r_cmd_check_extended"), function(key) isTRUE(choices$checks[[key]]$on), logical(1)))
  values$extended_env <- if (extended_in_ci) "EXTENDED_TESTS=true" else "# EXTENDED_TESTS=true"
  values$browser_row <- if (frontend) {
    sprintf("| `-browser.R` | Tests that drive a browser (shinytest2, chromote); start them with `options(chromote.timeout = 60)`, as Chrome can start slowly on CI | `test-demo-browser.R` | %s |", values$runs_browser)
  } else {
    ""
  }
  values$browser_skip <- if (frontend) "skip_on_cran()                                                    # -browser.R files" else ""
  # How to send coverage to Codecov; codecov.yml comes with new packages only (an existing package's .Rbuildignore
  # doesn't list it).
  values$codecov_note <- if (ci_on && isTRUE(choices$checks$coverage$on)) {
    yml <- if ("skeleton" %in% choices$parts) {
      c("", "`codecov.yml` at the top of the package keeps Codecov to reporting: no blocking status and no second comment.")
    }
    paste0(paste(c(
      "## Codecov",
      "",
      "The coverage check decides on its own. To also show coverage on Codecov:",
      "",
      "1. Sign in at <https://about.codecov.io> with GitHub and add this repository.",
      "2. Copy its upload token. On GitHub, add it as a repository secret named `CODECOV_TOKEN` (Settings, then Secrets and",
      "   variables, then Actions).",
      "3. In `coverage.yaml`, remove the `#` before the `secrets:` and `CODECOV_TOKEN:` lines.",
      yml
    ), collapse = "\n"), "\n\n")
  } else {
    ""
  }
  test_kinds_text <- paste(c(
    "## Test file kinds",
    "",
    "Most tests run in every check. Files whose name ends in a kind run only where they can:",
    "",
    "| File name ends in | What it holds | Runs in |",
    "| --- | --- | --- |",
    sprintf("| `-browser.R` | Tests that drive a browser (shinytest2, chromote); start them with `options(chromote.timeout = 60)`, as Chrome can start slowly on CI | %s |", values$runs_browser),
    sprintf("| `-snap.R` | Snapshot tests (`expect_snapshot()`) | %s |", values$runs_snap),
    sprintf("| `-extended.R` | Slow or detailed tests | %s |", values$runs_extended),
    "",
    "Start each browser file with `skip_on_cran()` and each extended file with",
    "`skip_if_not(identical(Sys.getenv(\"EXTENDED_TESTS\"), \"true\"))`, so CRAN and R CMD check skip them."
  ), collapse = "\n")
  values$test_kinds_section <- if ("skeleton" %in% choices$parts) {
    "Which test files each check runs: `tests/README.md`.\n\n"
  } else {
    paste0(test_kinds_text, "\n\n")
  }
  values$full_tests_line <- if (ci_on && isTRUE(choices$checks$full_tests$on)) {
    "`full-tests` runs every kind and fails if any test skips there. "
  } else {
    ""
  }
  values$time_limit_section <- if (ci_on && isTRUE(choices$checks$r_cmd_check$on)) {
    paste0(
      "## The time limit\n\n`r-cmd-check` fails when the tests take longer than `test-time-limit` seconds on Linux with R release (180 by default;\n",
      "0 turns it off). CRAN asks for quick checks. Move slow tests to a `-extended.R` file, or make them faster.\n\n"
    )
  } else {
    ""
  }
  for (i in seq_len(nrow(checks))) {
    key <- checks$key[i]
    check <- choices$checks[[key]]
    for (event in c("pr", "push", "schedule", "manual")) {
      values[[sprintf("c_%s_%s", key, event)]] <- if (event %in% check$events) "" else "# "
    }
    values[[paste0("cron_", key)]] <- check$cron
    default <- checks[[paste0("platforms_", choices$visibility)]][i]
    # The default oldest R (4.1) in a check's systems becomes the chosen one, and R CMD check runs on it on Linux, as
    # the site's Modify page does. engine.js has the same.
    default <- gsub(paste0("/", kit_setting("min_r")), paste0("/", min_r), default, fixed = TRUE)
    if (key == "r_cmd_check" && min_r != kit_setting("min_r") && !grepl(paste0("ubuntu/", min_r), default, fixed = TRUE)) {
      default <- paste0(default, ", ubuntu/", min_r)
    }
    values[[paste0("platforms_", key)]] <- if (is.null(check$platforms)) default else check$platforms
  }
  values
}

# When a check runs, in words for the workflows README: "pull requests, pushes, Mondays at 05:00 UTC, by hand".
# site/src/form/engine.js has the same.
when_text <- function(check) {
  cron <- strsplit(check$cron, " ", fixed = TRUE)[[1]]
  time <- sprintf("%02d:%02d UTC", as.integer(cron[2]), as.integer(cron[1]))
  weekdays <- c("Sundays", "Mondays", "Tuesdays", "Wednesdays", "Thursdays", "Fridays", "Saturdays")
  parts <- c(
    if ("pr" %in% check$events) "pull requests",
    if ("push" %in% check$events) "pushes",
    if ("schedule" %in% check$events) {
      if (cron[5] == "*") paste("every day at", time) else paste(weekdays[as.integer(cron[5]) + 1], "at", time)
    },
    if ("manual" %in% check$events) "by hand"
  )
  paste(parts, collapse = ", ")
}

# Which of the package's checks run each kind of test file, for tests/README.md.
test_kinds <- list(
  plain = c("r_cmd_check", "coverage", "full_tests", "r_cmd_check_extended"),
  browser = "full_tests",
  snap = "full_tests",
  extended = c("coverage", "full_tests", "r_cmd_check_extended")
)

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
  missing <- names(values)[vapply(values, function(value) length(value) != 1 || is.na(value), logical(1))]
  if (length(missing) > 0) stop("No value for: ", paste(missing, collapse = ", "), call. = FALSE)
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
    (!nzchar(files$check) | ("ci" %in% choices$parts & files$check %in% on_checks)) &
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
