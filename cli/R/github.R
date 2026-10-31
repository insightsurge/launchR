# Labels, the root issue and the stage checklists. Lists what it will do, then acts on a yes. Safe to run again.
gh_available <- function() nzchar(Sys.which("gh"))

gh_json <- function(args) {
  out <- suppressWarnings(tryCatch(system2("gh", args, stdout = TRUE, stderr = FALSE), error = function(e) character()))
  if (!is.null(attr(out, "status"))) character() else out
}

check_box <- function(kind, target) {
  if (kind == "file") {
    return(file.exists(target))
  }
  if (kind == "placeholder") {
    parts <- strsplit(target, "|", fixed = TRUE)[[1]]
    return(file.exists(parts[1]) && !grepl(parts[2], read_text(parts[1]), fixed = TRUE))
  }
  NA
}

package_facts <- function() {
  target <- read.dcf("DESCRIPTION", fields = "Config/quality-gate/target")[[1]]
  visibility <- gh_json(c("repo", "view", "--json", "visibility", "--jq", ".visibility"))
  list(
    public = length(visibility) == 1 && visibility == "PUBLIC",
    connected = length(visibility) == 1,
    internal = identical(target, "internal")
  )
}

open_stages <- function(facts) {
  stage <- if (facts$public) "After public" else "Before public"
  c(stage, if (!facts$internal) "Before CRAN")
}

checklist_body <- function(stage, internal, old_body = "") {
  rows <- read_list("checklists.tsv")
  rows <- rows[rows$stage == stage & (rows$release == "any" | !internal), ]
  lines <- character()
  for (section in unique(rows$section)) {
    lines <- c(lines, sprintf("### %s", section), "")
    for (i in which(rows$section == section)) {
      state <- check_box(rows$kind[i], rows$target[i])
      if (is.na(state)) state <- grepl(sprintf("- [x] %s", rows$text[i]), old_body, fixed = TRUE)
      lines <- c(lines, sprintf("- [%s] %s", if (state) "x" else " ", rows$text[i]))
    }
    lines <- c(lines, "")
  }
  c(lines, sprintf("Checked by r-pkg-kit on %s.", format(Sys.Date())))
}

github_plan <- function(facts) {
  labels <- read_list("labels.tsv")
  stages <- open_stages(facts)
  cat("r-pkg-kit will:\n")
  cat(sprintf("- create or update %d labels\n", nrow(labels)))
  cat("- open a root issue, \"About this repository\", if there isn't one\n")
  for (stage in stages) {
    body <- checklist_body(stage, facts$internal)
    done <- sum(startsWith(body, "- [x]"))
    total <- sum(startsWith(body, "- ["))
    cat(sprintf("- open or update the \"%s\" checklist (%d of %d boxes ticked)\n", stage, done, total))
  }
  stages
}

find_issue <- function(title) {
  found <- gh_json(c("issue", "list", "--state", "all", "--search", shQuote(sprintf("%s in:title", title)),
    "--json", "number,title", "--jq", shQuote(sprintf('.[] | select(.title == "%s") | .number', title))))
  if (length(found) > 0) found[1] else ""
}

put_issue <- function(title, body, parent = "") {
  file <- tempfile(fileext = ".md")
  writeLines(body, file)
  number <- find_issue(title)
  if (nzchar(number)) {
    system2("gh", c("issue", "edit", number, "--body-file", shQuote(file)), stdout = FALSE)
    return(number)
  }
  url <- gh_json(c("issue", "create", "--title", shQuote(title), "--body-file", shQuote(file),
    if (nzchar(parent)) c("--parent", parent)))
  sub(".*/", "", url[length(url)])
}

cmd_github <- function(args) {
  if (!file.exists("DESCRIPTION")) {
    message("Run this from the package's folder.")
    return(1L)
  }
  facts <- if (gh_available()) package_facts() else list(public = FALSE, connected = FALSE, internal = FALSE)
  if (!facts$connected) cat("Not connected to a GitHub repository yet, so this shows the plan for a private one.\n")
  stages <- github_plan(facts)
  if (has_flag(args, "dry-run") || !facts$connected) {
    cat("Nothing was changed.\n")
    return(0L)
  }
  if (!has_flag(args, "yes")) {
    options(kit.stdin = file("stdin", "r"))
    if (ask_choice("Go ahead", c("no", "yes")) != "yes") {
      cat("Nothing was changed.\n")
      return(0L)
    }
  }
  labels <- read_list("labels.tsv")
  for (i in seq_len(nrow(labels))) {
    system2("gh", c("label", "create", shQuote(labels$name[i]), "--force", "--color", labels$color[i],
      "--description", shQuote(labels$description[i])), stdout = FALSE, stderr = FALSE)
    Sys.sleep(0.5)  # GitHub limits how fast labels and issues can be created
  }
  root <- put_issue("About this repository", c("The plan for this package.", "",
    "Each checklist below is a sub-issue. Unticked boxes are what's left to do."))
  for (stage in stages) {
    title <- sprintf("Checklist: %s", stage)
    number <- find_issue(title)
    old <- if (nzchar(number)) paste(gh_json(c("issue", "view", number, "--json", "body", "--jq", ".body")), collapse = "\n") else ""
    put_issue(title, checklist_body(stage, facts$internal, old), root)
    Sys.sleep(1)
  }
  cat("Done.\n")
  0L
}
