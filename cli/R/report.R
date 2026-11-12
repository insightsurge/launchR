# The report at the end of Set up this repository: what changed (or, in a dry run, what would), with links. The
# console gets plain text with full addresses; on GitHub the same report goes to the run's summary page as Markdown.

# A box line's text without the box, the launchR marker, and (when there is no repository to link to) its links.
box_text <- function(line, links = TRUE) {
  text <- sub("^\\s*- \\[[ xX]\\]\\s*", "", line)
  text <- sub("\\s*<!-- launchr:[^>]+-->\\s*$", "", text)
  if (!links) text <- gsub("\\[([^]]+)\\]\\([^)]*\\)", "\\1", text)
  trimws(text)
}

keep_note <- "Keep the Set up this repository workflow: run it again to tick boxes and open the next checklist. If you would rather use R, you can delete `.github/workflows/github-setup.yaml`; the R line does the same."

# What the report says, once, for both ways of showing it.
report_data <- function(ctx, plan, created = NULL, dry_run = FALSE) {
  verb <- function(done, would) if (dry_run) would else done
  url <- function(path) if (ctx$connected) sprintf("https://github.com/%s/%s", ctx$repo, path) else ""
  issue_url <- function(number) if (nzchar(number %||% "")) url(paste0("issues/", number)) else ""
  labels <- list(
    list(what = verb("Created", "Would create"), names = plan$labels$name[plan$label_action == "create"]),
    list(what = verb("Updated", "Would update"), names = plan$labels$name[plan$label_action == "update"]),
    list(what = verb("Removed", "Would remove"), names = if (isTRUE(ctx$remove_labels)) plan$other_labels else character())
  )
  labels <- Filter(function(x) length(x$names) > 0, labels)
  root_number <- if (!is.null(created)) created$root else if (!is.null(plan$root)) plan$root$number else ""
  issues <- list(list(
    title = root_title, url = issue_url(root_number),
    action = if (is.null(plan$root)) verb("created", "would create") else "already there",
    ticked = character(), unticked = character(), closed = FALSE, todo = character()
  ))
  for (item in plan$checklists) {
    number <- if (!is.null(created) && item$stage %in% names(created$numbers)) created$numbers[[item$stage]] else item$number
    open_boxes <- item$lines[is_box(item$lines) & !is_ticked(item$lines)]
    issues[[length(issues) + 1]] <- list(
      title = checklist_title(item$stage), url = issue_url(number),
      action = switch(item$action, create = verb("created", "would create"), update = verb("updated", "would update"), same = "no change"),
      ticked = item$ticked, unticked = item$unticked, closed = isTRUE(item$close),
      todo = if (isTRUE(item$close)) character() else vapply(open_boxes, box_text, "", links = ctx$connected, USE.NAMES = FALSE)
    )
  }
  list(
    heading = if (dry_run) "What a real run would change" else "What changed",
    labels = labels, labels_url = url("labels"), label_count = nrow(plan$labels),
    issues = issues, closed = plan$closed, dry_run = dry_run,
    # The first real run of a package that has the workflow: say why to keep it.
    keep_note = !dry_run && is.null(plan$root) && file.exists(file.path(".github", "workflows", "github-setup.yaml"))
  )
}

report_console <- function(data) {
  out <- c(paste0(data$heading, ":"), sprintf("Labels%s", if (nzchar(data$labels_url)) paste0(" (", data$labels_url, ")") else ""))
  out <- c(out, if (length(data$labels)) vapply(data$labels, function(x) sprintf("- %s: %s", x$what, paste(x$names, collapse = ", ")), "") else
    sprintf("- all %d already right", data$label_count))
  out <- c(out, "", "Issues")
  for (issue in data$issues) {
    out <- c(out, sprintf("- %s: %s%s", issue$title, issue$action, if (issue$closed) ", closed: every box that isn't optional is ticked" else ""))
    if (nzchar(issue$url)) out <- c(out, paste0("  ", issue$url))
    if (length(issue$ticked)) out <- c(out, paste0("  ticked: ", issue$ticked))
    if (length(issue$unticked)) out <- c(out, paste0("  unticked: ", issue$unticked))
  }
  for (title in data$closed) out <- c(out, sprintf("- %s: closed, left closed", title))
  todo <- Filter(function(x) length(x$todo) > 0, data$issues)
  if (length(todo)) {
    out <- c(out, "", "Still to do")
    for (issue in todo) out <- c(out, sprintf("- %s (%d):", issue$title, length(issue$todo)), paste0("  - ", issue$todo))
  }
  if (data$keep_note) out <- c(out, "", keep_note)
  out
}

report_markdown <- function(data) {
  link <- function(text, url) if (nzchar(url)) sprintf("[%s](%s)", text, url) else text
  out <- c(sprintf("## Set up this repository: %s", tolower(data$heading)), "")
  if (data$dry_run) out <- c(out, "Nothing was changed. To make these changes, click **Run workflow** and untick **Only show what would change**.", "")
  out <- c(out, sprintf("### %s", link("Labels", data$labels_url)))
  out <- c(out, if (length(data$labels)) vapply(data$labels, function(x) sprintf("- **%s:** %s", x$what, paste0("`", x$names, "`", collapse = ", ")), "") else
    sprintf("- All %d already right", data$label_count))
  out <- c(out, "", "### Issues", "", "| Issue | This run | Boxes left |", "| --- | --- | --- |")
  for (issue in data$issues) {
    changes <- c(issue$action, if (length(issue$ticked)) sprintf("ticked %d", length(issue$ticked)),
      if (length(issue$unticked)) sprintf("unticked %d", length(issue$unticked)), if (issue$closed) "closed")
    out <- c(out, sprintf("| %s | %s | %s |", link(issue$title, issue$url), paste(changes, collapse = ", "),
      if (identical(issue$title, root_title)) "" else length(issue$todo)))
  }
  for (title in data$closed) out <- c(out, sprintf("| %s | closed, left closed | |", title))
  changed <- Filter(function(x) length(x$ticked) + length(x$unticked) > 0, data$issues)
  for (issue in changed) {
    out <- c(out, "", sprintf("<details><summary>%s: boxes ticked or unticked</summary>", issue$title), "",
      if (length(issue$ticked)) paste0("- ✅ ", issue$ticked), if (length(issue$unticked)) paste0("- ⬜ ", issue$unticked, " (unticked)"),
      "", "</details>")
  }
  todo <- Filter(function(x) length(x$todo) > 0, data$issues)
  if (length(todo)) {
    out <- c(out, "", "### Still to do")
    for (issue in todo) {
      out <- c(out, "", sprintf("<details><summary>%s: %d left</summary>", issue$title, length(issue$todo)), "",
        paste0("- ⬜ ", issue$todo), "", "</details>")
    }
  }
  if (data$keep_note) out <- c(out, "", keep_note)
  out
}

# Prints the report and, on GitHub, adds it to the run's summary page.
report_setup <- function(ctx, plan, created = NULL, dry_run = FALSE) {
  data <- report_data(ctx, plan, created, dry_run)
  summary_file <- Sys.getenv("GITHUB_STEP_SUMMARY")
  if (nzchar(summary_file)) cat(report_markdown(data), "", sep = "\n", file = summary_file, append = TRUE)
  cat("", report_console(data), "", sep = "\n")
  invisible(data)
}
