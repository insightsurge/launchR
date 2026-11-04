# Tests for the command line, in base R. Run from anywhere:  Rscript tests/cli-tests.R
# The GitHub parts run against tests/fake-gh/gh, so nothing leaves this computer and no repository is touched.
here <- if (exists("test_dir")) test_dir else dirname(normalizePath(sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1])))
kit_root <- dirname(here)
for (file in list.files(file.path(kit_root, "cli", "R"), pattern = "[.]R$", full.names = TRUE)) sys.source(file, envir = globalenv())
options(kit.root = kit_root, kit.pause = 0, kit.retry_wait = 0)

failures <- character()
expect <- function(ok, label) {
  ok <- isTRUE(ok)
  cat(if (ok) "  ok    " else "  FAIL  ", label, "\n", sep = "")
  if (!ok) failures <<- c(failures, label)
}
section <- function(title) cat("\n", title, "\n", sep = "")
# Runs code, keeping what it prints and the messages it sends.
quiet <- function(code) {
  messages <- character()
  value <- NULL
  out <- capture.output(value <- withCallingHandlers(code, message = function(m) {
    messages <<- c(messages, conditionMessage(m))
    invokeRestart("muffleMessage")
  }))
  list(value = value, out = c(out, messages))
}

rscript <- file.path(R.home("bin"), "Rscript")
work <- tempfile("kit-tests")
dir.create(work)
on.exit(unlink(work, recursive = TRUE), add = TRUE)
home <- file.path(work, "home")
dir.create(home)
writeLines(c("[user]", "  name = Test Person", "  email = test@example.com"), file.path(home, ".gitconfig"))
Sys.setenv(HOME = home, GIT_CONFIG_GLOBAL = file.path(home, ".gitconfig"), GH_REPO = "", GITHUB_REPOSITORY = "", GH_TOKEN = "", GITHUB_TOKEN = "")
old_path <- Sys.getenv("PATH")

new_package <- function(name = "samplepkg", ..., git = FALSE) {
  out <- file.path(work, paste0(name, "-", length(list.files(work))))
  args <- c(name, "--yes", "--title", "Sample Tools", "--author", "Asha Rao", "--email", "a@example.com",
    "--owner", "sample-org", "--preset", "everything", "--path", out, if (!git) "--no-git", ...)
  status <- quiet(cmd_new(args))$value
  stopifnot(status == 0L)
  out
}

# A fake GitHub: returns its folder. Settings and CI answers are canned the way gh would print them.
fake_github <- function(visibility = "PRIVATE", settings_ok = TRUE, token_visible = TRUE) {
  dir <- tempfile("fake-github", work)
  dir.create(file.path(dir, "api"), recursive = TRUE)
  writeLines(paste("sample-org/samplepkg", visibility, "main"), file.path(dir, "repo.txt"))
  writeLines(character(), file.path(dir, "issues.txt"))
  writeLines(character(), file.path(dir, "labels.txt"))
  writeLines(character(), file.path(dir, "subs.txt"))
  repo <- list(
    name = "samplepkg", description = "Sample", topics = list("r"),
    allow_squash_merge = TRUE, allow_merge_commit = !settings_ok, allow_rebase_merge = FALSE, delete_branch_on_merge = TRUE,
    security_and_analysis = list(secret_scanning = list(status = "enabled"), secret_scanning_push_protection = list(status = "enabled"))
  )
  writeLines(sprintf(
    '{"name":"samplepkg","description":"Sample","topics":["r"],"allow_squash_merge":true,"allow_merge_commit":%s,"allow_rebase_merge":false,"delete_branch_on_merge":true,"security_and_analysis":{"secret_scanning":{"status":"enabled"},"secret_scanning_push_protection":{"status":"enabled"}}}',
    if (settings_ok) "false" else "true"), file.path(dir, "api", "repo.json"))
  if (token_visible) writeLines('{"default_workflow_permissions":"read"}', file.path(dir, "api", "actions_permissions_workflow.json"))
  writeLines('[{"type":"deletion"},{"type":"non_fast_forward"}]', file.path(dir, "api", "rules_branches_main.json"))
  writeLines('{"total_count":1,"check_runs":[{"status":"completed","conclusion":"success"}]}', file.path(dir, "api", "commits_main_check_runs_per_page_100.json"))
  writeLines('{"enabled":true}', file.path(dir, "api", "private_vulnerability_reporting.json"))
  writeLines('{"html_url":"https://sample-org.github.io/samplepkg/","build_type":"workflow"}', file.path(dir, "api", "pages.json"))
  dir
}

use_fake <- function(dir) {
  Sys.setenv(PATH = paste(file.path(here, "fake-gh"), old_path, sep = .Platform$path.sep), FAKE_GH_DIR = dir, FAKE_GH_SIGNED_OUT = "", FAKE_GH_RATE_LIMIT = "")
}
log_lines <- function(dir) if (file.exists(file.path(dir, "log.txt"))) readLines(file.path(dir, "log.txt")) else character()
writes <- function(lines) lines[grepl("^(issue (create|edit|close)|label (create|delete)|api -X POST)", lines)]
issues <- function(dir) readLines(file.path(dir, "issues.txt"))
body <- function(dir, n) readLines(file.path(dir, sprintf("body-%d.md", n)))

run_github <- function(package, dir, ..., http = function(url) 404L) invisible(run_github_(package, dir, ..., http = http))
run_github_ <- function(package, dir, ..., http = function(url) 404L) {
  use_fake(dir)
  options(kit.http = http)
  old <- setwd(package)
  on.exit(setwd(old), add = TRUE)
  quiet(cmd_github(c(...)))
}

