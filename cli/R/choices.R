# What a person chooses, as a plain list. The app's form and these functions hold the same fields.
default_choices <- function(package, preset = kit_setting("preset"), plan = kit_setting("plan")) {
  parts <- read_list("parts.tsv")
  checks <- read_list("checks.tsv")
  chosen <- plan_row(plan)
  on_part <- parts$part[parts[[preset]] == "yes"]
  list(
    package = package,
    title = "",
    description = "",
    given = "",
    family = "",
    email = "",
    owner = "",
    visibility = chosen$visibility,
    release = chosen$release,
    year = format(Sys.Date(), "%Y"),
    branches = kit_setting("branches"),
    min_r = kit_setting("min_r"),
    parts = on_part,
    checks = lapply(stats::setNames(seq_len(nrow(checks)), checks$key), function(i) {
      list(
        on = checks[[preset]][i] == "yes" && !(checks$key[i] == "r_cmd_check_extended" && chosen$extended == "no"),
        events = strsplit(checks$events[i], ",", fixed = TRUE)[[1]],
        cron = checks$cron[i],
        platforms = NULL
      )
    })
  )
}

# What a plan starts from: visibility, release, and whether r-cmd-check-extended is on (lists/plans.tsv).
plan_row <- function(plan) {
  plans <- read_list("plans.tsv")
  as.list(plans[plans$plan == plan, , drop = FALSE])
}

# The rules for what a person types, with the same messages in site/src/form/engine.js. DESCRIPTION holds these as text
# and as R code (Authors@R), so quotes and backslashes would break it.
check_title <- function(title) {
  if (!nzchar(title)) {
    return("Say in one line what it does. This goes in DESCRIPTION.")
  }
  if (nchar(title) > 65) {
    return(sprintf("Keep it to 65 characters. It is %d now.", nchar(title)))
  }
  if (grepl("[\"\\\\{}%]", title)) {
    return("Use plain words here: no double quotes, backslashes, braces or percent signs.")
  }
  ""
}

check_person <- function(name, which) {
  if (!nzchar(name)) {
    return(sprintf("Add a %s name. DESCRIPTION needs an author.", which))
  }
  if (grepl("[\"\\\\]", name)) "Names can't contain double quotes or backslashes." else ""
}

check_email <- function(email) {
  if (!nzchar(email) || grepl("^[^@[:space:]]+@[^@[:space:]]+\\.[^@[:space:]]+$", email)) {
    return("")
  }
  "That email looks incomplete, or leave it empty."
}

# The oldest R a package supports, as x.y (one digit each) from 4.1 on; DESCRIPTION gets x.y.0. site/src/form/engine.js
# has the same.
check_min_r <- function(min_r) {
  parts <- suppressWarnings(as.integer(strsplit(min_r, ".", fixed = TRUE)[[1]]))
  ok <- grepl("^[0-9]\\.[0-9]$", min_r) && (parts[1] > 4 || (parts[1] == 4 && parts[2] >= 1))
  if (ok) "" else "Give x.y from 4.1 on, such as 4.3. The .0 is added for you."
}

# A title without its full stop: DESCRIPTION's Description adds one.
clean_title <- function(title) sub("[.[:space:]]+$", "", title)

# DESCRIPTION's Description: the person's own sentences, or the title, ending in a full stop either way.
description_text <- function(choices) {
  text <- gsub("[[:space:]]+", " ", trimws(choices$description %||% ""))
  if (!nzchar(text)) {
    return(paste0(clean_title(choices$title), "."))
  }
  if (grepl("[.!?]$", text)) text else paste0(text, ".")
}

# The longer description is optional: left empty, DESCRIPTION repeats the title. R CMD check --as-cran notes a
# Description that starts with the package's name, with "This package", "A package" and the like, or in lower case.
check_description <- function(text, name = "") {
  if (!nzchar(text)) {
    return("")
  }
  if (nchar(text) > 500) {
    return(sprintf("Keep it to 500 characters. It is %d now.", nchar(text)))
  }
  if (grepl("[\"\\\\{}%]", text)) {
    return("Use plain words here: no double quotes, backslashes, braces or percent signs.")
  }
  if (grepl("^(the|this|a|in this|in the) package", text, ignore.case = TRUE) || (nzchar(name) && startsWith(tolower(text), tolower(name)))) {
    return("Start with what it does, not with \"This package\", \"A package\" or its name: CRAN asks for that.")
  }
  if (!grepl("^['A-Z]", text)) {
    return("Start with a capital letter, as CRAN asks.")
  }
  ""
}

# R's rules for a package name, plus a length limit and the names of R's own packages. site/src/form/engine.js has the
# same.
check_package_name <- function(name) {
  if (nchar(name) < 2) {
    return("Names need at least two characters.")
  }
  if (nchar(name) > 60) {
    return("Keep the name under 60 characters.")
  }
  if (name %in% trimws(strsplit(kit_setting("base_packages"), ",")[[1]])) {
    return(paste(name, "is part of R itself, so choose another name."))
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
    return(paste(
      "Give your GitHub username or organisation, such as insightsurge.",
      "No account yet? Sign up free at github.com/signup."
    ))
  }
  if (!grepl("^[A-Za-z0-9][A-Za-z0-9-]{0,38}$", owner)) {
    return("Use only your GitHub name, such as insightsurge, not a link.")
  }
  ""
}
