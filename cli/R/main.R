# Reads the command line and calls the right function. Returns the exit status.

# A flag's value. A flag given without one (last on the line, or followed by another flag) stops the command, so a
# missing value never reaches a file.
flag_value <- function(args, name, default = "") {
  at <- match(paste0("--", name), args)
  if (is.na(at)) {
    return(default)
  }
  value <- args[at + 1]
  if (is.na(value) || startsWith(value, "--")) {
    stop(usage_error(sprintf("--%s needs a value, such as --%s %s.", name, name, flag_example[[name]] %||% "value")))
  }
  value
}

flag_example <- list(
  title = '"Tools For Tables"', description = '"Builds tables for clinical reports."', author = '"Asha Rao"', email = "asha@example.com", owner = "insightsurge",
  path = "mypkg", preset = "starter", plan = "d", year = "2026", repo = "owner/name", `min-r` = "4.3",
  licence = "proprietary", badges = "check,lifecycle", navbar = "reference,news,search", forms = "bug,docs", labels = "bug,documentation"
)

usage_error <- function(message) {
  structure(class = c("usage_error", "error", "condition"), list(message = message, call = NULL))
}

`%||%` <- function(x, y) if (is.null(x)) y else x

has_flag <- function(args, name) paste0("--", name) %in% args

git_available <- function() nzchar(Sys.which("git"))

cmd_new <- function(args) {
  package <- args[1]
  problem <- if (is.na(package)) "Give the package a name: launchr.R new mypkg" else check_package_name(package)
  if (nzchar(problem)) {
    message(problem)
    return(1L)
  }
  preset <- flag_value(args, "preset", kit_setting("preset"))
  presets <- setdiff(names(read_list("parts.tsv")), c("part", "label", "description"))
  if (!preset %in% presets) {
    message("--preset is one of: ", paste(presets, collapse = ", "), ".")
    return(1L)
  }
  plan <- plan_from_flags(args)
  if (!plan %in% read_list("plans.tsv")$plan) {
    message("--plan is one of: ", paste(read_list("plans.tsv")$plan, collapse = ", "), " (see lists/plans.tsv).")
    return(1L)
  }
  choices <- default_choices(package, preset, plan)
  if (has_flag(args, "yes")) {
    choices$title <- flag_value(args, "title", "An R Package")
    choices$description <- flag_value(args, "description")
    author <- split_name(flag_value(args, "author", "Your Name"))
    choices$given <- author[1]
    choices$family <- author[2]
    choices$email <- flag_value(args, "email")
    choices$owner <- flag_value(args, "owner")
    choices$year <- flag_value(args, "year", choices$year)
    choices$min_r <- flag_value(args, "min-r", choices$min_r)
    problems <- c(
      `min-r` = check_min_r(choices$min_r),
      title = check_title(choices$title),
      description = check_description(choices$description, package),
      author = check_person(choices$given, "first"),
      author = check_person(choices$family, "last"),
      email = check_email(choices$email),
      owner = check_owner(choices$owner)
    )
    problems <- problems[nzchar(problems)]
    if (length(problems) > 0) {
      message(paste(sprintf("%s (--%s)", problems, names(problems)), collapse = "\n"))
      return(1L)
    }
  } else {
    choices <- ask_choices(choices)
  }
  modified <- modify_from_flags(args, choices)
  if (is.character(modified)) {
    message(modified)
    return(1L)
  }
  choices <- modified
  out <- flag_value(args, "path", package)
  if (dir.exists(out) && length(list.files(out, all.files = TRUE, no.. = TRUE)) > 0) {
    message("That folder already has files in it: ", out)
    return(1L)
  }
  build_package(choices, out)
  cat("Created", out, "\n")
  placeholders <- c(
    if (identical(c(choices$given, choices$family), c("Your", "Name"))) "author (--author)",
    if (!nzchar(choices$email)) "email (--email)"
  )
  if (length(placeholders) > 0) {
    message("Replace the placeholder ", paste(placeholders, collapse = " and "), " in DESCRIPTION before you publish.")
  }
  if (has_flag(args, "no-git")) {
    print_next_steps(choices, package, out, committed = FALSE)
    return(0L)
  }
  if (!git_available()) {
    message("git isn't installed, so the folder is not a repository yet. Install git, then run: git init")
    print_next_steps(choices, package, out, committed = FALSE)
    return(0L)
  }
  git <- function(...) system2("git", c("-C", quote_arg(out), ...), stdout = FALSE, stderr = FALSE)
  branch <- strsplit(choices$branches, ",")[[1]][1]
  init <- git("init", "-q", "-b", branch)
  if (init != 0L) {
    # git before 2.28 has no -b: start the repository, then name its first branch.
    init <- git("init", "-q")
    if (init == 0L) init <- git("symbolic-ref", "HEAD", paste0("refs/heads/", branch))
  }
  if (init != 0L) {
    message("git couldn't start a repository in the folder. launchR needs git 2.28 or newer (git --version), or run: git init")
    print_next_steps(choices, package, out, committed = FALSE)
    return(0L)
  }
  git("add", "-A")
  status <- git("commit", "-q", "-m", quote_arg("feat: start the package"))
  if (status != 0L) {
    message("The first commit failed. Set your name and email (git config --global user.name and user.email), then commit.")
  }
  print_next_steps(choices, package, out, committed = status == 0L)
  0L
}

