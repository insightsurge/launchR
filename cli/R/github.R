# Labels, the root issue and the stage checklists. Lists what it will do, then acts on a yes. Safe to run again.
#
# A checklist line launchR writes ends in a hidden marker, <!-- launchr:id -->. On a re-run launchR edits only lines that
# carry one: it refreshes the boxes it can check, leaves the boxes a person decides alone, and never touches a line
# someone else added.
root_title <- "About this repository"
checklist_title <- function(stage) sprintf("Checklist: %s", stage)
marker <- function(id) sprintf("<!-- launchr:%s -->", id)
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
  description <- read.dcf("DESCRIPTION", fields = c("Package", "Version", "Config/quality-gate/target", "Config/launchR/labels", "Config/launchR/checklists", "Config/launchR/checklist"))
  # A package made with some of launchR's labels names them; without the field it gets them all.
  chosen <- unname(description[1, "Config/launchR/labels"])
  labels <- if (is.na(chosen)) NULL else trimws(strsplit(chosen, ",", fixed = TRUE)[[1]])
  # The stage checklists a package chose; without the field it gets all but QC (so a package from before Set up was a
  # checklist gets it on its next run). A package made earlier names the QC choice "QC before release", and
  # an older one recorded only that, as Config/launchR/checklist.
  chosen_stages <- unname(description[1, "Config/launchR/checklists"])
  stages <- if (is.na(chosen_stages)) NULL else trimws(strsplit(chosen_stages, ",", fixed = TRUE)[[1]])
  if (!is.null(stages)) stages[stages == "QC before release"] <- kit_setting("qc_stage")
  # QC is sections of Next release, so choosing QC opens that list too.
  if (kit_setting("qc_stage") %in% stages) stages <- union(stages, "Next release")
  qc_old <- identical(unname(description[1, "Config/launchR/checklist"]), "QC before release")
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
    version = unname(description[1, "Version"]),
    public = public,
    remove_labels = has_flag(args, "remove-other-labels"),
    internal = identical(unname(description[1, "Config/quality-gate/target"]), "internal"),
    labels = labels,
    checklists = stages,
    qc = if (is.null(stages)) qc_old else kit_setting("qc_stage") %in% stages
  )
}

# The checklists that should be open now. Set up opens for every package, from the first run. Internal packages never
# get the CRAN ones, and their Next release opens at once. A package for CRAN moves on to After acceptance and Next
# release once it is on CRAN. Only the checklists the package chose (Config/launchR/checklists) open; without the
# field it gets all of these. QC has no list of its own: its boxes are sections of Next release (stage_rows).
open_stages <- function(ctx, on_cran = FALSE) {
  visibility <- if (ctx$public) "After public" else "Before public"
  stages <- c("Set up", if (ctx$internal) {
    c(visibility, "Next release")
  } else if (isTRUE(on_cran)) {
    c("After acceptance", "Next release")
  } else {
    c(visibility, "Before CRAN")
  })
  if (!is.null(ctx$checklists)) {
    stages <- stages[stages %in% ctx$checklists]
  } else if (isTRUE(ctx$qc) && ctx$internal) {
    stages <- setdiff(stages, "Before public") # a package from before v0.0.18: QC took the place of Before public
  }
  stages
}

# --- A checklist's text -------------------------------------------------------------------------------------------

# The rows of one checklist for this package: cran rows only for a package going to CRAN, qc rows only when it chose
# QC, rows whose needs path exists, and no box whose parent is left out.
stage_rows <- function(stage, ctx) {
  rows <- read_list("checklists.tsv")
  keep <- rows$stage == stage &
    (rows$release == "any" | (rows$release == "cran" & !ctx$internal) | (rows$release == "qc" & isTRUE(ctx$qc))) &
    (!nzchar(rows$needs) | file.exists(rows$needs))
  rows <- rows[keep, , drop = FALSE]
  rows[!nzchar(rows$parent) | rows$parent %in% rows$id, , drop = FALSE]
}

# A box under a parent box is indented by two spaces, which GitHub shows as a sub-box.
box_line <- function(row, ticked, ctx, nested = FALSE) {
  detail <- c(
    if (nzchar(row$link)) sprintf("[%s](%s)", row$where, fill_in(row$link, ctx)),
    if (nzchar(row$pick)) row$pick
  )
  detail <- if (length(detail) == 2) paste(detail, collapse = ": ") else detail
  sprintf("%s- [%s] %s%s %s", if (nested) "  " else "", if (ticked) "x" else " ", row$text, if (length(detail)) sprintf(" (%s)", detail) else "", marker(row$id))
}