# --- Small functions ---------------------------------------------------------------------------------------------
section("Names, quoting, line endings")
expect(check_package_name("a") != "", "one-letter names are refused")
expect(check_package_name("9abc") != "", "names must start with a letter")
expect(check_package_name("abc.") != "", "names can't end in a dot")
expect(check_package_name("a-b") != "", "dashes are refused")
expect(check_package_name("My.pkg2") == "", "letters, digits and dots are accepted")
expect(quote_arg("a b", windows = FALSE) == "'a b'", "sh quoting wraps in single quotes")
expect(quote_arg("a b", windows = TRUE) == "\"a b\"", "cmd quoting wraps in double quotes")
expect(grepl("\\\"", quote_arg("say \"hi\"", windows = TRUE), fixed = TRUE), "cmd quoting escapes double quotes for gh")
crlf <- tempfile()
writeBin(charToRaw("one\r\ntwo\r\n"), crlf)
expect(read_text(crlf) == "one\ntwo\n", "text with Windows line endings is read as \\n")
expect(all(c("id", "stage", "kind", "needs", "link", "pick") %in% names(read_list("checklists.tsv"))), "checklists.tsv has its columns")
rows <- read_list("checklists.tsv")
expect(!anyDuplicated(rows$id), "every checklist row has its own id")
kit_versions <- c(
  settings = kit_setting("kit_version"),
  description = sub("^Version: *", "", grep("^Version:", readLines(file.path(kit_root, "cli", "DESCRIPTION")), value = TRUE)),
  setup = sub('^.*version <- "([^"]*)".*$', "\\1", grep('^ *version <- "', readLines(file.path(kit_root, "cli", "github-setup.R")), value = TRUE)[1])
)
expect(length(unique(kit_versions)) == 1, paste("the version is the same in settings.tsv, cli/DESCRIPTION and github-setup.R:", toString(kit_versions)))
expect(all(rows$kind %in% c("file", "placeholder", "setting", "ci", "site", "cran", "description", "manual", "platforms")), "only the decided check kinds are used")
expect(all(nzchar(rows$id[rows$kind == "setting"]) & nzchar(rows$link[rows$kind == "setting"]) & nzchar(rows$pick[rows$kind == "setting"])), "every settings box has a link and a value to pick")

# --- cmd_new ------------------------------------------------------------------------------------------------------
section("Template files are in git")
# A file the lists name but git doesn't track is missing from a clean checkout, so the site's zip can't be built there
# (a .gitignore inside template/ can hide one, as it did .Renviron).
listed <- file.path("template", read_list("files.tsv")$path)
tracked <- system2("git", c("-C", quote_arg(kit_root), "ls-files", "--", "template"), stdout = TRUE)
expect(all(listed %in% tracked), paste("every template file in files.tsv is in git:", toString(setdiff(listed, tracked))))

section("The Modify lists agree")
forms <- read_list("forms.tsv")
files <- read_list("files.tsv")
expect(all(file.path(".github", "ISSUE_TEMPLATE", forms$file) %in% files$path), "every form in forms.tsv is in files.tsv")
expect(all(paste0("form_", forms$key) %in% files$needs), "files.tsv includes each form only when it is chosen")
expect(all(forms$label %in% read_list("labels.tsv")$name), "every form's label is in labels.tsv")
expect(all(forms$part %in% read_list("parts.tsv")$part), "every form's part is a part")
checks <- read_list("checks.tsv")$key
needs <- unlist(strsplit(read_list("badges.tsv")$needs, ",", fixed = TRUE))
expect(all(needs %in% c("owner", "cran", checks)), "every badge need is owner, cran or a check")
expect(kit_setting("qc_stage") %in% read_list("checklists.tsv")$stage, "the QC checklist has rows")

section("launchr.R new")
expect(quiet(cmd_new(character()))$value == 1L, "new without a name fails")
expect(quiet(cmd_new("1bad"))$value == 1L, "new with a bad name fails")
steps <- quiet(cmd_new(c("stepspkg", "--yes", "--owner", "sample-org", "--plan", "c", "--path", file.path(work, "stepspkg"), "--no-git")))
expect(any(grepl("usethis::use_github(organisation = \"sample-org\", private = TRUE)", steps$out, fixed = TRUE)) && any(grepl("pak::local_install_dev_deps()", steps$out, fixed = TRUE)) && any(grepl("Set up this repository", steps$out, fixed = TRUE)) &&
  any(grepl("install.packages(c(\"devtools\", \"gitcreds\", \"pak\"))", steps$out, fixed = TRUE)) && any(grepl("gitcreds::gitcreds_set()", steps$out, fixed = TRUE)) && any(grepl("Only show what would change", steps$out, fixed = TRUE)),
  "new prints the next steps, with the organisation line and the plan's visibility")
