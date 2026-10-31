# Reads the command line and calls the right function. Returns the exit status.
flag_value <- function(args, name, default = "") {
  at <- match(paste0("--", name), args)
  if (is.na(at)) default else args[at + 1]
}

has_flag <- function(args, name) paste0("--", name) %in% args

git_name_is_ai <- function() {
  name <- suppressWarnings(tryCatch(system2("git", c("config", "user.name"), stdout = TRUE), error = function(e) ""))
  length(name) == 1 && grepl("claude|copilot|gemini|codex|cursor|\\bai\\b", name, ignore.case = TRUE)
}

cmd_new <- function(args) {
  package <- args[1]
  problem <- if (is.na(package)) "Give the package a name: kit.R new mypkg" else check_package_name(package)
  if (nzchar(problem)) {
    message(problem)
    return(1L)
  }
  choices <- default_choices(package, flag_value(args, "preset", kit_setting("preset")))
  if (has_flag(args, "recommended")) {
    choices$title <- flag_value(args, "title", "An R Package")
    author <- strsplit(flag_value(args, "author", "Your Name"), " +")[[1]]
    choices$given <- author[1]
    choices$family <- paste(author[-1], collapse = " ")
    choices$email <- flag_value(args, "email", "you@example.com")
    choices$owner <- flag_value(args, "owner")
    choices$visibility <- if (has_flag(args, "public")) "public" else "private"
    choices$release <- if (has_flag(args, "internal")) "internal" else "cran"
    choices$year <- flag_value(args, "year", choices$year)
  } else {
    choices <- ask_choices(choices)
  }
  out <- flag_value(args, "out", package)
  if (dir.exists(out) && length(list.files(out, all.files = TRUE, no.. = TRUE)) > 0) {
    message("That folder already has files in it: ", out)
    return(1L)
  }
  build_package(choices, out)
  cat("Created", out, "\n")
  if (!has_flag(args, "no-git") && nzchar(Sys.which("git"))) {
    if (git_name_is_ai()) {
      message("Your git name looks like an AI tool, so the first commit was skipped.")
      return(0L)
    }
    git <- function(...) system2("git", c("-C", shQuote(out), ...), stdout = FALSE, stderr = FALSE)
    git("init", "-q", "-b", strsplit(choices$branches, ",")[[1]][1])
    git("add", "-A")
    git("commit", "-q", "-m", shQuote("feat: start the package"))
  }
  0L
}

cmd_gate <- function(args) {
  system2(file.path(R.home("bin"), "Rscript"), c(shQuote(kit_path("quality-gate", "quality-gate.R")), args))
}

kit_main <- function(args) {
  command <- if (length(args) > 0) args[1] else "help"
  rest <- args[-1]
  switch(command,
    new = cmd_new(rest),
    gate = cmd_gate(rest),
    github = cmd_github(rest),
    eject = cmd_eject(rest),
    {
      cat("Commands: new, gate, github, eject. See the top of cli/kit.R.\n")
      0L
    }
  )
}
