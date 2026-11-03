# The questions, kept apart from the functions that do the work.
# In an R console (RStudio, Positron) readline() reads what the person types; run as a script, the answers come from stdin.
read_answer <- function(label) {
  if (interactive()) {
    return(readline(label))
  }
  if (is.null(getOption("kit.stdin"))) options(kit.stdin = file("stdin", "r"))
  cat(label)
  readLines(getOption("kit.stdin"), n = 1)
}

ask <- function(question, default = "") {
  label <- if (nzchar(default)) sprintf("%s [%s]: ", question, default) else sprintf("%s: ", question)
  answer <- trimws(read_answer(label))
  if (length(answer) == 0 || !nzchar(answer)) default else answer
}

ask_choice <- function(question, options) {
  repeat {
    answer <- ask(sprintf("%s (%s)", question, paste(options, collapse = "/")), options[1])
    if (answer %in% options) {
      return(answer)
    }
    cat("Please answer one of:", paste(options, collapse = ", "), "\n")
  }
}

# Asks until the answer passes check(answer), printing the problem each time.
ask_until <- function(question, check, default = "") {
  repeat {
    answer <- ask(question, default)
    problem <- check(answer)
    if (!nzchar(problem)) {
      return(answer)
    }
    cat(problem, "\n")
  }
}

ask_choices <- function(choices) {
  choices$title <- ask_until("One-line title, in title case", check_title)
  choices$description <- ask_until("Describe it in a sentence or two (Enter to use the title)", function(text) check_description(text, choices$package))
  author <- split_name(ask_until("Your first and last name", function(name) {
    parts <- split_name(name)
    problem <- check_person(parts[1], "first")
    if (nzchar(problem)) problem else check_person(parts[2], "last")
  }))
  choices$given <- author[1]
  choices$family <- author[2]
  choices$email <- ask_until("Your email, shown in DESCRIPTION (Enter to add it later)", check_email)
  choices$owner <- ask_until("GitHub user or organisation", check_owner)
  plans <- read_list("plans.tsv")
  cat(sprintf("  %s: %s\n", plans$plan, plans$label), sep = "")
  chosen <- plan_row(ask_choice("Your plan for this package", plans$plan))
  choices$visibility <- chosen$visibility
  choices$release <- chosen$release
  if (chosen$extended == "no") choices$checks$r_cmd_check_extended$on <- FALSE
  parts <- read_list("parts.tsv")
  for (i in which(parts$part != "skeleton")) {
    on <- parts$part[i] %in% choices$parts
    answer <- ask_choice(sprintf("%s: %s", parts$label[i], parts$description[i]), if (on) c("yes", "no") else c("no", "yes"))
    choices$parts <- setdiff(choices$parts, parts$part[i])
    if (answer == "yes") choices$parts <- c(choices$parts, parts$part[i])
  }
  choices
}