expect(!any(grepl("^Next:", quiet(cmd_new(c("stepspkg", "--yes", "--path", file.path(work, "stepspkg2"))))$out)), "no next steps when new failed")
expect(any(grepl("usethis::use_git()", steps$out, fixed = TRUE)), "with --no-git the next steps start with use_git()")
pkg <- new_package()
expect(file.exists(file.path(pkg, "DESCRIPTION")) && file.exists(file.path(pkg, ".github", "workflows", "github-setup.yaml")), "new writes the package, hidden folders included")
expect(!grepl("\r", read_text(file.path(pkg, "DESCRIPTION")), fixed = TRUE), "generated files use \\n line endings")
made <- list.files(pkg, recursive = TRUE, all.files = TRUE)
expect(!any(grepl("template-LICENSE", made)) && !("template-LICENSE" %in% read_list("files.tsv")$path), "the template's own licence never reaches a generated package")
expect(!any(grepl("Zero-Clause", vapply(file.path(pkg, made), read_text, ""), fixed = TRUE)), "no generated file carries the template's licence text")
expect(quiet(cmd_new(c("samplepkg", "--yes", "--path", pkg, "--no-git")))$value == 1L, "new refuses a folder that already has files")
git_pkg <- new_package("gitpkg", git = TRUE)
expect(!any(grepl("usethis::use_git()", quiet(cmd_new(c("nextpkg", "--yes", "--owner", "sample-org", "--path", file.path(work, "nextpkg"))))$out, fixed = TRUE)), "after a first commit the next steps skip use_git()")
expect(dir.exists(file.path(git_pkg, ".git")), "new makes the first commit when git is there")
expect(identical(system2("git", c("-C", quote_arg(git_pkg), "log", "-1", "--format=%an"), stdout = TRUE), "Test Person"), "the first commit is under the person's own git name")
expect(!grepl("Co-authored", paste(system2("git", c("-C", quote_arg(git_pkg), "log", "-1", "--format=%B"), stdout = TRUE), collapse = "\n"), ignore.case = TRUE), "the first commit has no trailer")
writeLines(c("[user]", "  name = Claude", "  email = x@example.com"), file.path(home, ".gitconfig-ai"))
Sys.setenv(GIT_CONFIG_GLOBAL = file.path(home, ".gitconfig-ai"))
ai <- quiet(new_package("aipkg", git = TRUE))
expect(dir.exists(file.path(work, list.files(work, pattern = "^aipkg"), ".git")), "new makes the first commit whatever the git name is")
Sys.setenv(GIT_CONFIG_GLOBAL = file.path(home, ".gitconfig"))
Sys.setenv(PATH = "/nonexistent")
nogit <- quiet(cmd_new(c("nogitpkg", "--yes", "--owner", "sample-org", "--path", file.path(work, "nogitpkg"))))
Sys.setenv(PATH = old_path)
expect(any(grepl("git isn't installed", nogit$out)), "new says so when git is absent")
expect(file.exists(file.path(work, "nogitpkg", "DESCRIPTION")) && nogit$value == 0L, "package files exist even when git is absent")
noowner <- quiet(cmd_new(c("noownerpkg", "--yes", "--no-git", "--path", file.path(work, "noownerpkg"))))
expect(noowner$value == 1L && !dir.exists(file.path(work, "noownerpkg")), "new --yes needs --owner")
expect(nzchar(check_owner("https://github.com/sample-org")) && !nzchar(check_owner("sample-org")), "a link isn't a GitHub name")
nopath <- quiet(kit_main(c("new", "nopathpkg", "--yes", "--owner", "sample-org", "--no-git", "--path")))
expect(nopath$value == 1L && any(grepl("--path needs a value", nopath$out)) && !dir.exists("NA"), "a flag without a value stops with a message")
badtitle <- quiet(cmd_new(c("quotepkg", "--yes", "--owner", "sample-org", "--title", 'Say "hi"', "--no-git", "--path", file.path(work, "quotepkg"))))
expect(badtitle$value == 1L && !dir.exists(file.path(work, "quotepkg")), "a title R can't hold is refused")
badpreset <- quiet(cmd_new(c("presetpkg", "--yes", "--owner", "sample-org", "--preset", "bogus", "--no-git", "--path", file.path(work, "presetpkg"))))
expect(badpreset$value == 1L && any(grepl("--preset is one of", badpreset$out)), "an unknown preset is named, not a stack trace")
plan_d <- new_package("plandpkg", "--plan", "d")
expect(!file.exists(file.path(plan_d, ".github", "workflows", "r-cmd-check-extended.yaml")) &&
  any(grepl("target: internal", readLines(file.path(plan_d, "DESCRIPTION")))), "plan d is private and internal, without r-cmd-check-extended")
min_r <- new_package("minrpkg", "--min-r", "4.3")
expect(any(grepl("R (>= 4.3.0)", readLines(file.path(min_r, "DESCRIPTION")), fixed = TRUE)), "the minimum R version reaches DESCRIPTION")
min_r_flows <- unlist(lapply(list.files(file.path(min_r, ".github", "workflows"), "[.]yaml$", full.names = TRUE), readLines))
expect(!any(grepl("^ *platforms:.*/4[.]1", min_r_flows)) && any(grepl("platforms: ubuntu/release, ubuntu/4.3", min_r_flows, fixed = TRUE)),
  "no check runs on an R older than the oldest R chosen")
private_min_r <- new_package("privminrpkg", "--plan", "c", "--min-r", "4.4")
expect(any(grepl("platforms: ubuntu/release, ubuntu/oldrel-1, ubuntu/4.4", readLines(file.path(private_min_r, ".github", "workflows", "r-cmd-check.yaml")), fixed = TRUE)),
  "a private package checks its oldest R on Linux, as the site does")
described <- read.dcf(file.path(new_package("descpkg", "--description", "Builds  tables for reports"), "DESCRIPTION"))
expect(identical(unname(described[1, "Description"]), "Builds tables for reports."), "--description fills DESCRIPTION's Description, ending in a full stop")
plain_description <- read.dcf(file.path(new_package("plaindescpkg"), "DESCRIPTION"))
expect(identical(unname(plain_description[1, "Description"]), "Sample Tools."), "without --description, Description repeats the title")
expect(nzchar(check_description("This package builds tables.", "descpkg")) && nzchar(check_description("descpkg builds tables.", "descpkg")) &&
  nzchar(check_description('Say "hi".')) && !nzchar(check_description("")) && !nzchar(check_description("Builds tables.", "descpkg")),
  "a description that starts with the name or \"This package\", or holds quotes, is refused; an empty one is fine")
expect(nzchar(check_description("A package for clinical tables.")) && nzchar(check_description("The package builds tables.")) &&
  nzchar(check_description("builds tables for reports.")) && !nzchar(check_description("'Shiny' apps for tables.")),
  "a description R CMD check --as-cran would note (A/The package, a lower-case start) is refused")
