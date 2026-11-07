# Report of what "Set up this repository" changed, or what a dry run would change.

clean_box_text <- function(line, connected = TRUE) {
  text <- sub("^\\s*-\\s*\\[[ xX]\\]\\s*", "", line)
  text <- sub("\\s*<!--\\s*launchr:[^>]+-->\\s*$", "", text)
  if (!connected) {
    text <- gsub("\\[([^]]+)\\]\\([^)]*\\)", "\\1", text)
  }
  trimws(text)
}

still_to_do_items <- function(checklists, connected = TRUE) {
  items <- list()
  for (item in checklists) {
    if (isTRUE(item$close)) next
    unticked_lines <- item$lines[is_box(item$lines) & !is_ticked(item$lines)]
    if (length(unticked_lines) == 0) next
    texts <- vapply(unticked_lines, function(l) clean_box_text(l, connected = connected), "")
    items[[item$stage]] <- list(stage = item$stage, count = length(texts), boxes = unname(texts))
  }
  items
}

report_adds_something <- function(plan, ctx) {
  if (any(plan$label_action %in% c("create", "update"))) return(TRUE)
  if (isTRUE(ctx$remove_labels) && length(plan$other_labels) > 0) return(TRUE)
  for (item in plan$checklists) {
    if (length(item$ticked) > 0 || length(item$unticked) > 0) return(TRUE)
    if (isTRUE(item$close)) return(TRUE)
    unticked <- item$lines[is_box(item$lines) & !is_ticked(item$lines)]
    if (length(unticked) > 0) return(TRUE)
  }
  FALSE
}

build_console_report <- function(ctx, plan, created = NULL, dry_run = FALSE) {
  lines <- character()
  heading <- if (dry_run) "What would change:" else "What changed:"
  lines <- c(lines, heading)

  # 1. Labels
  created_labels <- plan$labels$name[plan$label_action == "create"]
  updated_labels <- plan$labels$name[plan$label_action == "update"]
  removed_labels <- if (isTRUE(ctx$remove_labels)) plan$other_labels else character()
  labels_link <- if (ctx$connected) sprintf("https://github.com/%s/labels", ctx$repo) else ""

  label_header <- if (nzchar(labels_link)) sprintf("Labels (%s):", labels_link) else "Labels:"
  lines <- c(lines, label_header)

  label_items <- character()
  if (length(created_labels) > 0) {
    label_items <- c(label_items, sprintf("- %s: %s", if (dry_run) "Would create" else "Created", paste(created_labels, collapse = ", ")))
  }
  if (length(updated_labels) > 0) {
    label_items <- c(label_items, sprintf("- %s: %s", if (dry_run) "Would update" else "Updated", paste(updated_labels, collapse = ", ")))
  }
  if (length(removed_labels) > 0) {
    label_items <- c(label_items, sprintf("- %s: %s", if (dry_run) "Would remove" else "Removed", paste(removed_labels, collapse = ", ")))
  }
  if (length(label_items) == 0) {
    label_items <- c(label_items, sprintf("- All %d up to date", nrow(plan$labels)))
  }
  lines <- c(lines, label_items, "")

  # 2. Issues
  lines <- c(lines, "Issues:")

  # Root issue
  root_num <- if (!is.null(created)) created$root else if (!is.null(plan$root)) plan$root$number else ""
  root_link <- if (ctx$connected && nzchar(root_num)) sprintf("https://github.com/%s/issues/%s", ctx$repo, root_num) else ""
  root_action <- if (is.null(plan$root)) {
    if (dry_run) "would create" else "created"
  } else {
    "unchanged"
  }
  root_desc <- if (nzchar(root_link)) sprintf("- %s (%s): %s", root_title, root_link, root_action) else sprintf("- %s: %s", root_title, root_action)
  lines <- c(lines, root_desc)

  # Checklists
  for (item in plan$checklists) {
    stage <- item$stage
    title <- checklist_title(stage)
    num <- if (!is.null(created) && stage %in% names(created$numbers)) {
      created$numbers[[stage]]
    } else if (nzchar(item$number)) {
      item$number
    } else {
      ""
    }
    link <- if (ctx$connected && nzchar(num)) sprintf("https://github.com/%s/issues/%s", ctx$repo, num) else ""
    action <- switch(item$action,
      create = if (dry_run) "would create" else "created",
      update = if (dry_run) "would update" else "updated",
      same = "unchanged"
    )
    details <- character()
    if (length(item$ticked) > 0) {
      details <- c(details, sprintf("%s: %s", if (dry_run) "would tick" else "ticked", paste(item$ticked, collapse = "; ")))
    }
    if (length(item$unticked) > 0) {
      details <- c(details, sprintf("%s: %s", if (dry_run) "would untick" else "unticked", paste(item$unticked, collapse = "; ")))
    }
    if (isTRUE(item$close)) {
      details <- c(details, if (dry_run) "would close" else "closed")
    }
    detail_str <- if (length(details)) paste0("; ", paste(details, collapse = "; ")) else ""
    item_desc <- if (nzchar(link)) {
      sprintf("- %s (%s): %s%s", title, link, action, detail_str)
    } else {
      sprintf("- %s: %s%s", title, action, detail_str)
    }
    lines <- c(lines, item_desc)
  }

  for (title in plan$closed) {
    lines <- c(lines, sprintf("- %s: left closed", title))
  }

  # 3. Still to do
  todo <- still_to_do_items(plan$checklists, connected = ctx$connected)
  if (length(todo) > 0) {
    lines <- c(lines, "", "Still to do:")
    for (item in todo) {
      lines <- c(lines, sprintf("- %s (%d):", checklist_title(item$stage), item$count))
      for (box in item$boxes) {
        lines <- c(lines, sprintf("  - %s", box))
      }
    }
  }

  lines
}