# The line number of the box with this id, or NA.
box_at <- function(lines, id) which(grepl(marker(id), lines, fixed = TRUE))[1]

# Where a new box goes: under its parent box (after the parent's other sub-boxes) when parent_at is the parent's line
# number, else after the last line of its section, or in a new section before the closing lines.
add_line <- function(lines, section, line, parent_at = NA_integer_) {
  if (!is.na(parent_at)) {
    end <- parent_at
    while (end < length(lines) && grepl("^\\s+- \\[[ xX]\\]", lines[end + 1L])) end <- end + 1L
    return(append(lines, line, after = end))
  }
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

# Builds a checklist's new text. Returns the lines, plus which boxes launchR ticked and unticked this time.
checklist_lines <- function(stage, ctx, old_body = "") {
  rows <- stage_rows(stage, ctx)
  lines <- if (nzchar(old_body)) strsplit(gsub("\r", "", old_body, fixed = TRUE), "\n", fixed = TRUE)[[1]] else character()
  lines <- lines[!grepl(marker("date"), lines, fixed = TRUE) & !grepl(marker("unticked"), lines, fixed = TRUE)]
  while (length(lines) > 0 && !nzchar(lines[length(lines)])) lines <- lines[-length(lines)]
  ticked <- character()
  unticked <- character()
  # The boxes a person decides (manual) keep their line; a group's state comes from its sub-boxes, in the second pass.
  own <- rows$kind %in% c("manual", "group")
  for (i in seq_len(nrow(rows))) {
    row <- as.list(rows[i, ])
    at <- box_at(lines, row$id)
    parent_at <- if (nzchar(row$parent)) box_at(lines, row$parent) else NA_integer_
    nested <- !is.na(parent_at)
    if (is.na(at)) {
      state <- if (own[i]) FALSE else tick_state(row, ctx)
      lines <- add_line(lines, row$section, box_line(row, isTRUE(state), ctx, nested), parent_at)
      if (isTRUE(state)) ticked <- c(ticked, row$text)
      next
    }
    if (own[i]) next
    state <- tick_state(row, ctx)
    if (is.na(state)) next
    before <- is_ticked(lines[at])
    lines[at] <- box_line(row, state, ctx, nested)
    if (state && !before) ticked <- c(ticked, row$text)
    if (!state && before) unticked <- c(unticked, row$text)
  }
  # A group is ticked when every sub-box that is still in the list is ticked, and unticked otherwise. A group with no
  # sub-box left is a box a person ticks.
  for (i in which(rows$kind == "group")) {
    row <- as.list(rows[i, ])
    kids <- vapply(rows$id[rows$parent == row$id], function(id) box_at(lines, id), 1L)
    kids <- kids[!is.na(kids)]
    if (length(kids) == 0) next
    at <- box_at(lines, row$id)
    state <- all(is_ticked(lines[kids]))
    before <- is_ticked(lines[at])
    lines[at] <- box_line(row, state, ctx, nested = grepl("^\\s", lines[at]))
    if (state && !before) ticked <- c(ticked, row$text)
    if (!state && before) unticked <- c(unticked, row$text)
  }
  while (length(lines) > 0 && !nzchar(lines[length(lines)])) lines <- lines[-length(lines)]
  waiting <- unticked_required(lines, rows)
  lines <- c(
    lines, "",
    if (length(unticked)) c(sprintf("Unticked because they stopped being true: %s. %s", paste(unticked, collapse = "; "), marker("unticked")), ""),
    sprintf("Last checked by launchR on %s. %s", format(Sys.Date()), marker("date"))
  )
  list(lines = lines, ticked = ticked, unticked = unticked, waiting = waiting)
}

box_counts <- function(lines) {
  boxes <- lines[is_box(lines)]
  c(done = sum(is_ticked(boxes)), total = length(boxes))
}

# How many boxes that hold the list open are still unticked: every box except the optional ones (a box with no
# launchR marker is someone else's and counts).
unticked_required <- function(lines, rows) {
  boxes <- lines[is_box(lines)]
  ids <- ifelse(grepl("<!-- launchr:[^ ]+ -->", boxes), sub("^.*<!-- launchr:([^ ]+) -->.*$", "\\1", boxes), "")
  optional <- ids %in% rows$id[rows$optional == "yes"]
  sum(!optional & !is_ticked(boxes))
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
  parts <- strsplit(out[nzchar(out)], "|", fixed = TRUE)
  stats::setNames(lapply(parts, function(p) c(color = tolower(p[2]), description = if (length(p) >= 3) p[3] else "")), vapply(parts, `[`, "", 1))
}

# --- The plan -----------------------------------------------------------------------------------------------------

github_plan <- function(ctx) {
  labels <- read_list("labels.tsv")
  if (!is.null(ctx$labels)) labels <- labels[labels$name %in% ctx$labels, , drop = FALSE]
  have <- if (ctx$connected) existing_labels(ctx) else list()
  label_action <- vapply(seq_len(nrow(labels)), function(i) {
    current <- have[[labels$name[i]]]
    if (is.null(current)) "create" else if (current[["color"]] != tolower(labels$color[i]) || current[["description"]] != labels$description[i]) "update" else "same"
  }, "")
  # Labels that aren't launchR's, such as GitHub's own and the person's: kept unless they ask to remove them. GitHub
  # matches label names ignoring case, and Dependabot's labels are always kept.
  other_labels <- names(have)[!tolower(names(have)) %in% tolower(c(labels$name, "dependencies", "github_actions"))]
  issues <- if (ctx$connected) existing_issues(ctx) else data.frame(number = character(), state = character(), title = character())
  root <- pick_issue(issues, root_title)
  cran <- if (ctx$internal) FALSE else on_cran(ctx$package, if (ctx$connected) ctx$repo else NA_character_)
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
      close = is_open && counts[["total"]] > 0 && built$waiting == 0
    )
  }
  closed <- unique(issues$title[issues$state == "CLOSED" & startsWith(issues$title, "Checklist: ")])
  closed <- setdiff(closed, vapply(checklists, function(x) checklist_title(x$stage), ""))
  list(labels = labels, label_action = label_action, other_labels = other_labels, root = root, checklists = checklists, closed = closed, issues = issues)
}