expect(nzchar(check_min_r("4.4.1")) && nzchar(check_min_r("4.10")) && nzchar(check_min_r("4.0")) && !nzchar(check_min_r("4.4")), "the oldest R is x.y, one digit each, from 4.1 on")
owned <- read.dcf(file.path(new_package("ownedpkg"), "DESCRIPTION"))
expect(identical(unname(owned[1, "BugReports"]), "https://github.com/sample-org/ownedpkg/issues"), "DESCRIPTION has BugReports from the start")
expect(nzchar(check_package_name("stats")) && nzchar(check_package_name(strrep("a", 61))), "a base R name or a very long name is refused")
digits <- readLines(file.path(new_package("demo2pkg"), "inst", "WORDLIST"))
expect(identical(digits, c("CMD", "CRAN", "Codecov", "Lifecycle", "demo2pkg", "demo", "pkg", "launchR")), "a name with a digit puts its parts in the word list")
lint_caller <- readLines(file.path(work, "nogitpkg", ".github", "workflows", "lint.yaml"))
expect(any(grepl("branches: [main, master]", lint_caller, fixed = TRUE)), "the checks run for main and master")

# --- Checklist text -----------------------------------------------------------------------------------------------
section("Checklist merging (no network)")
ctx <- list(connected = FALSE, repo = "sample-org/samplepkg", owner = "sample-org", branch = "main", package = "samplepkg", public = FALSE, internal = FALSE)
old <- setwd(pkg)
options(kit.http = function(url) NA_integer_)
first <- checklist_lines("Before public", ctx)
text <- paste(first$lines, collapse = "\n")
expect(grepl("- \\[x\\] Licence is in place <!-- launchr:licence -->", text), "a file that exists is ticked")
expect(grepl("- \\[ \\] Example function replaced with your own", text), "an unchanged placeholder stays unticked")
expect(grepl("[Settings, General](https://github.com/sample-org/samplepkg/settings)", text, fixed = TRUE), "settings boxes link to the right page")
expect(grepl("untick Allow merge commits", text, fixed = TRUE), "settings boxes say the value to pick")
expect(grepl("launchr:date", text, fixed = TRUE), "the date line is there")
# a person ticks a judgement box, adds a line of their own, and a file goes missing
edited <- sub("- [ ] Search the history", "- [x] Search the history", first$lines, fixed = TRUE)
edited <- append(edited, "- [ ] My own extra step", after = which(startsWith(edited, "### Repository")) + 2L)
invisible(file.rename("LICENSE", "LICENSE.bak"))
second <- checklist_lines("Before public", ctx, paste(edited, collapse = "\n"))
invisible(file.rename("LICENSE.bak", "LICENSE"))
expect(identical(second$unticked, "Licence is in place"), "a file that went missing is unticked and named")
expect(any(grepl("Unticked because they stopped being true: Licence is in place", second$lines)), "the unticked box is named in the issue")
expect(any(grepl("- [x] Search the history for secrets before going public", second$lines, fixed = TRUE)), "a judgement box a person ticked stays ticked")
expect("- [ ] My own extra step" %in% second$lines, "a line the kit didn't write is left alone")
third <- checklist_lines("Before public", ctx, paste(second$lines, collapse = "\n"))
expect(identical(third$lines, checklist_lines("Before public", ctx, paste(third$lines, collapse = "\n"))$lines), "running again changes nothing")
# a box that can't be checked (no access) keeps its tick
manual <- sub("- [ ] Squash merge", "- [x] Squash merge", first$lines, fixed = TRUE)
kept <- checklist_lines("Before public", ctx, paste(manual, collapse = "\n"))
expect(any(grepl("^- \\[x\\] Squash merge only", kept$lines)), "a box the kit can't read is left as it is")
# a new row in the kit's list is added to its section
short <- first$lines[!grepl("launchr:history", first$lines, fixed = TRUE)]
added <- checklist_lines("Before public", ctx, paste(short, collapse = "\n"))
expect(any(grepl("launchr:history", added$lines, fixed = TRUE)) && which(grepl("launchr:history", added$lines, fixed = TRUE)) < which(startsWith(added$lines, "### CI")), "a box new to the list is added inside its section")
# the Description box is ticked only once Description says more than the Title
desc_row <- list(kind = "description", target = "DESCRIPTION")
expect(identical(tick_state(desc_row, ctx), FALSE), "a Description that repeats the Title leaves its box unticked")
dcf <- read.dcf("DESCRIPTION")
dcf[1, "Description"] <- "Builds tables for clinical reports from analysis datasets."
write.dcf(dcf, "DESCRIPTION")
expect(identical(tick_state(desc_row, ctx), TRUE), "a written Description ticks its box")
# the platforms box ticks itself once the caller lists a Windows and a Mac system
plat <- tempfile(); dir.create(file.path(plat, ".github", "workflows"), recursive = TRUE)
plat_file <- file.path(plat, ".github", "workflows", "r-cmd-check.yaml")
plat_row <- list(kind = "platforms", target = plat_file)
expect(is.na(tick_state(plat_row, list(connected = FALSE))), "platforms: no file leaves the box alone")
writeLines(c("with:", "  platforms: ubuntu/release"), plat_file)
expect(identical(tick_state(plat_row, list(connected = FALSE)), FALSE), "platforms: Linux only is not ticked")
writeLines(c("with:", "  platforms: ubuntu/release, macos/release, windows/release"), plat_file)
expect(identical(tick_state(plat_row, list(connected = FALSE)), TRUE), "platforms: Windows and Mac tick the box")
writeLines(c("with:", "  platforms: >-", "    ubuntu/release", "    macos/release,", "    windows/4.1", "  timeout-minutes: 0"), plat_file)
expect(identical(tick_state(plat_row, list(connected = FALSE)), TRUE), "platforms: a multi-line value ticks")
writeLines(c("with:", "  platforms: ubuntu/release  # later: macos/release, windows/release"), plat_file)
expect(identical(tick_state(plat_row, list(connected = FALSE)), FALSE), "platforms: a comment does not tick")
# the website box only appears when the package has a website
expect(!any(grepl("launchr:site", checklist_lines("After public", ctx)$lines, fixed = TRUE)) == !file.exists("_pkgdown.yml"), "website boxes appear only with a website")
setwd(old)

