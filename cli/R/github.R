# Labels, the root issue and the stage checklists. Lists what it will do, then acts on a yes. Safe to run again.
#
# A checklist line the kit writes ends in a hidden marker, <!-- kit:id -->. On a re-run the kit edits only lines that
# carry one: it refreshes the boxes it can check, leaves the boxes a person decides alone, and never touches a line
# someone else added.
root_title <- "About this repository"
checklist_title <- function(stage) sprintf("Checklist: %s", stage)
marker <- function(id) sprintf("<!-- kit:%s -->", id)
is_ticked <- function(line) grepl("^\\s*- \\[[xX]\\]", line)
is_box <- function(line) grepl("^\\s*- \\[[ xX]\\]", line)

# --- Facts about the package and its repository -------------------------------------------------------------------

find_repo <- function(args) {
  repo <- flag_value(args, "repo", Sys.getenv("GH_REPO", Sys.getenv("GITHUB_REPOSITORY")))
  if (!gh_available()) {
    return(list(connected = FALSE, why = "gh isn't installed or isn't on the PATH (https://cli.github.com)."))
  }
  signed_in <- gh(c("auth", "status"))
  if (!signed_in$ok && !nzchar(Sys.getenv("GH_TOKEN")) && !nzchar(Sys.getenv("GITHUB_TOKEN"))) {
    return(list(connected = FALSE, why = "gh isn't signed in. Run: gh auth login"))
  }
  view <- gh(c("repo", "view", if (nzchar(repo)) repo, "--json", "nameWithOwner,visibility,defaultBranchRef",
    "--jq", "[.nameWithOwner, .visibility, (.defaultBranchRef.name // \"main\")] | join(\" \")"))
  fields <- strsplit(paste(view$out, collapse = ""), " ")[[1]]
  if (!view$ok || length(fields) < 3) {
    return(list(connected = FALSE, why = "This folder isn't connected to a GitHub repository. Pass --repo owner/name, or add a remote."))
  }
  list(connected = TRUE, repo = fields[1], visibility = fields[2], branch = fields[3])
}

package_context <- function(args) {
  description <- read.dcf("DESCRIPTION", fields = c("Package", "Config/quality-gate/target"))
  found <- find_repo(args)
  repo <- if (found$connected) found$repo else ""
  public <- if (found$connected) found$visibility == "PUBLIC" else has_flag(args, "public")
  list(
    connected = found$connected,
    why = found$why,
    repo = repo,
    owner = sub("/.*", "", repo),
    branch = if (found$connected) found$branch else "main",
    package = description[1, "Package"],
    public = public,
    internal = identical(unname(description[1, "Config/quality-gate/target"]), "internal")
  )
}

# The checklists that should be open now. Internal packages never get the CRAN ones. A package on CRAN moves on to
# After acceptance and Next release.
open_stages <- function(ctx, on_cran = FALSE) {
  if (ctx$internal) {
    return(if (ctx$public) "After public" else "Before public")
  }
  if (isTRUE(on_cran)) {
    return(c("After acceptance", "Next release"))
  }
  c(if (ctx$public) "After public" else "Before public", "Before CRAN")
}

# --- A checklist's text -------------------------------------------------------------------------------------------

stage_rows <- function(stage, ctx) {
  rows <- read_list("checklists.tsv")
  keep <- rows$stage == stage &
    (rows$release == "any" | !ctx$internal) &
    (!nzchar(rows$needs) | file.exists(rows$needs))
  rows[keep, , drop = FALSE]
}

box_line <- function(row, ticked, ctx) {
  detail <- c(
    if (nzchar(row$link)) sprintf("[%s](%s)", row$where, fill_in(row$link, ctx)),
    if (nzchar(row$pick)) row$pick
  )
  detail <- if (length(detail) == 2) paste(detail, collapse = ": ") else detail
  sprintf("- [%s] %s%s %s", if (ticked) "x" else " ", row$text, if (length(detail)) sprintf(" (%s)", detail) else "", marker(row$id))
}