build_markdown_report <- function(ctx, plan, created = NULL, dry_run = FALSE) {
  lines <- character()
  heading <- if (dry_run) "## Set up this repository (dry run)" else "## Set up this repository"
  lines <- c(lines, heading, "", "### Labels")

  created_labels <- plan$labels$name[plan$label_action == "create"]
  updated_labels <- plan$labels$name[plan$label_action == "update"]
  removed_labels <- if (isTRUE(ctx$remove_labels)) plan$other_labels else character()
  labels_link <- if (ctx$connected) sprintf("https://github.com/%s/labels", ctx$repo) else ""

  label_items <- character()
  if (length(created_labels) > 0) {
    label_items <- c(label_items, sprintf("- **%s:** %s", if (dry_run) "Would create" else "Created", paste(sprintf("`%s`", created_labels), collapse = ", ")))
  }
  if (length(updated_labels) > 0) {
    label_items <- c(label_items, sprintf("- **%s:** %s", if (dry_run) "Would update" else "Updated", paste(sprintf("`%s`", updated_labels), collapse = ", ")))
  }
  if (length(removed_labels) > 0) {
    label_items <- c(label_items, sprintf("- **%s:** %s", if (dry_run) "Would remove" else "Removed", paste(sprintf("`%s`", removed_labels), collapse = ", ")))
  }
  if (length(label_items) == 0) {
    label_items <- c(label_items, sprintf("- All %d up to date", nrow(plan$labels)))
  }
  if (nzchar(labels_link)) {
    label_items <- c(label_items, sprintf("- [View labels](%s)", labels_link))
  }
  lines <- c(lines, label_items, "", "### Issues")

  # Root issue
  root_num <- if (!is.null(created)) created$root else if (!is.null(plan$root)) plan$root$number else ""
  root_link <- if (ctx$connected && nzchar(root_num)) sprintf("https://github.com/%s/issues/%s", ctx$repo, root_num) else ""
  root_action <- if (is.null(plan$root)) {
    if (dry_run) "would create" else "created"
  } else {
    "unchanged"
  }
  root_title_text <- if (nzchar(root_link)) sprintf("[%s](%s)", root_title, root_link) else root_title
  lines <- c(lines, sprintf("- %s: %s", root_title_text, root_action))

  # Checklists
  for (item in plan$checklists) {
    stage <- item$stage
    title <- checklist_title(stage)
    num <- if (!is.null(created) && stage %in% names(created$numbers)) {
      created$numbers[[stage]]
    } else if (nzchar(item$number)) {
      item$number
    } else {
      ""
    }
    link <- if (ctx$connected && nzchar(num)) sprintf("https://github.com/%s/issues/%s", ctx$repo, num) else ""
    action <- switch(item$action,
      create = if (dry_run) "would create" else "created",
      update = if (dry_run) "would update" else "updated",
      same = "unchanged"
    )
    details <- character()
    if (length(item$ticked) > 0) {
      details <- c(details, sprintf("%s: %s", if (dry_run) "would tick" else "ticked", paste(item$ticked, collapse = "; ")))
    }
    if (length(item$unticked) > 0) {
      details <- c(details, sprintf("%s: %s", if (dry_run) "would untick" else "unticked", paste(item$unticked, collapse = "; ")))
    }
    if (isTRUE(item$close)) {
      details <- c(details, if (dry_run) "would close" else "closed")
    }
    detail_str <- if (length(details)) paste0(" (", paste(details, collapse = "; "), ")") else ""
    title_text <- if (nzchar(link)) sprintf("[%s](%s)", title, link) else title
    lines <- c(lines, sprintf("- %s: %s%s", title_text, action, detail_str))
  }

  for (title in plan$closed) {
    lines <- c(lines, sprintf("- %s: left closed", title))
  }

  # Still to do
  todo <- still_to_do_items(plan$checklists, connected = ctx$connected)
  if (length(todo) > 0) {
    lines <- c(lines, "", "### Still to do")
    for (item in todo) {
      lines <- c(lines, sprintf("- **%s** (%d):", checklist_title(item$stage), item$count))
      for (box in item$boxes) {
        lines <- c(lines, sprintf("  - %s", box))
      }
    }
  }

  lines
}

report_setup <- function(ctx, plan, created = NULL, dry_run = FALSE) {
  summary_file <- Sys.getenv("GITHUB_STEP_SUMMARY", "")
  adds <- report_adds_something(plan, ctx)

  if (nzchar(summary_file)) {
    md <- build_markdown_report(ctx, plan, created = created, dry_run = dry_run)
    cat(paste0(paste(md, collapse = "\n"), "\n\n"), file = summary_file, append = TRUE)
  }

  if (!dry_run || adds) {
    console_lines <- build_console_report(ctx, plan, created = created, dry_run = dry_run)
    cat("\n", paste(console_lines, collapse = "\n"), "\n", sep = "")
  }
}