section("Which checklists open")
expect(identical(open_stages(modifyList(ctx, list(public = FALSE))), c("Before public", "Before CRAN")), "private: Before public and Before CRAN")
expect(identical(open_stages(modifyList(ctx, list(public = TRUE))), c("After public", "Before CRAN")), "public: After public and Before CRAN")
expect(identical(open_stages(ctx, on_cran = TRUE), c("After acceptance", "Next release")), "on CRAN: After acceptance and Next release")
expect(identical(open_stages(modifyList(ctx, list(internal = TRUE))), "Before public"), "internal packages get no CRAN checklists")
internal_rows <- stage_rows("Before public", modifyList(ctx, list(internal = TRUE)))
expect(all(internal_rows$release == "any"), "internal packages get no CRAN boxes")

# --- With the fake GitHub -----------------------------------------------------------------------------------------
section("First run against a fake GitHub")
pkg <- new_package()
fake <- fake_github()
dry <- run_github(pkg, fake, "--dry-run")
expect(dry$value == 0L && length(writes(log_lines(fake))) == 0L, "--dry-run changes nothing")
expect(any(grepl("labels: create 11", dry$out)), "the dry run counts the labels")
first_run <- run_github(pkg, fake, "--yes")
expect(first_run$value == 0L, "--yes exits 0")
expect(length(readLines(file.path(fake, "labels.txt"))) == 11L, "all labels exist")
some <- new_package("somelabels", "--forms", "bug", "--labels", "priority: high")
fake_some <- fake_github()
run_github(some, fake_some, "--yes")
expect(identical(sort(sub("[|].*", "", readLines(file.path(fake_some, "labels.txt")))), c("bug", "priority: high")),
  "a package made with some labels gets those and its forms' labels")
expect(identical(sub("^[0-9]+\\|OPEN\\|", "", issues(fake)), c(root_title, "Checklist: Before public", "Checklist: Before CRAN")), "the root issue and two checklists are created")
expect(setequal(readLines(file.path(fake, "subs.txt")), c("2", "3")), "both checklists are sub-issues of the root")
expect(any(grepl("launchr:licence", body(fake, 2), fixed = TRUE)) && any(grepl("^- \\[x\\] Licence", body(fake, 2))), "the checklist body has its ticked boxes")
expect(any(grepl("^- \\[x\\] Squash merge only", body(fake, 2))), "a GitHub setting that holds is ticked")
expect(any(grepl("^- \\[x\\] Workflow token set to read-only", body(fake, 2))), "the workflow token setting is read through gh api")
section("Second run")
before <- length(log_lines(fake))
second_run <- run_github(pkg, fake, "--yes")
expect(second_run$value == 0L && length(writes(log_lines(fake)[-seq_len(before)])) == 0L, "a second run writes nothing")
expect(length(issues(fake)) == 3L, "a second run makes no duplicates")
expect(any(grepl("is up to date", second_run$out)), "a second run says what is up to date")
section("Unticking and judgement boxes")
invisible(file.rename(file.path(pkg, "LICENSE"), file.path(pkg, "LICENSE.bak")))
mine <- sub("- [ ] Search the history", "- [x] Search the history", body(fake, 2), fixed = TRUE)
writeLines(mine, file.path(fake, "body-2.md"))
third_run <- run_github(pkg, fake, "--yes")
invisible(file.rename(file.path(pkg, "LICENSE.bak"), file.path(pkg, "LICENSE")))
expect(any(grepl("^- \\[ \\] Licence is in place", body(fake, 2))), "a missing file is unticked on GitHub")
expect(any(grepl("untick 1", third_run$out)), "the plan names what it will untick")
expect(any(grepl("^- \\[x\\] Search the history", body(fake, 2))), "a judgement box ticked by a person is untouched")
section("Labels that aren't launchR's")
fake_labels <- fake_github()
writeLines(c("question|d876e3|Further information is requested", "wontfix|ffffff|This will not be worked on"), file.path(fake_labels, "labels.txt"))
dry_remove <- run_github(pkg, fake_labels, "--dry-run", "--remove-other-labels")
expect(dry_remove$value == 0L && length(writes(log_lines(fake_labels))) == 0L && any(grepl("question, wontfix): remove them", dry_remove$out, fixed = TRUE)),
  "--dry-run --remove-other-labels names the labels and deletes nothing")
kept_run <- run_github(pkg, fake_labels, "--yes")
expect(any(grepl("other labels (question, wontfix): kept", kept_run$out, fixed = TRUE)) &&
  all(c("question", "wontfix") %in% sub("[|].*", "", readLines(file.path(fake_labels, "labels.txt")))), "GitHub's own labels are kept by default, and named")