# Where a new box goes: after the last line of its section, or in a new section before the closing lines.
add_line <- function(lines, section, line) {
  heading <- sprintf("### %s", section)
  at <- match(heading, lines)
  if (is.na(at)) {
    return(c(lines, heading, "", line, ""))
  }
  rest <- which(startsWith(lines, "### ") & seq_along(lines) > at)
  end <- if (length(rest)) rest[1] - 1L else length(lines)
  while (end > at && !nzchar(lines[end])) end <- end - 1L
  append(lines, line, after = end)
}

# Builds a checklist's new text. Returns the lines, plus which boxes the kit ticked and unticked this time.
checklist_lines <- function(stage, ctx, old_body = "") {
  rows <- stage_rows(stage, ctx)
  lines <- if (nzchar(old_body)) strsplit(gsub("\r", "", old_body, fixed = TRUE), "\n", fixed = TRUE)[[1]] else character()
  lines <- lines[!grepl(marker("date"), lines, fixed = TRUE) & !grepl(marker("unticked"), lines, fixed = TRUE)]
  while (length(lines) > 0 && !nzchar(lines[length(lines)])) lines <- lines[-length(lines)]
  ticked <- character()
  unticked <- character()
  for (i in seq_len(nrow(rows))) {
    row <- as.list(rows[i, ])
    at <- which(grepl(marker(row$id), lines, fixed = TRUE))[1]
    if (is.na(at)) {
      state <- if (row$kind == "manual") FALSE else tick_state(row, ctx)
      lines <- add_line(lines, row$section, box_line(row, isTRUE(state), ctx))
      if (isTRUE(state)) ticked <- c(ticked, row$text)
      next
    }
    if (row$kind == "manual") next
    state <- tick_state(row, ctx)
    if (is.na(state)) next
    before <- is_ticked(lines[at])
    lines[at] <- box_line(row, state, ctx)
    if (state && !before) ticked <- c(ticked, row$text)
    if (!state && before) unticked <- c(unticked, row$text)
  }
  while (length(lines) > 0 && !nzchar(lines[length(lines)])) lines <- lines[-length(lines)]
  lines <- c(
    lines, "",
    if (length(unticked)) c(sprintf("Unticked because they stopped being true: %s. %s", paste(unticked, collapse = "; "), marker("unticked")), ""),
    sprintf("Last checked by launchR on %s. %s", format(Sys.Date()), marker("date"))
  )
  list(lines = lines, ticked = ticked, unticked = unticked)
}

box_counts <- function(lines) {
  boxes <- lines[is_box(lines)]
  c(done = sum(is_ticked(boxes)), total = length(boxes))
}

# --- What is on GitHub now ----------------------------------------------------------------------------------------

existing_issues <- function(ctx) {
  # A full listing, not a search: the search index lags, and a re-run seconds later would not find the new issue.
  out <- gh_must(c("issue", "list", "-R", ctx$repo, "--state", "all", "--limit", "1000", "--json", "number,title,state",
    "--jq", ".[] | [.number, .state, .title] | join(\"|\")"))
  if (length(out) == 0) {
    return(data.frame(number = character(), state = character(), title = character()))
  }
  parts <- regmatches(out, regexec("^([0-9]+)\\|([A-Z]+)\\|(.*)$", out))
  parts <- Filter(length, parts)
  data.frame(number = vapply(parts, `[`, "", 2), state = vapply(parts, `[`, "", 3), title = vapply(parts, `[`, "", 4))
}

# The open issue with this title, else the newest closed one.
pick_issue <- function(issues, title) {
  found <- issues[issues$title == title, , drop = FALSE]
  if (nrow(found) == 0) {
    return(NULL)
  }
  open <- found[found$state == "OPEN", , drop = FALSE]
  found <- if (nrow(open)) open else found
  as.list(found[which.max(as.integer(found$number)), ])
}

issue_body <- function(number, ctx) {
  paste(gh_must(c("issue", "view", number, "-R", ctx$repo, "--json", "body", "--jq", ".body")), collapse = "\n")
}