print_plan <- function(ctx, plan) {
  cat(sprintf("launchR will set up %s:\n", if (ctx$connected) ctx$repo else "your repository (not connected yet)"))
  counts <- table(factor(plan$label_action, levels = c("create", "update", "same")))
  cat(sprintf("- labels: create %d, update %d, %d already right\n", counts[["create"]], counts[["update"]], counts[["same"]]))
  if (length(plan$other_labels) > 0) {
    cat(sprintf("- other labels (%s): %s\n", paste(plan$other_labels, collapse = ", "),
      if (ctx$remove_labels) "remove them" else "kept; --remove-other-labels removes them"))
  }
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
  if (ctx$remove_labels) {
    for (name in plan$other_labels) {
      gh_must(c("label", "delete", name, "-R", ctx$repo, "--yes"))
      kit_pause(0.5)
    }
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
      "To update the ticks, run the \"Set up this repository\" workflow again, or run this in R from the package's folder:", "",
      sprintf("`source(\"https://raw.githubusercontent.com/insightsurge/launchR/v%s/cli/github-setup.R\")`", kit_setting("kit_version")), "",
      marker("root")), if (is.null(ctx$labels) || "epic" %in% ctx$labels) "epic" else "")
  } else {
    plan$root$number
  }
  linked <- gh(c("api", sprintf("repos/%s/issues/%s/sub_issues", ctx$repo, root), "--paginate", "--jq", ".[].number"))$out
  numbers <- character()
  for (item in plan$checklists) {
    number <- item$number
    if (item$action == "create") {
      number <- create_issue(ctx, checklist_title(item$stage), item$lines)
    } else if (item$action == "update") {
      edit_issue(ctx, number, item$lines)
    }
    numbers[[item$stage]] <- as.character(number)
    link_sub_issue(ctx, root, number, linked)
    if (item$close) {
      gh_must(c("issue", "close", number, "-R", ctx$repo, "--reason", "completed"))
      kit_pause(1)
    }
  }
  invisible(list(root = as.character(root), numbers = numbers))
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
        report_setup(ctx, plan, dry_run = TRUE)
        cat("Nothing was changed.\n")
        return(0L)
      }
      if (!has_flag(args, "yes")) {
        if (ask_choice("Go ahead", c("no", "yes")) != "yes") {
          report_setup(ctx, plan, dry_run = TRUE)
          cat("Nothing was changed.\n")
          return(0L)
        }
      }
      created <- apply_plan(ctx, plan)
      report_setup(ctx, plan, created = created, dry_run = FALSE)
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