removed_run <- run_github(pkg, fake_labels, "--yes", "--remove-other-labels")
left <- sub("[|].*", "", readLines(file.path(fake_labels, "labels.txt")))
expect(removed_run$value == 0L && !any(c("question", "wontfix") %in% left) && length(left) == 11L, "--remove-other-labels removes them and keeps launchR's eleven")
writeLines(c(readLines(file.path(fake_labels, "labels.txt")), "dependencies|0366d6|Dependabot", "Epic|3e4b9e|Same name, other case"), file.path(fake_labels, "labels.txt"))
run_github(pkg, fake_labels, "--yes", "--remove-other-labels")
left <- sub("[|].*", "", readLines(file.path(fake_labels, "labels.txt")))
expect(all(c("dependencies", "Epic") %in% left), "Dependabot's label is kept, and a launchR label in other case isn't taken for another")
section("Settings that don't hold, or can't be read")
fake2 <- fake_github(settings_ok = FALSE, token_visible = FALSE)
run_github(pkg, fake2, "--yes")
expect(any(grepl("^- \\[ \\] Squash merge only", body(fake2, 2))), "a setting that is wrong stays unticked")
expect(any(grepl("^- \\[ \\] Workflow token", body(fake2, 2))), "a setting gh can't read is left unticked, not guessed")
writeLines(sub("- [ ] Workflow token", "- [x] Workflow token", body(fake2, 2), fixed = TRUE), file.path(fake2, "body-2.md"))
run_github(pkg, fake2, "--yes")
expect(any(grepl("^- \\[x\\] Workflow token", body(fake2, 2))), "a tick the kit can't verify is not removed")
section("Public, internal and on CRAN")
fake3 <- fake_github("PUBLIC")
run_github(pkg, fake3, "--yes")
expect(identical(sub("^[0-9]+\\|OPEN\\|", "", issues(fake3)), c(root_title, "Checklist: After public", "Checklist: Before CRAN")), "a public repository gets After public")
expect(any(grepl("^- \\[x\\] Private vulnerability reporting on", body(fake3, 2))), "a setting read from an enabled flag is ticked")
expect(any(grepl("^- \\[x\\] The website is live", body(fake3, 2))) == FALSE, "the website box is not ticked when the site doesn't answer")
run_github(pkg, fake3, "--yes", http = function(url) 200L)
expect(any(grepl("^- \\[x\\] The website is live", body(fake3, 2))), "the website box ticks when the site answers")
internal <- new_package("internalpkg", "--internal")
fake4 <- fake_github()
run_github(internal, fake4, "--yes")
expect(identical(sub("^[0-9]+\\|OPEN\\|", "", issues(fake4)), c(root_title, "Checklist: QC before release")), "a private internal package gets the QC checklist, and no CRAN one")
expect(any(grepl("Coverage is at or above the limit", body(fake4, 2))), "the QC checklist has its boxes")
no_qc <- new_package("noqcpkg", "--internal", "--no-qc")
fake4b <- fake_github()
run_github(no_qc, fake4b, "--yes")
expect(identical(sub("^[0-9]+\\|OPEN\\|", "", issues(fake4b)), c(root_title, "Checklist: Before public")), "without the QC checklist, a private internal package gets Before public")
fake_other <- fake_github("PUBLIC")
options(kit.http_text = function(url) "<td>URL:</td><td>https://github.com/someone-else/samplepkg</td>")
run_github(pkg, fake_other, "--yes", http = function(url) if (grepl("cran.r-project", url)) 200L else 404L)
expect(!"Checklist: After acceptance" %in% sub("^[0-9]+\\|OPEN\\|", "", issues(fake_other)), "another author's package with the same name on CRAN doesn't count as this one")
options(kit.http_text = function(url) "<td>URL:</td><td>https://github.com/sample-org/samplepkg</td>")
fake5 <- fake_github("PUBLIC")
run_github(pkg, fake5, "--yes", http = function(url) if (grepl("cran.r-project", url)) 200L else 404L)
expect(all(c("Checklist: After acceptance", "Checklist: Next release") %in% sub("^[0-9]+\\|OPEN\\|", "", issues(fake5))), "a package on CRAN gets After acceptance and Next release")
section("A closed Next release")
rows <- issues(fake5)
next_at <- grep("Next release", rows)
writeLines(sub("\\|OPEN\\|", "|CLOSED|", rows), file.path(fake5, "issues.txt"))
rows <- issues(fake5)
run_github(pkg, fake5, "--yes", http = function(url) if (grepl("cran.r-project", url)) 200L else 404L)
rows <- issues(fake5)
expect(sum(grepl("Next release", rows)) == 2L && sum(grepl("OPEN\\|Checklist: Next release", rows)) == 1L, "a closed Next release opens a new one")
run_github(pkg, fake5, "--yes", http = function(url) if (grepl("cran.r-project", url)) 200L else 404L)
expect(sum(grepl("Next release", issues(fake5))) == 2L, "the new Next release isn't opened again")
section("Everything ticked")
done_pkg <- new_package("donepkg")
writeLines(gsub("say_hello", "greet", readLines(file.path(done_pkg, "R", "say_hello.R"))), file.path(done_pkg, "R", "say_hello.R"))
fake6 <- fake_github()
run_github(done_pkg, fake6, "--yes")
writeLines(sub("- [ ]", "- [x]", body(fake6, 2), fixed = TRUE), file.path(fake6, "body-2.md"))
run_github(done_pkg, fake6, "--yes")
expect(any(grepl("^2\\|CLOSED\\|", issues(fake6))), "a checklist with every box ticked is closed")
run_github(done_pkg, fake6, "--yes")
expect(sum(grepl("Checklist: Before public", issues(fake6))) == 1L && sum(grepl("OPEN\\|Checklist: Before public", issues(fake6))) == 0L, "a closed checklist is not reopened or duplicated")
section("The question before changes")
fake9 <- fake_github()
options(kit.stdin = textConnection("no"))
no <- run_github_(pkg, fake9)
expect(no$value == 0L && length(writes(log_lines(fake9))) == 0L && any(grepl("Nothing was changed", no$out)), "answering no changes nothing")
options(kit.stdin = textConnection(character()))
silent <- run_github_(pkg, fake9)
expect(silent$value == 0L && length(writes(log_lines(fake9))) == 0L, "no answer at all (stdin closed) changes nothing")
options(kit.stdin = textConnection("yes"))
yes <- run_github_(pkg, fake9)
expect(yes$value == 0L && length(issues(fake9)) == 3L, "answering yes makes the changes")
options(kit.stdin = NULL)