# What to do next, in the order of the site's R route. use_github() needs a repository with a commit, so without one
# the step starts with use_git().
print_next_steps <- function(choices, package, out, committed) {
  private <- if (identical(choices$visibility, "private")) "TRUE" else "FALSE"
  cat(
    "Next:\n",
    "  1. Open ", out, " (", package, ".Rproj in RStudio, or the folder in Positron).\n",
    "  2. In R: install.packages(c(\"devtools\", \"gitcreds\", \"pak\")) (skip any you have), then\n",
    "     pak::local_install_dev_deps() and devtools::test()\n",
    "  3. Let R reach GitHub, once (skip if it can): usethis::create_github_token(), then gitcreds::gitcreds_set()\n",
    "  4. Put it on GitHub: ", if (!committed) "usethis::use_git() (answer yes to commit), then ", "usethis::use_github(private = ", private, ")\n",
    "     for an organisation: usethis::use_github(organisation = \"", choices$owner, "\", private = ", private, ")\n",
    if ("github" %in% choices$parts) "  5. On GitHub, go to Actions, open \"Set up this repository\", click Run workflow, untick \"Only show what would change\", and run it.\n",
    sep = ""
  )
}

cmd_gate <- function(args) {
  system2(file.path(R.home("bin"), "Rscript"), c(quote_arg(kit_path("quality-gate", "quality-gate.R")), vapply(args, quote_arg, "")))
}

# The plan: --plan a to d, or the older --public and --internal flags; without either, the default in settings.tsv.
plan_from_flags <- function(args) {
  plan <- flag_value(args, "plan", "")
  if (nzchar(plan)) {
    return(plan)
  }
  if (!has_flag(args, "public") && !has_flag(args, "internal")) {
    return(kit_setting("plan"))
  }
  plans <- read_list("plans.tsv")
  visibility <- if (has_flag(args, "public")) "public" else "private"
  release <- if (has_flag(args, "internal")) "internal" else "cran"
  plans$plan[plans$visibility == visibility & plans$release == release]
}

# "Asha Rao" or "Ana de la Cruz": the first word is the given name, the rest the family name.
split_name <- function(name) {
  words <- strsplit(trimws(name), " +")[[1]]
  c(if (length(words) > 0) words[1] else "", paste(words[-1], collapse = " "))
}

kit_main <- function(args) {
  tryCatch(run_command(args), usage_error = function(e) {
    message(conditionMessage(e))
    1L
  })
}

run_command <- function(args) {
  command <- if (length(args) > 0) args[1] else "help"
  rest <- args[-1]
  switch(command,
    new = cmd_new(rest),
    gate = cmd_gate(rest),
    "github-setup" = cmd_github(rest),
    eject = cmd_eject(rest),
    {
      cat("Commands: new, gate, github-setup, eject. See the top of cli/launchr.R.\n")
      0L
    }
  )
}

# The site's settings, as flags: --no-ci-report, --licence, --badges, --navbar, --forms, --labels, --checklists,
# --qc and --no-qc.
# A list flag replaces the default list with the comma-separated keys given ("none" for an empty one). Returns the
# choices, or a message saying what is wrong.
modify_from_flags <- function(args, choices) {
  if (has_flag(args, "no-ci-report")) choices$ci_report <- FALSE
  choices$licence <- flag_value(args, "licence", choices$licence)
  if (!choices$licence %in% c("mit", "proprietary")) {
    return("--licence is mit or proprietary.")
  }
  if (choices$licence == "proprietary" && choices$release == "cran") {
    message("Note: CRAN only accepts open-source licences, and R CMD check as CRAN gives a NOTE for a proprietary one.")
  }
  known <- list(
    badges = read_list("badges.tsv")$key, navbar = read_list("navbar.tsv")$key,
    forms = read_list("forms.tsv")$key, labels = read_list("labels.tsv")$name, checklists = read_list("stages.tsv")$key
  )
  for (name in names(known)) {
    if (!paste0("--", name) %in% args) next
    given <- trimws(strsplit(flag_value(args, name), ",", fixed = TRUE)[[1]])
    given <- if (identical(given, "none")) character() else given[nzchar(given)]
    unknown <- setdiff(given, known[[name]])
    if (length(unknown) > 0) {
      return(sprintf("--%s takes some of: %s (unknown: %s).", name, paste(known[[name]], collapse = ", "), paste(unknown, collapse = ", ")))
    }
    choices[[name]] <- known[[name]][known[[name]] %in% given]
  }
  # --qc and --no-qc, from before --checklists, add and remove the QC checklist: sections of Next release.
  if (has_flag(args, "qc")) choices$checklists <- union(choices$checklists, "qc")
  if (has_flag(args, "no-qc")) choices$checklists <- setdiff(choices$checklists, "qc")
  if ("qc" %in% choices$checklists && !"next-release" %in% choices$checklists) {
    return("QC is sections of Next release, so add next-release to --checklists.")
  }
  choices
}