existing_labels <- function(ctx) {
  out <- gh_must(c("label", "list", "-R", ctx$repo, "--limit", "200", "--json", "name,color,description",
    "--jq", ".[] | [.name, .color, .description] | join(\"|\")"))
  parts <- strsplit(out, "|", fixed = TRUE)
  stats::setNames(lapply(parts, function(p) c(color = tolower(p[2]), description = if (length(p) >= 3) p[3] else "")), vapply(parts, `[`, "", 1))
}

# --- The plan -----------------------------------------------------------------------------------------------------

github_plan <- function(ctx) {
  labels <- read_list("labels.tsv")
  have <- if (ctx$connected) existing_labels(ctx) else list()
  label_action <- vapply(seq_len(nrow(labels)), function(i) {
    current <- have[[labels$name[i]]]
    if (is.null(current)) "create" else if (current[["color"]] != tolower(labels$color[i]) || current[["description"]] != labels$description[i]) "update" else "same"
  }, "")
  issues <- if (ctx$connected) existing_issues(ctx) else data.frame(number = character(), state = character(), title = character())
  root <- pick_issue(issues, root_title)
  cran <- if (ctx$internal) FALSE else on_cran(ctx$package)
  wanted <- open_stages(ctx, cran)
  stages <- unique(c(wanted, read_list("checklists.tsv")$stage))
  checklists <- list()
  for (stage in stages) {
    found <- pick_issue(issues, checklist_title(stage))
    is_open <- !is.null(found) && found$state == "OPEN"
    # A closed Next release means the release shipped, so the next one starts a fresh list. Other closed lists stay closed.
    needs_new <- stage %in% wanted && (is.null(found) || (!is_open && stage == "Next release"))
    if (!needs_new && !is_open) next
    if (ctx$internal && stage %in% c("Before CRAN", "After acceptance")) next
    old <- if (is_open) issue_body(found$number, ctx) else ""
    built <- checklist_lines(stage, ctx, old)
    counts <- box_counts(built$lines)
    changed <- !is_open || !identical(paste(built$lines, collapse = "\n"), paste(strsplit(gsub("\r", "", old, fixed = TRUE), "\n", fixed = TRUE)[[1]], collapse = "\n"))
    checklists[[stage]] <- list(
      stage = stage, number = if (is_open) found$number else "", action = if (!is_open) "create" else if (changed) "update" else "same",
      lines = built$lines, ticked = built$ticked, unticked = built$unticked, done = counts[["done"]], total = counts[["total"]],
      close = is_open && counts[["total"]] > 0 && counts[["done"]] == counts[["total"]]
    )
  }
  closed <- unique(issues$title[issues$state == "CLOSED" & startsWith(issues$title, "Checklist: ")])
  closed <- setdiff(closed, vapply(checklists, function(x) checklist_title(x$stage), ""))
  list(labels = labels, label_action = label_action, root = root, checklists = checklists, closed = closed, issues = issues)
}

print_plan <- function(ctx, plan) {
  cat(sprintf("launchR will set up %s:\n", if (ctx$connected) ctx$repo else "your repository (not connected yet)"))
  counts <- table(factor(plan$label_action, levels = c("create", "update", "same")))
  cat(sprintf("- labels: create %d, update %d, %d already right\n", counts[["create"]], counts[["update"]], counts[["same"]]))
  cat(sprintf("- the root issue \"%s\": %s\n", root_title, if (is.null(plan$root)) "create it" else sprintf("already there (#%s), left alone", plan$root$number)))
  for (item in plan$checklists) {
    what <- switch(item$action,
      create = "create it",
      update = sprintf("update #%s", item$number),
      same = sprintf("#%s is up to date", item$number)
    )
    extra <- c(
      if (length(item$ticked)) sprintf("tick %d", length(item$ticked)),
      if (length(item$unticked)) sprintf("untick %d (%s)", length(item$unticked), paste(item$unticked, collapse = ", ")),
      if (item$close) "close it, every box is ticked"
    )
    cat(sprintf("- \"%s\": %s; %d of %d boxes ticked%s\n", checklist_title(item$stage), what, item$done, item$total,
      if (length(extra)) paste0("; ", paste(extra, collapse = "; ")) else ""))
  }
  for (title in plan$closed) cat(sprintf("- \"%s\" is closed, so it is left closed\n", title))
}