section("cli/github-setup.R, the one-line route")
stage <- file.path(work, "archive-stage")
dir.create(file.path(stage, "launchR-0.0.1"), recursive = TRUE)
invisible(file.copy(file.path(kit_root, c("cli", "lists")), file.path(stage, "launchR-0.0.1"), recursive = TRUE))
old <- setwd(stage)
archive <- file.path(work, "launchR-0.0.1.tar.gz")
tar(archive, files = "launchR-0.0.1", compression = "gzip", tar = "internal")
setwd(old)
fake10 <- fake_github()
use_fake(fake10)
old <- setwd(pkg)
one_line <- function(...) system2(rscript, c(quote_arg(file.path(kit_root, "cli", "github-setup.R")), ...), stdout = TRUE, stderr = TRUE,
  env = c(paste0("KIT_ARCHIVE_URL=file://", archive), paste0("FAKE_GH_DIR=", fake10), paste0("PATH=", Sys.getenv("PATH")), paste0("HOME=", home), "GH_REPO=", "GITHUB_REPOSITORY="))
dry_line <- one_line("--dry-run")
expect(any(grepl("labels: create 11", dry_line)) && length(writes(log_lines(fake10))) == 0L, "the one-line route fetches the kit and shows the plan")
real_line <- one_line("--yes")
expect(length(issues(fake10)) == 3L, "the one-line route makes the changes with --yes")
setwd(old)

section("Rate limits, no gh, not signed in")
fake7 <- fake_github()
Sys.setenv(FAKE_GH_RATE_LIMIT = "1")
use_fake(fake7)
Sys.setenv(FAKE_GH_RATE_LIMIT = "1")
old <- setwd(pkg)
options(kit.http = function(url) 404L)
rate <- quiet(cmd_github("--yes"))
setwd(old)
expect(rate$value == 0L && length(issues(fake7)) == 3L, "a rate-limit answer is retried and the run finishes")
fake8 <- fake_github()
use_fake(fake8)
Sys.setenv(FAKE_GH_SIGNED_OUT = "1")
old <- setwd(pkg)
signed_out <- quiet(cmd_github("--yes"))
dry_out <- quiet(cmd_github("--dry-run"))
setwd(old)
expect(signed_out$value == 1L && length(writes(log_lines(fake8))) == 0L, "--yes while signed out stops and writes nothing")
expect(dry_out$value == 0L && any(grepl("isn't signed in", dry_out$out)), "a dry run while signed out still shows the plan")
# A PATH with git and the shell tools but no gh (on GitHub's runners gh sits in /usr/bin, so "/usr/bin:/bin" won't do).
no_gh_bin <- file.path(work, "no-gh-bin")
dir.create(no_gh_bin)
for (tool in c("git", "jq", "sh", "bash", "env")) {
  found <- Sys.which(tool)
  if (nzchar(found)) file.symlink(found, file.path(no_gh_bin, tool))
}
Sys.setenv(PATH = no_gh_bin)
old <- setwd(pkg)
no_gh <- quiet(cmd_github("--dry-run"))
no_gh_yes <- quiet(cmd_github("--yes"))
setwd(old)
Sys.setenv(PATH = old_path)
expect(no_gh$value == 0L && any(grepl("gh isn't installed", no_gh$out)), "without gh the dry run explains how to get it")
expect(no_gh_yes$value == 1L, "without gh, --yes fails with an exit code")
expect(quiet(cmd_github(character()))$value == 1L, "github outside a package folder fails")

section("launchr.R eject")
eject_pkg <- new_package("ejectpkg")
old <- setwd(eject_pkg)
write_text(sub("\\^\\\\[.]launchr[$]\n", "", read_text(".Rbuildignore")), ".Rbuildignore")
ejected <- quiet(cmd_eject(character()))
workflow <- read_text(".github/workflows/lint.yaml")
ignore <- read_text(".Rbuildignore")
readme <- read_text(".github/workflows/README.md")
dependabot <- read_text(".github/dependabot.yml")
setwd(old)
expect(ejected$value == 0L && dir.exists(file.path(eject_pkg, ".launchr", "quality-gate")) && file.exists(file.path(eject_pkg, ".launchr", ".github", "gitleaks.toml")),
  "eject copies launchR's CI, gate and gitleaks config into .launchr")
expect(grepl("uses: ./.github/workflows/launchr-lint.yaml", workflow, fixed = TRUE) && !grepl("insightsurge/launchR", workflow, fixed = TRUE), "eject points the caller files at local copies")
expect(endsWith(ignore, "^\\.launchr$\n") && !grepl("\r", ignore, fixed = TRUE), "eject adds .launchr to .Rbuildignore with \\n line endings")
expect(grepl('gate <- ".launchr/quality-gate/quality-gate.R"', readme, fixed = TRUE) && !grepl("insightsurge/launchR", readme, fixed = TRUE), "eject points the local gate run at the package's own copy")
expect(!grepl("launchR", dependabot, fixed = TRUE) && grepl("package-ecosystem: github-actions", dependabot, fixed = TRUE),
  "eject drops dependabot.yml's launchR group and rule, and keeps the rest")
expect(!grepl("lives in the launchR repository", readme, fixed = TRUE) && !grepl("Dependabot opens a pull request when launchR", readme, fixed = TRUE) &&
  grepl("`launchr-*.yaml` files here", readme, fixed = TRUE), "eject rewrites the workflows README's opening paragraph and updates section")

# A caller pinned by commit (with a version comment) is ejected too, and a second eject refreshes the copies.
sha_pkg <- new_package("shapkg")
old <- setwd(sha_pkg)
sha <- strrep("a1b2c3d4e5", 4)
lint_caller <- read_text(".github/workflows/lint.yaml")
write_text(sub("@v[0-9.]+", sprintf("@%s # v0.0.12", sha), lint_caller), ".github/workflows/lint.yaml")
first <- quiet(cmd_eject(character()))
sha_caller <- read_text(".github/workflows/lint.yaml")
write_text("stale copy\n", ".github/workflows/launchr-lint.yaml")
write_text(sub("uses: ./.github/workflows/launchr-lint.yaml", "uses: ./.github/workflows/launchr-lint.yaml\n", sha_caller, fixed = TRUE), ".github/workflows/lint.yaml")
second <- quiet(cmd_eject(character()))
refreshed <- read_text(".github/workflows/launchr-lint.yaml")
workflows_listed <- list.files(".github/workflows")
setwd(old)
expect(first$value == 0L && grepl("uses: ./.github/workflows/launchr-lint.yaml", sha_caller, fixed = TRUE) && !grepl("# v0.0.12|launchR", sha_caller),
  "eject also points a caller pinned by commit at the local copy, dropping the version comment")
