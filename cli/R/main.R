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
  title = '"Tools For Tables"', author = '"Asha Rao"', email = "asha@example.com", owner = "insightsurge",
  path = "mypkg", preset = "starter", plan = "d", year = "2026", repo = "owner/name", `min-r` = "4.3"
)

usage_error <- function(message) {
  structure(class = c("usage_error", "error", "condition"), list(message = message, call = NULL))
}

`%||%` <- function(x, y) if (is.null(x)) y else x

has_flag <- function(args, name) paste0("--", name) %in% args

git_available <- function() nzchar(Sys.which("git"))

git_name_is_ai <- function() {
  name <- suppressWarnings(tryCatch(system2("git", c("config", "user.name"), stdout = TRUE), error = function(e) ""))
  length(name) == 1 && grepl("claude|copilot|gemini|codex|cursor|\\bai\\b", name, ignore.case = TRUE)
}

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
    return(0L)
  }
  if (!git_available()) {
    message("git isn't installed, so the folder is not a repository yet. Install git, then run: git init")
    return(0L)
  }
  if (git_name_is_ai()) {
    message("Your git name looks like an AI tool, so the first commit was skipped.")
    return(0L)
  }
  git <- function(...) system2("git", c("-C", quote_arg(out), ...), stdout = FALSE, stderr = FALSE)
  git("init", "-q", "-b", strsplit(choices$branches, ",")[[1]][1])
  git("add", "-A")
  status <- git("commit", "-q", "-m", quote_arg("feat: start the package"))
  if (status != 0L) {
    message("The first commit failed. Set your name and email (git config --global user.name and user.email), then commit.")
  }
  0L
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
