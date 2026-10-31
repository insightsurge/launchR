# The questions, kept apart from the functions that do the work.
ask <- function(question, default = "") {
  label <- if (nzchar(default)) sprintf("%s [%s]: ", question, default) else sprintf("%s: ", question)
  cat(label)
  answer <- trimws(readLines(getOption("kit.stdin"), n = 1))
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

ask_choices <- function(choices) {
  options(kit.stdin = file("stdin", "r"))
  choices$title <- ask("One-line title, in title case")
  author <- strsplit(ask("Your name"), " +")[[1]]
  choices$given <- author[1]
  choices$family <- paste(author[-1], collapse = " ")
  choices$email <- ask("Your email, shown in DESCRIPTION")
  choices$owner <- ask("GitHub user or organisation, Enter if you have none")
  choices$visibility <- ask_choice("Public or private repository", c("private", "public"))
  choices$release <- ask_choice("Going to CRAN or staying internal", c("cran", "internal"))
  parts <- read_list("parts.tsv")
  for (i in which(parts$part != "skeleton")) {
    on <- parts$part[i] %in% choices$parts
    answer <- ask_choice(sprintf("%s: %s", parts$label[i], parts$description[i]), if (on) c("yes", "no") else c("no", "yes"))
    choices$parts <- setdiff(choices$parts, parts$part[i])
    if (answer == "yes") choices$parts <- c(choices$parts, parts$part[i])
  }
  choices
}
