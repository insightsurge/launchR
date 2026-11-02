# What a person chooses, as a plain list. The app's form and these functions hold the same fields.
default_choices <- function(package, preset = kit_setting("preset")) {
  parts <- read_list("parts.tsv")
  checks <- read_list("checks.tsv")
  on_part <- parts$part[parts[[preset]] == "yes"]
  list(
    package = package,
    title = "",
    given = "",
    family = "",
    email = "",
    owner = "",
    visibility = "private",
    release = "cran",
    year = format(Sys.Date(), "%Y"),
    branches = kit_setting("branches"),
    parts = on_part,
    checks = lapply(stats::setNames(seq_len(nrow(checks)), checks$key), function(i) {
      list(
        on = checks[[preset]][i] == "yes",
        events = strsplit(checks$events[i], ",", fixed = TRUE)[[1]],
        cron = checks$cron[i],
        platforms = NULL
      )
    })
  )
}

check_package_name <- function(name) {
  if (nchar(name) < 2) {
    return("Names need at least two characters.")
  }
  if (!grepl("^[A-Za-z]", name)) {
    return("Names must start with a letter.")
  }
  if (grepl("[.]$", name)) {
    return("Names can't end in a dot.")
  }
  if (!grepl("^[A-Za-z0-9.]+$", name)) {
    return("Names can only use letters, numbers and dots.")
  }
  ""
}

# The GitHub user or organisation: it fills URL, BugReports and the help page's links, so use_github() finds nothing to
# add. The same rule as the site's form.
check_owner <- function(owner) {
  if (!nzchar(owner)) {
    return("Give your GitHub user or organisation name, such as insightsurge.")
  }
  if (!grepl("^[A-Za-z0-9][A-Za-z0-9-]{0,38}$", owner)) {
    return("Use only your GitHub name, such as insightsurge, not a link.")
  }
  ""
}