# --- Doing it -----------------------------------------------------------------------------------------------------

apply_labels <- function(ctx, plan) {
  for (i in which(plan$label_action != "same")) {
    row <- plan$labels[i, ]
    gh_must(c("label", "create", row$name, "-R", ctx$repo, "--force", "--color", row$color, "--description", row$description))
    kit_pause(0.5)
  }
}

create_issue <- function(ctx, title, lines, label = "") {
  file <- body_file(lines)
  on.exit(unlink(file))
  out <- gh_must(c("issue", "create", "-R", ctx$repo, "--title", title, "--body-file", file, if (nzchar(label)) c("--label", label)))
  kit_pause(1)
  sub(".*/", "", out[length(out)])
}

edit_issue <- function(ctx, number, lines) {
  file <- body_file(lines)
  on.exit(unlink(file))
  gh_must(c("issue", "edit", number, "-R", ctx$repo, "--body-file", file))
  kit_pause(1)
}

# Makes the issue a sub-issue of the root, unless it already is.
link_sub_issue <- function(ctx, root, number, linked) {
  if (number %in% linked) {
    return(invisible())
  }
  id <- gh_must(c("api", sprintf("repos/%s/issues/%s", ctx$repo, number), "--jq", ".id"))
  gh_must(c("api", "-X", "POST", sprintf("repos/%s/issues/%s/sub_issues", ctx$repo, root), "-F", sprintf("sub_issue_id=%s", id[1])))
  kit_pause(1)
}

apply_plan <- function(ctx, plan) {
  apply_labels(ctx, plan)
  root <- if (is.null(plan$root)) {
    create_issue(ctx, root_title, c(
      "The plan for this package.", "",
      "Each checklist is a sub-issue of this one. Unticked boxes are what's left to do.",
      "Run `Rscript cli/kit.R github` from your clone of launchR again at any time to update the ticks.", "",
      marker("root")), "epic")
  } else {
    plan$root$number
  }
  linked <- gh(c("api", sprintf("repos/%s/issues/%s/sub_issues", ctx$repo, root), "--paginate", "--jq", ".[].number"))$out
  for (item in plan$checklists) {
    number <- item$number
    if (item$action == "create") {
      number <- create_issue(ctx, checklist_title(item$stage), item$lines)
    } else if (item$action == "update") {
      edit_issue(ctx, number, item$lines)
    }
    link_sub_issue(ctx, root, number, linked)
    if (item$close) {
      gh_must(c("issue", "close", number, "-R", ctx$repo, "--reason", "completed"))
      kit_pause(1)
    }
  }
  invisible(root)
}

cmd_github <- function(args) {
  if (!file.exists("DESCRIPTION")) {
    message("Run this from the package's folder.")
    return(1L)
  }
  rm(list = ls(kit_cache), envir = kit_cache)
  ctx <- package_context(args)
  if (!ctx$connected) {
    cat(ctx$why, "\n")
    if (has_flag(args, "yes")) {
      message("Nothing was changed, because there is no repository to change.")
      return(1L)
    }
    cat("Here is the plan for a", if (ctx$public) "public" else "private", "repository.\n")
  }
  result <- tryCatch(
    {
      plan <- github_plan(ctx)
      print_plan(ctx, plan)
      if (has_flag(args, "dry-run") || !ctx$connected) {
        cat("Nothing was changed.\n")
        return(0L)
      }
      if (!has_flag(args, "yes")) {
        if (ask_choice("Go ahead", c("no", "yes")) != "yes") {
          cat("Nothing was changed.\n")
          return(0L)
        }
      }
      apply_plan(ctx, plan)
      cat("Done.\n")
      0L
    },
    error = function(e) {
      message("Stopped: ", conditionMessage(e), "\nNothing is half-made that a second run can't finish.")
      1L
    }
  )
  result
}