expect(second$value == 0L && !grepl("stale copy", refreshed, fixed = TRUE) && grepl("\nname: lint", refreshed, fixed = TRUE) && !grepl("launchr-fetch", refreshed, fixed = TRUE),
  "a second eject refreshes the launchr-*.yaml copies")
expect(sum(workflows_listed == "launchr-lint.yaml") == 1L, "a second eject doesn't duplicate the copies")
old <- setwd(file.path(work))
outside <- quiet(cmd_eject(character()))
setwd(old)
expect(outside$value == 1L, "eject outside a package fails with a message")

# --- The first commit when git is old -------------------------------------------------------------------------
section("launchr.R new with a git that has no init -b")
# A git that refuses init -b, as before 2.28: the first branch is named another way. Another that refuses every init.
old_git <- Sys.which("git")
for (mode in c("no-b", "no-init")) {
  fake_bin <- file.path(work, paste0("fake-git-", mode))
  dir.create(fake_bin)
  writeLines(c("#!/bin/sh",
    if (mode == "no-b") 'case " $* " in *" -b "*) echo "unknown switch b" >&2; exit 129;; esac' else 'case " $* " in *" init "*) exit 128;; esac',
    sprintf('exec "%s" "$@"', old_git)), file.path(fake_bin, "git"))
  Sys.chmod(file.path(fake_bin, "git"), "755")
  Sys.setenv(PATH = paste(fake_bin, old_path, sep = .Platform$path.sep))
  assign(paste0("old_git_", gsub("-", "_", mode)), quiet(cmd_new(c(paste0("oldgit", gsub("-", "", mode)), "--yes", "--owner", "sample-org", "--path", file.path(work, paste0("oldgit-", mode))))))
  Sys.setenv(PATH = old_path)
}
branch <- system2("git", c("-C", quote_arg(file.path(work, "oldgit-no-b")), "symbolic-ref", "--short", "HEAD"), stdout = TRUE)
commits <- system2("git", c("-C", quote_arg(file.path(work, "oldgit-no-b")), "rev-list", "--count", "HEAD"), stdout = TRUE)
expect(old_git_no_b$value == 0L && identical(branch, "main") && identical(commits, "1"), "without init -b, new starts the repository, names the branch main and commits")
expect(old_git_no_init$value == 0L && any(grepl("git 2.28 or newer", old_git_no_init$out)) && !any(grepl("first commit failed", old_git_no_init$out)) &&
  file.exists(file.path(work, "oldgit-no-init", "DESCRIPTION")), "when git can't start a repository, new says git 2.28 or newer is needed, not that the commit failed")

# --- Eject, gate and the command line ----------------------------------------------------------------------------
section("launchr.R from the command line")
no_package <- file.path(work, "no-package")
dir.create(no_package)
old_dir <- setwd(no_package)
no_desc <- suppressWarnings(system2(rscript, quote_arg(file.path(kit_root, "quality-gate", "quality-gate.R")), stdout = TRUE, stderr = TRUE))
setwd(old_dir)
# Where the gate's own packages are missing (the routes job installs none), it stops at that check, with exit 2 too.
gate_ok <- identical(attr(no_desc, "status"), 2L) && (
  (length(no_desc) == 1 && grepl("package root", no_desc)) || grepl("^FAIL tools: missing R packages", no_desc[1])
)
if (!gate_ok) cat("  the gate printed (status ", deparse(attr(no_desc, "status")), "):\n", paste0("    ", no_desc, "\n"), sep = "")
expect(gate_ok, "the gate outside a package folder exits 2 with one line")

# The no-Suggests step hides every Suggests package except base and recommended ones, which ship with R.
gate_env <- new.env()
sys.source(file.path(kit_root, "quality-gate", "quality-gate.R"), envir = gate_env)
in_r <- function(pkg) pkg %in% c("tools", "MASS", "shiny")
expect(length(gate_env$suggests_in_r_library(c("tools", "MASS", "knitr"), "knitr", c("tools", "MASS"), in_r)) == 0L,
  "no-Suggests: base and recommended packages in Suggests don't stop the check")
expect(identical(gate_env$suggests_in_r_library(c("tools", "shiny", "knitr"), character(), c("tools", "MASS"), in_r), "shiny"),
  "no-Suggests: another Suggests package in R's own library is named")
expect(identical(gate_env$check_log_unavailable(c("* checking package dependencies ... INFO",
  "Packages suggested but not available for checking:", "  'shiny', 'data.table'", "* checking if this is a source package ... OK")),
  c("shiny", "data.table")), "no-Suggests: the hidden packages are read from R 4.6's INFO line")
expect(identical(gate_env$check_log_unavailable("Package suggested but not available for checking: 'zz'"), "zz"),
  "no-Suggests: and from the one-line form")
expect(identical(gate_env$missing_package_skips(c("• {shiny} is not installed. (2): 'a.R:1:1'", "• {zz} is not installed. (1): 'b.R:2:1'", "[ FAIL 0 | SKIP 3 ]")),
  c(shiny = 2L, zz = 1L)), "no-Suggests: tests skipped for a missing package are counted")
help_out <- system2(rscript, c(quote_arg(file.path(kit_root, "cli", "launchr.R"))), stdout = TRUE)
expect(any(grepl("Commands: new, gate, github-setup, eject", help_out)), "launchr.R with no command prints the commands")

cat("\n")
if (length(failures)) {
  cat(length(failures), "failed:\n", paste0("  - ", failures, "\n"), sep = "")
  quit(status = 1L)
}
cat("All tests passed.\n")
