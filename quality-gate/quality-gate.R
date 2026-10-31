#!/usr/bin/env Rscript
# quality-gate version: 2026-10-31
# Quality gate: one command that says whether an R package is ready: for CRAN by default, or for internal use.
#
#   Rscript <path to this file> [fast|tests|full|lint|nosuggests] [options]   (--help lists the options)
#
#   fast  (default) tools, style, docs in sync, \value, spelling, pkgdown, R CMD check --as-cran without tests
#   tests           tools, tests (NOT_CRAN=true, so tests that CRAN skips run too), coverage and new lines
#   full            everything: fast steps, tests, coverage, new lines, CRAN-like check with tests, built tarball and
#                   the check without Suggests
#   lint            the quick static steps only: tools, style, docs in sync, \value, spelling
#   nosuggests      R CMD check with only the hard dependencies on the library path (CI's check-no-suggests job)
#
# In `tests` and `full` the suite runs ONCE, under covr, and the same run gives the test results and the coverage
# (a package whose tests/ is not the standard testthat layout falls back to a plain run plus a separate covr run). If
# covr itself fails after that run, the coverage step FAILs with covr's message; the suite is not run a second time.
# --no-coverage runs the suite plainly, without covr (quicker, no coverage); --no-retry skips the re-run below.
# When tests fail, the failing files are re-run once in a fresh R process without covr: if every one then passes, the
# line says so ("probable flake") and the gate exits 3; each retried failure is appended to flakes.tsv beside the run
# folder. More than 5 failing files is not re-run (a breakage), unless one message accounts for most failures: a
# cascade (one broken thing, such as a closed browser, failing every later test), which the line names once.
#
# new_lines: every runnable line this branch adds in R/ (compared with where it left origin/HEAD, uncommitted and new
# files included) must be run by a test; `# nocov` leaves out a justified line. It reads the coverage of the same run,
# and skips outside git, without origin/HEAD, or when no coverage was measured.
#
# Exit codes: 0 every step passed or skipped; 1 a step failed; 2 usage, settings or tools problem (the gate could not
# judge the package); 3 the only failures are tests that passed on the re-run (a person decides: it is not merge
# evidence on its own). --steps, --filter and --no-coverage give a PARTIAL run, which is not merge evidence either.
#
# Run it from the package root. It prints one PASS/FAIL/SKIP line per step and a summary, and exits 1 if any step
# fails. Detailed output goes to a run folder that outlives the gate (its path is printed): one log per step,
# gate.json (one row per step) and, after the tests step, tests.txt, tests.json and tests.rds.
#
# Always checked (CRAN or its reviewers ask for these): R CMD check --as-cran with 0 errors, 0 warnings and 0 notes;
# a \value section for every exported function; help pages in sync with the roxygen comments; spelling; every file
# in inst/ present in the built package, and the package's size.
#
# Checked when the package has the tool's settings file (skipped with a reason otherwise):
#   air.toml    formatting with Air            (https://posit-dev.github.io/air/)
#   .lintr      lintr, with the package's rules
#   biome.json  Biome on the JS and CSS in inst/ (https://biomejs.dev)
#
# Optional settings, as fields in the package's DESCRIPTION:
#   Config/quality-gate/coverage: 80      lowest line coverage allowed, in percent (default 70; 0 = no limit).
#                                      A good-practice check: CRAN itself does not measure coverage
#   Config/quality-gate/tarball-mb: 5     largest built package allowed, in MB (default 5; 5 to 9, CRAN's limit is 10)
#   Config/quality-gate/target: internal  cran (default), or internal for a package that won't go to CRAN: R CMD check
#                                      then runs without --as-cran
#   Config/quality-gate/extra-dirs: tools more folders to format-check and lint, comma separated (default: none)
#
# Needs the R packages checkmate, cli, devtools, jsonlite and spelling, plus roxygen2, lintr, covr, testthat, withr
# and pkgbuild for the steps that use them; the tools step names whatever is missing. The nosuggests mode needs only
# checkmate, cli, jsonlite, pkgbuild, processx and rcmdcheck, so it runs where only the hard dependencies are installed.
#
# Writes to the package: devtools::document() may rewrite man/, NAMESPACE and DESCRIPTION (the docs step then fails
# and names the files); --update-wordlist rewrites inst/WORDLIST. Outside the package it writes only to tempdir()
# and the run folder: <QUALITY_GATE_OUT>/<YYYYmmdd-HHMMSS>-<mode>, where QUALITY_GATE_OUT defaults to quality-gate/ in the
# system temp folder (the parent of tempdir()).

modes <- c("fast", "tests", "full", "lint", "nosuggests")

# TRUE when the package says it won't go to CRAN (Config/quality-gate/target: internal).
gate_internal <- function() {
  identical(unname(read.dcf("DESCRIPTION", fields = "Config/quality-gate/target")[[1]]), "internal")
}

setting <- function(name, default) {
  checkmate::assert_string(name)
  checkmate::assert_string(default)
  fields <- paste0(c("Config/quality-gate/", "Config/cran-gate/"), name)  # the old field name still works
  values <- read.dcf("DESCRIPTION", fields = fields)
  value <- values[!is.na(values)][1]
  if (is.na(value)) default else trimws(value)
}

read_settings <- function() {
  coverage <- suppressWarnings(as.numeric(setting("coverage", "70")))
  tarball_mb <- suppressWarnings(as.numeric(setting("tarball-mb", "5")))
  extra_dirs <- trimws(strsplit(setting("extra-dirs", ""), ",", fixed = TRUE)[[1]])
  extra_dirs <- extra_dirs[nzchar(extra_dirs)]
  checkmate::assert_number(coverage, lower = 0, upper = 100, .var.name = "Config/quality-gate/coverage")
  # CRAN asks for source packages under 10 MB if possible, so the limit can be raised to 9 but not further.
  checkmate::assert_number(tarball_mb, lower = 5, upper = 9, .var.name = "Config/quality-gate/tarball-mb")
  for (dir in extra_dirs) {
    checkmate::assert_directory_exists(dir, .var.name = "Config/quality-gate/extra-dirs")
  }
  list(coverage = coverage, tarball_mb = tarball_mb, extra_dirs = extra_dirs)
}

# What this package uses, which decides the steps that run and the tools they need.
package_uses <- function() {
  roxygen_fields <- c("Roxygen", "RoxygenNote", "Config/roxygen2/version")
  list(
    air = any(file.exists(c("air.toml", ".air.toml"))),
    lintr = any(file.exists(c(".lintr", ".lintr.R"))),
    biome = any(file.exists(c("biome.json", "biome.jsonc"))),
    roxygen = !all(is.na(read.dcf("DESCRIPTION", fields = roxygen_fields))),
    tests = dir.exists("tests"),
    testthat = dir.exists("tests/testthat"),
    pkgdown = any(file.exists(c("_pkgdown.yml", "_pkgdown.yaml", "pkgdown/_pkgdown.yml", "inst/_pkgdown.yml")))
  )
}

required_packages <- function(mode, uses) {
  checkmate::assert_choice(mode, modes)
  checkmate::assert_list(uses, types = "logical")
  # The nosuggests mode needs only what its own step uses, so it runs in a library with just the hard dependencies
  # (CI's check-no-suggests job), which has no devtools.
  if (mode == "nosuggests") {
    return(c("checkmate", "cli", "jsonlite", "pkgbuild", "processx", "rcmdcheck"))
  }
  pkgs <- c("checkmate", "cli", "devtools", "jsonlite", "spelling")
  if (uses$roxygen) {
    pkgs <- c(pkgs, "roxygen2")
  }
  if (uses$lintr) {
    pkgs <- c(pkgs, "lintr")
  }
  if (mode %in% c("tests", "full") && uses$tests) {
    pkgs <- c(pkgs, "callr", "covr", "withr", if (uses$testthat) "testthat")
  }
  if (mode == "full") {
    pkgs <- c(pkgs, "pkgbuild", "processx", "rcmdcheck")
  }
  pkgs
}

steps_for <- function(mode) {
  checkmate::assert_choice(mode, modes)
  static <- c("air", "biome", "docs", "lintr", "value", "spelling")
  switch(
    mode,
    fast = c("tools", static, "pkgdown", "check_fast"),
    tests = c("tools", "tests", "coverage", "new_lines"),
    full = c("tools", static, "pkgdown", "tests", "coverage", "new_lines", "check_full", "nosuggests", "tarball"),
    lint = c("tools", static),
    nosuggests = c("tools", "nosuggests")
  )
}

# A step returns list(status = "PASS"|"FAIL"|"SKIP", detail = "..."); errors become FAIL.
result <- function(status, detail = "") {
  checkmate::assert_choice(status, c("PASS", "FAIL", "SKIP"))
  checkmate::assert_string(detail)
  list(status = status, detail = detail)
}

# The run folder: one per gate run, outside the session's tempdir() (which R deletes when the gate exits), so the
# logs and results are still there when you read them. `parent` is QUALITY_GATE_OUT or quality-gate/ in the system temp
# folder.
run_folder <- function(parent, mode) {
  checkmate::assert_string(parent, min.chars = 1)
  checkmate::assert_string(mode, min.chars = 1)
  dir.create(parent, recursive = TRUE, showWarnings = FALSE)
  checkmate::assert_directory_exists(parent, access = "w", .var.name = "QUALITY_GATE_OUT")
  base <- file.path(normalizePath(parent), paste0(format(Sys.time(), "%Y%m%d-%H%M%S"), "-", mode))
  dir <- base
  n <- 1L
  while (!dir.create(dir, showWarnings = FALSE)) {
    n <- n + 1L
    dir <- paste0(base, "-", n)
  }
  dir
}

default_out <- function() {
  Sys.getenv("QUALITY_GATE_OUT", file.path(dirname(tempdir()), "quality-gate"))
}

# Runs `fun`, sending its printed output and messages to the log file.
run_logged <- function(fun, log) {
  checkmate::assert_function(fun)
  checkmate::assert_string(log)
  con <- file(log, open = "a")
  sink(con)
  sink(con, type = "message")
  on.exit({
    sink(type = "message")
    sink()
    close(con)
  })
  fun()
}

js_css_files <- function() {
  if (!dir.exists("inst")) {
    return(character())
  }
  list.files("inst", pattern = "\\.(js|css)$", recursive = TRUE, full.names = TRUE)
}

step_tools <- function(mode, uses) {
  checkmate::assert_choice(mode, modes)
  checkmate::assert_list(uses, types = "logical")
  missing <- character()
  # Only the modes that run the air and biome steps need the tools (nosuggests runs in CI without them).
  steps <- steps_for(mode)
  if (uses$air && "air" %in% steps && !nzchar(Sys.which("air"))) {
    missing <- c(missing, "air (https://posit-dev.github.io/air/), needed because the package has an air.toml")
  }
  if (uses$biome && "biome" %in% steps && length(js_css_files()) > 0 && !nzchar(Sys.which("biome"))) {
    missing <- c(missing, "biome (https://biomejs.dev), needed because inst/ has JS or CSS")
  }
  pkgs <- required_packages(mode, uses)
  absent <- pkgs[!vapply(pkgs, requireNamespace, logical(1), quietly = TRUE)]
  if (length(absent) > 0) {
    missing <- c(missing, paste0("R package ", absent))
  }
  lib <- paste0(".libPaths()[1] = ", .libPaths()[1])
  if (length(missing) > 0) {
    return(result("FAIL", paste(c(paste("missing:", paste(missing, collapse = ", ")), lib), collapse = "; ")))
  }
  result("PASS", lib)
}

step_air <- function(uses, settings, log) {
  checkmate::assert_list(uses, types = "logical")
  checkmate::assert_list(settings)
  checkmate::assert_string(log)
  if (!uses$air) {
    return(result("SKIP", "no air.toml: the package doesn't use Air"))
  }
  # Air skips hidden folders when given ".", so extra folders (which may be hidden) are named one by one.
  paths <- c(".", settings$extra_dirs)
  out <- suppressWarnings(system2("air", c("format", "--check", shQuote(paths)), stdout = TRUE, stderr = TRUE))
  write(out, log, append = TRUE)
  if (!is.null(attr(out, "status")) && attr(out, "status") != 0) {
    fix <- paste0("run `air format ", paste(paths, collapse = " "), "`; ")
    return(result("FAIL", paste0(fix, paste(utils::head(out, 3), collapse = " | "))))
  }
  result("PASS")
}

step_biome <- function(uses, log) {
  checkmate::assert_list(uses, types = "logical")
  checkmate::assert_string(log)
  if (!uses$biome) {
    return(result("SKIP", "no biome.json: the package doesn't use Biome"))
  }
  files <- js_css_files()
  if (length(files) == 0) {
    return(result("SKIP", "no JS or CSS in inst/ yet"))
  }
  out <- suppressWarnings(system2("biome", c("ci", "inst"), stdout = TRUE, stderr = TRUE))
  write(out, log, append = TRUE)
  if (!is.null(attr(out, "status")) && attr(out, "status") != 0) {
    return(result("FAIL", "run `biome check --write inst`; details in the log"))
  }
  result("PASS", paste(length(files), "files"))
}

# Hashes of the files roxygen writes. DESCRIPTION is hashed without the roxygen version fields, so a different
# roxygen2 version on another machine doesn't count as out-of-date docs.
docs_snapshot <- function() {
  files <- c("NAMESPACE", list.files("man", full.names = TRUE))
  # Files only: a folder such as man/figures (a package logo) has no checksum, and NA != NA would count as a change.
  files <- files[file.exists(files) & !dir.exists(files)]
  hashes <- unname(tools::md5sum(files))
  desc <- readLines("DESCRIPTION", warn = FALSE)
  desc <- desc[!grepl("^(RoxygenNote|Config/roxygen2/version):", desc)]
  stats::setNames(c(hashes, paste(desc, collapse = "\n")), c(files, "DESCRIPTION"))
}

step_docs <- function(uses, log) {
  checkmate::assert_list(uses, types = "logical")
  checkmate::assert_string(log)
  if (!uses$roxygen) {
    return(result("SKIP", "the package doesn't use roxygen2"))
  }
  before <- docs_snapshot()
  run_logged(function() devtools::document(quiet = TRUE), log)
  after <- docs_snapshot()
  changed <- union(setdiff(names(after), names(before)), setdiff(names(before), names(after)))
  common <- intersect(names(before), names(after))
  changed <- c(changed, common[before[common] != after[common]])
  if (length(changed) > 0) {
    return(result("FAIL", paste0("document() changed ", paste(changed, collapse = ", "), ": review and commit")))
  }
  result("PASS")
}

step_lintr <- function(uses, settings, log) {
  checkmate::assert_list(uses, types = "logical")
  checkmate::assert_list(settings)
  checkmate::assert_string(log)
  if (!uses$lintr) {
    return(result("SKIP", "no .lintr: the package doesn't use lintr"))
  }
  # lint_package() covers R/, tests/ and inst/; Config/quality-gate/extra-dirs adds more folders.
  lints <- lintr::lint_package()
  for (dir in settings$extra_dirs) {
    # lint_dir() names files relative to the folder; name them from the package root, as lint_package() does, so a
    # GitHub annotation lands on the right file.
    extra <- lintr::lint_dir(dir)
    for (i in seq_along(extra)) {
      extra[[i]]$filename <- file.path(dir, extra[[i]]$filename)
    }
    # c() drops the "lints" class (lintr has no c() method), and then print() would skip lintr's print method, which
    # writes the ::warning annotation lines GitHub shows on the changed files.
    lints <- structure(c(lints, extra), class = class(lints))
  }
  if (length(lints) > 0) {
    run_logged(function() print(lints), log) # nolint: undesirable_function_linter. Full lint report for the log.
    first <- vapply(
      utils::head(lints, 3),
      function(x) paste0(x$filename, ":", x$line_number, " ", x$linter),
      character(1)
    )
    return(result("FAIL", paste0(length(lints), " lints: ", paste(first, collapse = "; "))))
  }
  result("PASS")
}

rd_tags <- function(rd) {
  checkmate::assert_class(rd, "Rd")
  vapply(rd, function(x) attr(x, "Rd_tag"), character(1))
}

# The package's own exported functions (re-exports from other packages don't need a \value section here).
exported_functions <- function(log) {
  checkmate::assert_string(log)
  pkg <- read.dcf("DESCRIPTION", fields = "Package")[[1]]
  if (!isNamespaceLoaded(pkg)) {
    run_logged(function() devtools::load_all(quiet = TRUE), log)
  }
  ns <- asNamespace(pkg)
  own <- function(name) {
    obj <- get0(name, envir = ns)
    is.function(obj) && !is.primitive(obj) && identical(topenv(environment(obj)), ns)
  }
  exports <- getNamespaceExports(ns)
  sort(exports[vapply(exports, own, logical(1))])
}

# Exported functions whose help page has no \value section (CRAN reviewers ask for one on every function).
step_value <- function(log) {
  checkmate::assert_string(log)
  exports <- exported_functions(log)
  if (length(exports) == 0) {
    return(result("PASS", "no exported functions yet"))
  }
  documented <- character()
  missing <- character()
  if (dir.exists("man")) {
    for (rd in tools::Rd_db(dir = ".")) {
      tags <- rd_tags(rd)
      aliases <- intersect(unlist(lapply(rd[tags == "\\alias"], as.character)), exports)
      documented <- c(documented, aliases)
      if (!"\\value" %in% tags) {
        missing <- c(missing, aliases)
      }
    }
  }
  undocumented <- setdiff(exports, documented)
  problems <- c(
    if (length(missing) > 0) paste0("no \\value (add @returns) for: ", toString(missing)),
    if (length(undocumented) > 0) paste0("no help page for: ", toString(undocumented))
  )
  if (length(problems) > 0) {
    return(result("FAIL", paste(problems, collapse = "; ")))
  }
  result("PASS", paste(length(exports), "exported functions"))
}

step_spelling <- function(update, log) {
  checkmate::assert_flag(update)
  checkmate::assert_string(log)
  words <- run_logged(function() spelling::spell_check_package("."), log)
  if (nrow(words) == 0) {
    return(result("PASS"))
  }
  run_logged(function() print(words), log) # nolint: undesirable_function_linter. Full report for the log.
  if (update) {
    run_logged(function() spelling::update_wordlist(".", confirm = FALSE), log)
    return(result("PASS", paste0("added to inst/WORDLIST (review before committing): ", toString(words$word))))
  }
  result("FAIL", paste0("unknown words: ", toString(words$word), "; fix them, or add with --update-wordlist"))
}

# The failing tests named in testthat's check output (testthat.Rout.fail under R CMD check or covr): lines such as
# "-- Failure ('test-x.R:3:3'): the name --", with the rule characters taken off.
failure_headers <- function(text) {
  checkmate::assert_character(text, any.missing = FALSE)
  lines <- unlist(strsplit(text, "\n", fixed = TRUE))
  found <- regmatches(lines, regexpr("(Failure|Error) \\('[^']+'\\): .*$", lines))
  trimws(sub("[ ─-]+$", "", found))
}

# The check's line: counts, and on FAIL the first problem (its header and first line of detail) and the failing tests.
# With `log`, every problem is written to it in full (the check itself runs quietly).
check_result <- function(res, log = NULL) {
  checkmate::assert_class(res, "rcmdcheck")
  checkmate::assert_string(log, null.ok = TRUE)
  counts <- c(errors = length(res$errors), warnings = length(res$warnings), notes = length(res$notes))
  detail <- paste(counts, names(counts), collapse = ", ")
  if (sum(counts) > 0) {
    problems <- c(res$errors, res$warnings, res$notes)
    if (!is.null(log)) {
      write(c(problems, if (length(res$test_fail) > 0) as.character(unlist(res$test_fail))), log, append = TRUE)
    }
    lines <- trimws(strsplit(problems[1], "\n", fixed = TRUE)[[1]])
    lines <- lines[nzchar(lines)]
    first <- paste(utils::head(lines, 2), collapse = ": ")
    failing <- failure_headers(as.character(unlist(res$test_fail)))
    tests <- if (length(failing) > 0) {
      more <- if (length(failing) > 3) sprintf(" +%d more", length(failing) - 3) else ""
      paste0("; failing tests: ", paste(utils::head(failing, 3), collapse = "; "), more)
    } else {
      ""
    }
    return(result("FAIL", paste0(detail, "; first: ", first, tests)))
  }
  result("PASS", detail)
}

# CRAN-like check: NOT_CRAN=false so tests behind skip_on_cran() skip as they do on CRAN (devtools::check() sets
# NOT_CRAN=true by default, which is not what CRAN runs). `_R_CHECK_SYSTEM_CLOCK_=false` checks the files' timestamps
# against this machine's clock instead of a time server, so a machine without internet gets no "unable to verify
# current time" note; the timestamps are still checked.
step_check <- function(tests, log) {
  checkmate::assert_flag(tests)
  checkmate::assert_string(log)
  args <- c(if (!gate_internal()) "--as-cran", if (!tests) "--no-tests")
  res <- run_logged(
    function() {
      devtools::check(
        document = FALSE,
        args = args,
        env_vars = c(NOT_CRAN = "false", `_R_CHECK_SYSTEM_CLOCK_` = "false"),
        error_on = "never",
        quiet = TRUE
      )
    },
    log
  )
  check_result(res, log)
}

# The first line of a test's message, without testthat's "Error in `eval(code, test_env)`: " prefix, cut to 100
# characters, with a long call shortened to its name. A line ending in ":" (cli's "Error in `f()`:") keeps the line
# after it. Older rlang versions start the
# message with the error's classes ("<error_x/rlang_error/error/condition>"), which say nothing: that line is skipped.
first_message_line <- function(message) {
  checkmate::assert_string(message)
  lines <- trimws(strsplit(message, "\n", fixed = TRUE)[[1]])
  lines <- lines[nzchar(lines) & !grepl("^<[A-Za-z0-9_./]+>$", lines)]
  if (length(lines) == 0) {
    return("")
  }
  line <- if (length(lines) > 1 && endsWith(lines[1], ":")) paste(lines[1:2], collapse = " ") else lines[1]
  line <- sub("^Error in `eval\\(code, test_env\\)`: ", "", line)
  # A long call ("Error in `f(a = a, b = b, ...)`: the message") would push the message past the cut: keep its name.
  line <- sub("^Error in `([A-Za-z0-9_.$:]+)\\(.{20,}?\\)`: ", "Error in `\\1()`: ", line, perl = TRUE)
  if (nchar(line) > 100) paste0(substr(line, 1, 97), "...") else line
}

# One row per failure, error and warning in a testthat results object: file, line, test, kind, message.
test_issues <- function(res) {
  checkmate::assert_class(res, "testthat_results")
  kinds <- c(expectation_failure = "Failure", expectation_error = "Error", expectation_warning = "Warning")
  rows <- lapply(res, function(t) {
    found <- Filter(function(e) inherits(e, names(kinds)), t$results)
    lapply(found, function(e) {
      data.frame(
        file = t$file,
        line = if (inherits(e$srcref, "srcref")) as.integer(e$srcref[[1]]) else NA_integer_,
        test = if (length(t$test) == 0 || is.na(t$test)) "(code outside test_that())" else t$test,
        kind = unname(kinds[intersect(class(e), names(kinds))[1]]),
        message = first_message_line(conditionMessage(e))
      )
    })
  })
  empty <- data.frame(
    file = character(),
    line = integer(),
    test = character(),
    kind = character(),
    message = character()
  )
  do.call(rbind, c(list(empty), unlist(rows, recursive = FALSE)))
}

# A cascade: one broken thing (a browser that closed, a server that stopped) making many later tests fail with the
# same message. At least 6 failures across at least 3 files share one message (numbers ignored), and they are at least
# half of all failures. Returns the message, how many failures and files share it, and the first of them in run order
# (the place to start looking); NULL when the failures are not a cascade.
cascade_of <- function(bad) {
  checkmate::assert_data_frame(bad)
  if (nrow(bad) < 6) {
    return(NULL)
  }
  key <- gsub("[0-9]+", "N", bad$message)
  counts <- sort(table(key), decreasing = TRUE)
  shared <- key == names(counts)[1]
  files <- unique(bad$file[shared])
  if (counts[[1]] < 6 || length(files) < 3 || counts[[1]] < nrow(bad) / 2) {
    return(NULL)
  }
  list(
    message = bad$message[shared][1],
    n = sum(shared),
    files = length(files),
    first = bad[shared, ][1, ],
    rows = shared
  )
}

# The cascade in one phrase, for the FAIL line and the report.
cascade_text <- function(cascade) {
  checkmate::assert_list(cascade)
  first <- cascade$first
  sprintf(
    "cascade: %d failures in %d files share one message (%s: %s), the first at %s:%s \"%s\"",
    cascade$n,
    cascade$files,
    first$kind,
    cascade$message,
    first$file,
    first$line,
    first$test
  )
}

# A failure message that reads like a timeout (a wait that ran out), which a package may fix by waiting longer.
timeout_like <- function(message) {
  checkmate::assert_character(message, any.missing = FALSE)
  grepl("timed? ?out|timeout|within [0-9]+ ?(s|sec|seconds)", message, ignore.case = TRUE)
}

# Issues as `file:line "test" (Kind: message)`, with a note on the ones that look like a timeout.
issue_text <- function(issues) {
  checkmate::assert_data_frame(issues)
  note <- ifelse(timeout_like(issues$message), " [looks like a timeout]", "")
  sprintf("%s:%s \"%s\" (%s: %s)%s", issues$file, issues$line, issues$test, issues$kind, issues$message, note)
}

# The testthat `filter` that picks exactly these test files (testthat matches it against the file name without the
# `test-` or `test_` prefix and the .R extension).
rerun_filter <- function(files) {
  checkmate::assert_character(files, min.len = 1, any.missing = FALSE)
  names <- sub("^test[-_]", "", sub("\\.[Rr]$", "", basename(files)))
  escaped <- gsub("([.|()\\^{}+$*?]|\\[|\\])", "\\\\\\1", names)
  paste0("^(", paste(unique(escaped), collapse = "|"), ")$")
}

# The gate's exit code: 0 passed, 1 a step failed, 2 the gate could not judge the package (its tools or settings are
# wrong), 3 the only failure is tests that passed on the re-run.
exit_code <- function(failed, flaky) {
  checkmate::assert_character(failed, any.missing = FALSE)
  checkmate::assert_flag(flaky)
  if (length(failed) == 0) {
    return(0L)
  }
  if (any(c("tools", "settings") %in% failed)) {
    return(2L)
  }
  if (flaky && identical(unique(failed), "tests")) 3L else 1L
}

# The git commit the run is for, or "" outside a repository.
git_head <- function() {
  out <- suppressWarnings(tryCatch(
    system2("git", c("rev-parse", "--short", "HEAD"), stdout = TRUE, stderr = FALSE),
    error = function(e) character()
  ))
  if (length(out) == 0 || !is.null(attr(out, "status"))) "" else out[[1]]
}

# Appends one row per retried failure to flakes.tsv (date, mode, commit, file, line, test, kind, message, re-run).
append_flakes <- function(path, issues, mode, rerun) {
  checkmate::assert_string(path)
  checkmate::assert_data_frame(issues)
  checkmate::assert_string(mode)
  checkmate::assert_string(rerun)
  if (nrow(issues) == 0) {
    return(invisible(path))
  }
  rows <- data.frame(
    date = format(Sys.time(), "%Y-%m-%d %H:%M:%S"),
    mode = mode,
    commit = git_head(),
    file = issues$file,
    line = issues$line,
    test = issues$test,
    kind = issues$kind,
    message = gsub("[\t\r\n]+", " ", issues$message),
    rerun = rerun
  )
  utils::write.table(
    rows,
    path,
    sep = "\t",
    quote = FALSE,
    row.names = FALSE,
    col.names = !file.exists(path),
    append = file.exists(path)
  )
  invisible(path)
}

# Reads a testthat results object: writes tests.rds and tests.json to the run folder and returns the counts, the
# issues and the slowest files.
summarise_tests <- function(res, run_dir) {
  checkmate::assert_class(res, "testthat_results")
  checkmate::assert_directory_exists(run_dir, access = "w")
  df <- as.data.frame(res)
  issues <- test_issues(res)
  slow <- if (nrow(df) > 0) {
    utils::head(sort(tapply(df$real, df$file, sum, na.rm = TRUE), decreasing = TRUE), 10)
  } else {
    numeric()
  }
  bad <- issues[issues$kind != "Warning", , drop = FALSE]
  cascade <- cascade_of(bad)
  counts <- list(
    expectations = sum(df$nb),
    failed = nrow(bad),
    warnings = sum(issues$kind == "Warning"),
    skipped = sum(df$skipped)
  )
  saveRDS(res, file.path(run_dir, "tests.rds"))
  jsonlite::write_json(
    list(
      counts = counts,
      issues = issues,
      cascade = if (!is.null(cascade)) cascade[c("message", "n", "files", "first")],
      slowest_files = as.list(slow),
      tests = df[setdiff(names(df), "result")]
    ),
    file.path(run_dir, "tests.json"),
    auto_unbox = TRUE,
    pretty = TRUE,
    digits = NA,
    na = "null"
  )
  list(counts = counts, issues = issues, bad = bad, slow = slow, cascade = cascade)
}

# The tests step's line: counts and the slowest file on PASS; counts, the first 3 problems and where the details
# are on FAIL.
tests_result <- function(summary, txt) {
  checkmate::assert_list(summary)
  checkmate::assert_string(txt)
  n <- summary$counts
  counts <- sprintf(
    "%d expectations, %d failed, %d warnings, %d skipped",
    n$expectations,
    n$failed,
    n$warnings,
    n$skipped
  )
  if (nrow(summary$bad) == 0) {
    slowest <- if (length(summary$slow) > 0) {
      sprintf("; slowest file %s (%.0fs)", names(summary$slow)[1], summary$slow[[1]])
    } else {
      ""
    }
    return(result("PASS", paste0(counts, slowest)))
  }
  # A cascade is said once, then the first failures it doesn't cover (they may be the real problem).
  cascade <- summary$cascade
  shown <- if (is.null(cascade)) summary$bad else summary$bad[!cascade$rows, , drop = FALSE]
  named <- c(if (!is.null(cascade)) cascade_text(cascade), issue_text(utils::head(shown, 3)))
  more <- if (nrow(shown) > 3) sprintf("; +%d more", nrow(shown) - 3) else ""
  result("FAIL", paste0(counts, ": ", paste(named, collapse = "; "), more, "; details: ", txt))
}

# Whether the tests step can run the suite once under covr and take the results from that run: the gate is going to
# measure coverage (tests or full mode, no --no-coverage), covr is installed, and tests/ is the standard testthat
# layout (only testthat.R beside testthat/), which is what covr's own `tests` run would execute.
single_run_ok <- function(state) {
  checkmate::assert_environment(state)
  tests_dir <- list.files("tests", all.files = FALSE)
  isTRUE(state$mode %in% c("tests", "full")) &&
    !isTRUE(state$no_coverage) &&
    requireNamespace("covr", quietly = TRUE) &&
    file.exists("tests/testthat.R") &&
    setequal(tests_dir, c("testthat", "testthat.R"))
}

# One covr run that executes the suite against the installed package and saves testthat's results. Returns them;
# the coverage object is left in state$cov for the coverage step. When covr errors after the suite has run (the
# results are saved), its message and this log are left in state$covr_error, so the coverage step can report them
# instead of running the suite a second time.
tests_under_covr <- function(run_dir, txt, log, state) {
  checkmate::assert_directory_exists(run_dir, access = "w")
  checkmate::assert_string(txt)
  checkmate::assert_string(log)
  checkmate::assert_environment(state)
  pkg <- read.dcf("DESCRIPTION", fields = "Package")[[1]]
  rds <- file.path(run_dir, "tests.rds")
  unlink(rds)
  state$covr_error <- NULL
  code <- c(
    # testthat's test_check(), which R CMD check and covr's own tests run use, sets this; test_dir() doesn't. Without
    # it, shinytest2 finds the source package and makes each app process pkgload::load_all() it, which re-runs covr's
    # load hook there: covr clears what it has counted, and its merge later fails or reads a far lower percentage.
    "Sys.setenv(TESTTHAT_IS_CHECKING = 'true')",
    sprintf(
      paste0(
        "res <- testthat::test_dir(%s, package = %s, load_package = 'installed', ",
        "reporter = testthat::SummaryReporter$new(file = %s, max_reports = Inf), stop_on_failure = FALSE)"
      ),
      deparse(normalizePath("tests/testthat")),
      deparse(pkg),
      deparse(txt)
    ),
    sprintf("saveRDS(res, %s)", deparse(rds))
  )
  # covr cuts the failure output to warning.length characters (1000 by default): raise it to R's maximum.
  withr::local_options(warning.length = 8170L)
  state$cov <- tryCatch(
    run_logged(function() covr::package_coverage(quiet = TRUE, type = "none", code = code), log),
    error = function(e) {
      write(conditionMessage(e), log, append = TRUE)
      if (!file.exists(rds)) {
        stop(first_message_line(conditionMessage(e)), call. = FALSE)
      }
      state$covr_error <- list(message = conditionMessage(e), log = log)
      NULL
    }
  )
  readRDS(rds)
}

# Runs the test files that match `filter` in a fresh R process, with the package loaded from source, and returns
# testthat's results. A fresh process starts without whatever the first run left behind (a closed browser, a stopped
# server, changed options), which is what a re-run is for.
rerun_fresh <- function(filter, log) {
  checkmate::assert_string(filter)
  checkmate::assert_string(log)
  callr::r(
    function(filter) devtools::test(filter = filter, stop_on_failure = FALSE, reporter = "summary"),
    args = list(filter = filter),
    stdout = log,
    stderr = "2>&1"
  )
}

# After a failed run: re-run only the failing files once, in a fresh R process without covr, and say whether they pass
# then. A pass is reported as a probable flake (the gate exits 3), never as a PASS. More than 5 failing files is a
# breakage and is not re-run, unless the failures are a cascade (one broken thing failing many later tests, which a
# fresh process may not repeat).
retry_failed <- function(out, state, run_dir, log) {
  checkmate::assert_list(out)
  checkmate::assert_environment(state)
  checkmate::assert_directory_exists(run_dir, access = "w")
  checkmate::assert_string(log)
  bad <- state$tests$bad
  files <- unique(bad$file)
  if (isTRUE(state$no_retry) || length(files) == 0) {
    return(out)
  }
  cascade <- !is.null(state$tests$cascade)
  if (length(files) > 5 && !cascade) {
    return(result("FAIL", paste0(out$detail, "; not re-run: ", length(files), " files failed, that is a breakage")))
  }
  rerun_log <- file.path(run_dir, "tests-rerun.log")
  again <- tryCatch(
    rerun_fresh(rerun_filter(files), rerun_log),
    error = function(e) {
      write(conditionMessage(e), log, append = TRUE)
      NULL
    }
  )
  if (is.null(again)) {
    return(result("FAIL", paste0(out$detail, "; the re-run could not be made (see tests.log)")))
  }
  still <- test_issues(again)
  still <- still[still$kind != "Warning", , drop = FALSE]
  passed <- nrow(still) == 0
  state$flaky <- passed
  verdict <- if (passed) "passed (probable flake)" else "failed again"
  append_flakes(file.path(dirname(run_dir), "flakes.tsv"), bad, state$mode, verdict)
  if (!passed) {
    verdict <- sprintf("%s (%d failures; see tests-rerun.log)", verdict, nrow(still))
  }
  result("FAIL", sprintf("%s; re-run of %d file(s) in a fresh R process: %s", out$detail, length(files), verdict))
}

step_tests <- function(uses, run_dir, log, state) {
  checkmate::assert_list(uses, types = "logical")
  checkmate::assert_directory_exists(run_dir, access = "w")
  checkmate::assert_string(log)
  checkmate::assert_environment(state)
  if (!uses$testthat) {
    return(result("SKIP", "no tests/testthat (R CMD check still runs whatever is in tests/)"))
  }
  withr::local_envvar(NOT_CRAN = "true")
  txt <- file.path(run_dir, "tests.txt")
  state$single_run <- single_run_ok(state)
  res <- if (state$single_run) {
    tests_under_covr(run_dir, txt, log, state)
  } else {
    reporter <- testthat::SummaryReporter$new(file = txt, max_reports = Inf)
    # stop_on_failure = FALSE: with TRUE, testthat aborts with "Test failures." and its results are lost.
    run_logged(
      function() devtools::test(filter = state$filter, stop_on_failure = FALSE, reporter = reporter),
      log
    )
  }
  state$tests <- summarise_tests(res, run_dir)
  out <- tests_result(state$tests, txt)
  if (out$status == "FAIL") {
    out <- retry_failed(out, state, run_dir, log)
  }
  out
}

step_coverage <- function(uses, settings, log, state) {
  checkmate::assert_list(uses, types = "logical")
  checkmate::assert_list(settings)
  checkmate::assert_string(log)
  checkmate::assert_environment(state)
  if (!uses$tests) {
    return(result("SKIP", "the package has no tests/"))
  }
  if (isTRUE(state$no_coverage)) {
    return(result("SKIP", if (is.null(state$filter)) "--no-coverage" else "--filter (a partial run has no coverage)"))
  }
  withr::local_envvar(NOT_CRAN = "true")
  cov <- state$cov
  if (!is.null(state$covr_error)) {
    # The suite already ran under covr and covr failed afterwards (merging its trace files, say). Running the suite
    # again would take as long as the first run and could fail the same way, so say what covr said instead.
    message <- gsub("\\s*\n\\s*", " ", trimws(state$covr_error$message))
    return(
      result(
        "FAIL",
        paste0(
          "covr failed after the tests ran under it (the suite is not run again): ",
          first_message_line(message),
          "; details: ",
          state$covr_error$log
        )
      )
    )
  }
  if (!inherits(cov, "coverage")) {
    if (identical(unname(state$statuses["tests"]), "FAIL")) {
      return(result("SKIP", "tests failed, and covr gives no percentage when a test fails"))
    }
    # The tests step did not run under covr (a non-standard tests/ layout): run covr's own tests run.
    # covr cuts the failure output to warning.length characters (1000 by default): raise it to R's maximum.
    withr::local_options(warning.length = 8170L)
    cov <- tryCatch(
      run_logged(function() covr::package_coverage(quiet = TRUE), log),
      error = function(e) {
        message <- conditionMessage(e)
        write(message, log, append = TRUE)
        failing <- failure_headers(message)
        if (length(failing) == 0) {
          return(result("FAIL", first_message_line(message)))
        }
        more <- if (length(failing) > 3) sprintf(" +%d more", length(failing) - 3) else ""
        result("FAIL", paste0("tests failed under covr: ", paste(utils::head(failing, 3), collapse = "; "), more))
      }
    )
  }
  if (!inherits(cov, "coverage")) {
    return(cov)
  }
  state$cov <- cov
  if (nrow(as.data.frame(cov)) == 0) {
    return(result("PASS", "no R code lines to cover yet"))
  }
  pct <- covr::percent_coverage(cov)
  after_failure <- if (identical(unname(state$statuses["tests"]), "FAIL")) " (from a run with failing tests)" else ""
  if (pct < settings$coverage) {
    return(
      result(
        "FAIL",
        sprintf("%.1f%% is under %g%%; see covr::zero_coverage()%s", pct, settings$coverage, after_failure)
      )
    )
  }
  limit <- if (settings$coverage > 0) sprintf("at least %g%% needed", settings$coverage) else "no limit set"
  result("PASS", sprintf("%.1f%% (%s)%s", pct, limit, after_failure))
}

# Runs git with these arguments and returns its output, or NULL when git fails or isn't installed.
git_lines <- function(args) {
  checkmate::assert_character(args, min.len = 1, any.missing = FALSE)
  out <- suppressWarnings(tryCatch(
    system2("git", args, stdout = TRUE, stderr = FALSE),
    error = function(e) NULL
  ))
  if (is.null(out) || !is.null(attr(out, "status"))) NULL else out
}

# The added lines in `git diff --unified=0` output, as file and line number (new-file side).
added_lines_in_diff <- function(diff) {
  checkmate::assert_character(diff, any.missing = FALSE)
  rows <- list()
  file <- NA_character_
  for (line in diff) {
    if (startsWith(line, "+++ ")) {
      file <- if (line == "+++ /dev/null") NA_character_ else sub("^\\+\\+\\+ b/", "", line)
    } else if (startsWith(line, "@@ ") && !is.na(file)) {
      hunk <- regmatches(line, regexec("\\+([0-9]+)(,([0-9]+))?", line))[[1]]
      start <- as.integer(hunk[2])
      count <- if (nzchar(hunk[4])) as.integer(hunk[4]) else 1L
      if (count > 0) {
        rows[[length(rows) + 1L]] <- data.frame(file = file, line = seq(start, length.out = count))
      }
    }
  }
  do.call(rbind, c(list(data.frame(file = character(), line = integer())), rows))
}

# The lines in R/ that this branch adds, compared with where it left origin/HEAD (or origin/main, origin/master),
# uncommitted and new files included. A string instead says why there is nothing to compare with.
branch_added_lines <- function() {
  if (is.null(git_lines(c("rev-parse", "--is-inside-work-tree")))) {
    return("not a git repository")
  }
  # origin/HEAD names the default branch; a clone without it may still have origin/main or origin/master.
  known <- Filter(
    function(ref) !is.null(git_lines(c("rev-parse", "--verify", "--quiet", ref))),
    c("origin/HEAD", "origin/main", "origin/master")
  )
  if (length(known) == 0) {
    return("no origin/HEAD, origin/main or origin/master to compare with")
  }
  base <- git_lines(c("merge-base", "HEAD", known[[1]]))
  if (length(base) == 0) {
    return("no common commit with origin/HEAD")
  }
  diff <- git_lines(c("diff", "--unified=0", "--no-color", "--no-ext-diff", base[[1]], "--", "R/"))
  if (is.null(diff)) {
    return("git diff failed")
  }
  added <- added_lines_in_diff(diff)
  untracked <- git_lines(c("ls-files", "--others", "--exclude-standard", "--", "R/"))
  for (file in untracked[grepl("\\.[Rr]$", untracked)]) {
    n <- length(readLines(file, warn = FALSE))
    if (n > 0) {
      added <- rbind(added, data.frame(file = file, line = seq_len(n)))
    }
  }
  added
}

# Line numbers as short ranges: 3, 4, 5, 9 -> "3-5, 9".
line_ranges <- function(lines) {
  checkmate::assert_integerish(lines, any.missing = FALSE)
  lines <- sort(unique(lines))
  starts <- lines[c(TRUE, diff(lines) != 1)]
  ends <- lines[c(diff(lines) != 1, TRUE)]
  paste(ifelse(starts == ends, starts, paste0(starts, "-", ends)), collapse = ", ")
}

# Every R line this branch adds must be run by a test (a coverage limit alone lets a branch add untested code while
# the total stays above it). Lines covr doesn't count, such as comments and `# nocov` lines, are left out.
step_new_lines <- function(uses, log, state) {
  checkmate::assert_list(uses, types = "logical")
  checkmate::assert_string(log)
  checkmate::assert_environment(state)
  if (!uses$tests) {
    return(result("SKIP", "the package has no tests/"))
  }
  if (!inherits(state$cov, "coverage")) {
    return(result("SKIP", "no coverage was measured in this run, so there is nothing to compare"))
  }
  added <- branch_added_lines()
  if (is.character(added)) {
    return(result("SKIP", added))
  }
  if (nrow(added) == 0) {
    return(result("SKIP", "this branch adds no lines in R/"))
  }
  tally <- covr::tally_coverage(state$cov, by = "line")
  tally <- stats::aggregate(value ~ filename + line, data = tally, FUN = max)
  runnable <- merge(added, tally, by.x = c("file", "line"), by.y = c("filename", "line"))
  untested <- runnable[runnable$value == 0, , drop = FALSE]
  after_failure <- if (identical(unname(state$statuses["tests"]), "FAIL")) " (from a run with failing tests)" else ""
  if (nrow(untested) == 0) {
    return(
      result(
        "PASS",
        sprintf("%d added runnable lines, every one run by a test%s", nrow(runnable), after_failure)
      )
    )
  }
  where <- vapply(
    split(untested$line, untested$file),
    line_ranges,
    character(1)
  )
  places <- paste0(names(where), ":", where)
  write(c("Added lines that no test runs:", places), log, append = TRUE)
  more <- if (length(places) > 3) sprintf(" +%d more files", length(places) - 3) else ""
  result(
    "FAIL",
    sprintf(
      "%d of %d added runnable lines run by no test: %s%s; %s%s",
      nrow(untested),
      nrow(runnable),
      paste(utils::head(places, 3), collapse = "; "),
      more,
      "test them, or mark a justified line `# nocov` with a reason",
      after_failure
    )
  )
}

# Why a step would skip for this package (NULL: it runs), for --list.
step_skip_reason <- function(step, uses) {
  checkmate::assert_string(step)
  checkmate::assert_list(uses, types = "logical")
  switch(
    step,
    air = if (!uses$air) "no air.toml",
    biome = if (!uses$biome) "no biome.json",
    lintr = if (!uses$lintr) "no .lintr",
    docs = if (!uses$roxygen) "the package doesn't use roxygen2",
    pkgdown = if (!uses$pkgdown) "no _pkgdown.yml",
    tests = if (!uses$testthat) "no tests/testthat",
    coverage = if (!uses$tests) "no tests/",
    new_lines = if (!uses$tests) "no tests/",
    check_full = NULL,
    nosuggests = if (.Platform$OS.type == "windows") "symlinks may need privileges on Windows",
    NULL
  )
}

step_pkgdown <- function(uses, log) {
  checkmate::assert_list(uses, types = "logical")
  checkmate::assert_string(log)
  if (!uses$pkgdown) {
    return(result("SKIP", "no _pkgdown.yml"))
  }
  if (!requireNamespace("pkgdown", quietly = TRUE)) {
    return(result("SKIP", "pkgdown isn't installed"))
  }
  run_logged(function() pkgdown::check_pkgdown(), log)
  result("PASS", "no problems")
}

# The package names in DESCRIPTION fields such as Imports, without R and without version limits.
description_packages <- function(fields) {
  checkmate::assert_character(fields, min.len = 1, any.missing = FALSE)
  desc <- read.dcf("DESCRIPTION", fields = fields)
  text <- paste(stats::na.omit(as.vector(desc)), collapse = ",")
  pkgs <- trimws(strsplit(gsub("\\s+", " ", text), ",", fixed = TRUE)[[1]])
  setdiff(sub(" .*$", "", pkgs[nzchar(pkgs)]), "R")
}

# A library of symlinks to what CI's no-Suggests job installs: the hard dependencies (Depends, Imports, LinkingTo)
# with everything they need, testthat when the package has tests, and the packages that build its vignettes.
# Returns its path, or NULL when symlinks cannot be made.
nosuggests_library <- function(dir, uses) {
  checkmate::assert_directory_exists(dir, access = "w")
  checkmate::assert_list(uses, types = "logical")
  builders <- description_packages("VignetteBuilder")
  roots <- unique(c(
    description_packages(c("Depends", "Imports", "LinkingTo")),
    if (uses$testthat) "testthat",
    builders,
    if (length(builders) > 0) "rmarkdown"
  ))
  base <- rownames(utils::installed.packages(priority = "base"))
  db <- utils::installed.packages()
  roots <- intersect(setdiff(roots, base), rownames(db))
  deps <- tools::package_dependencies(roots, db = db, which = c("Depends", "Imports", "LinkingTo"), recursive = TRUE)
  needed <- intersect(setdiff(unique(c(roots, unlist(deps))), base), rownames(db))
  lib <- file.path(dir, "nosuggests-lib")
  dir.create(lib, recursive = TRUE)
  for (pkg in needed) {
    linked <- suppressWarnings(file.symlink(find.package(pkg), file.path(lib, pkg)))
    if (!isTRUE(linked)) {
      return(NULL)
    }
  }
  structure(lib, linked = length(needed))
}

# R CMD check as CI's check-no-suggests job runs it, without installing anything: only the hard dependencies are on
# the library path, `_R_CHECK_FORCE_SUGGESTS_` is false and NOT_CRAN is unset, so a test that uses a Suggests
# package without guarding it fails here.
step_nosuggests <- function(uses, run_dir, log) {
  checkmate::assert_list(uses, types = "logical")
  checkmate::assert_directory_exists(run_dir, access = "w")
  checkmate::assert_string(log)
  lib <- nosuggests_library(run_dir, uses)
  if (is.null(lib)) {
    return(result("SKIP", "symlinks can't be made here (on Windows they may need privileges)"))
  }
  # R's own library is always on the library path, so a Suggests package installed there (as conda and some Docker
  # images do) can't be hidden, and a PASS would not mean anything.
  hidden <- setdiff(description_packages("Suggests"), list.files(lib))
  visible <- hidden[vapply(hidden, function(pkg) length(find.package(pkg, .Library, quiet = TRUE)) > 0, logical(1))]
  if (length(visible) > 0) {
    return(
      result(
        "SKIP",
        paste0(
          "Suggests installed in R's own library can't be hidden: ",
          toString(visible),
          " (install them in a user library to run this check)"
        )
      )
    )
  }
  tarball <- run_logged(function() pkgbuild::build(dest_path = run_dir, quiet = TRUE), log)
  check_dir <- file.path(run_dir, "nosuggests-check")
  dir.create(check_dir)
  # R CMD check is started directly, not through rcmdcheck: rcmdcheck starts it through callr, which puts R's site
  # library back on the library path, and on Debian and Ubuntu (apt, r2u) that is where every package is installed.
  nowhere <- file.path(run_dir, "no-library")
  run <- processx::run(
    file.path(R.home("bin"), "R"),
    c("CMD", "check", "--no-manual", if (!gate_internal()) "--as-cran", normalizePath(tarball)),
    wd = check_dir,
    env = c(
      "current",
      R_LIBS = as.character(lib),
      R_LIBS_USER = nowhere,
      R_LIBS_SITE = nowhere,
      `_R_CHECK_FORCE_SUGGESTS_` = "false",
      `_R_CHECK_CRAN_INCOMING_` = "false",
      `_R_CHECK_CRAN_INCOMING_REMOTE_` = "false",
      `_R_CHECK_SYSTEM_CLOCK_` = "false",
      NOT_CRAN = ""
    ),
    error_on_status = FALSE,
    stderr_to_stdout = TRUE
  )
  write(run$stdout, log, append = TRUE)
  pkg <- read.dcf("DESCRIPTION", fields = "Package")[[1]]
  check_log <- file.path(check_dir, paste0(pkg, ".Rcheck"), "00check.log")
  # A check that stopped part-way leaves a log without its Status line, and parsing it would find no problems.
  if (!file.exists(check_log) || !any(grepl("^Status: ", readLines(check_log, warn = FALSE)))) {
    lines <- strsplit(run$stdout, "\n", fixed = TRUE)[[1]]
    lines <- lines[nzchar(trimws(lines))]
    return(result("FAIL", paste0("R CMD check stopped before the end: ", trimws(utils::tail(lines, 1)))))
  }
  res <- rcmdcheck::parse_check(check_log)
  # Hiding the Suggests is the point of this check, so the note that lists them is expected; any other note counts.
  expected <- grepl(
    "^checking package dependencies \\.\\.\\. NOTE\\s+Packages? suggested but not available for checking:",
    res$notes
  ) &
    lengths(regmatches(res$notes, gregexpr("\n", res$notes))) <= 2
  res$notes <- res$notes[!expected]
  out <- check_result(res, log)
  hidden <- if (any(expected)) "; the Suggests were hidden" else ""
  result(out$status, paste0(out$detail, " (", attr(lib, "linked"), " packages on the library path", hidden, ")"))
}

step_tarball <- function(settings, log) {
  checkmate::assert_list(settings)
  checkmate::assert_string(log)
  path <- run_logged(function() pkgbuild::build(dest_path = tempdir(), quiet = TRUE), log)
  size_mb <- file.size(path) / 1024^2
  pkg <- read.dcf("DESCRIPTION", fields = "Package")[[1]]
  shipped <- utils::untar(path, list = TRUE)
  inst <- if (dir.exists("inst")) list.files("inst", recursive = TRUE, all.files = TRUE) else character()
  absent <- inst[!file.path(pkg, "inst", inst) %in% shipped]
  problems <- character()
  if (size_mb > settings$tarball_mb) {
    problems <- c(
      problems,
      sprintf("%.2f MB is over the %g MB limit (CRAN: under 10 MB)", size_mb, settings$tarball_mb)
    )
  }
  if (length(absent) > 0) {
    problems <- c(problems, paste0("inst/ files not in the tarball: ", toString(absent)))
  }
  if (length(problems) > 0) {
    return(result("FAIL", paste(problems, collapse = "; ")))
  }
  result("PASS", sprintf("%.2f MB (limit %g MB), %d inst/ files shipped", size_mb, settings$tarball_mb, length(inst)))
}

run_step <- function(step, mode, update, uses, settings, run_dir, log, state) {
  checkmate::assert_string(step)
  checkmate::assert_choice(mode, modes)
  checkmate::assert_flag(update)
  checkmate::assert_list(uses, types = "logical")
  checkmate::assert_list(settings)
  checkmate::assert_directory_exists(run_dir)
  checkmate::assert_string(log)
  checkmate::assert_environment(state)
  tryCatch(
    switch(
      step,
      tools = step_tools(mode, uses),
      air = step_air(uses, settings, log),
      biome = step_biome(uses, log),
      docs = step_docs(uses, log),
      lintr = step_lintr(uses, settings, log),
      value = step_value(log),
      spelling = step_spelling(update, log),
      pkgdown = step_pkgdown(uses, log),
      check_fast = step_check(tests = FALSE, log),
      tests = step_tests(uses, run_dir, log, state),
      coverage = step_coverage(uses, settings, log, state),
      new_lines = step_new_lines(uses, log, state),
      check_full = step_check(tests = TRUE, log),
      nosuggests = step_nosuggests(uses, run_dir, log),
      tarball = step_tarball(settings, log)
    ),
    error = function(e) result("FAIL", conditionMessage(e))
  )
}

# The versions that decide what the steps report (R and the tools; a different roxygen2 or lintr can change a
# result), so two runs that disagree can be compared. NA for what isn't installed.
tool_versions <- function() {
  pkgs <- c("devtools", "roxygen2", "lintr", "testthat", "covr", "rcmdcheck", "spelling", "pkgdown")
  installed <- vapply(
    pkgs,
    function(pkg) {
      if (requireNamespace(pkg, quietly = TRUE)) as.character(utils::packageVersion(pkg)) else NA_character_
    },
    character(1)
  )
  external <- vapply(
    c(air = "air", biome = "biome"),
    function(tool) {
      if (!nzchar(Sys.which(tool))) {
        return(NA_character_)
      }
      out <- suppressWarnings(tryCatch(system2(tool, "--version", stdout = TRUE, stderr = TRUE), error = function(e) {
        ""
      }))
      trimws(sub("^[^0-9]*", "", out[1]))
    },
    character(1)
  )
  c(R = paste(R.version$major, R.version$minor, sep = "."), platform = R.version$platform, installed, external)
}

# gate.json in the run folder: the mode and one row per step (status, seconds, detail). Rewritten after every step,
# so a gate that is stopped part-way still leaves the steps it finished.
write_gate_json <- function(run_dir, mode, rows, versions = NULL) {
  checkmate::assert_directory_exists(run_dir, access = "w")
  checkmate::assert_string(mode)
  checkmate::assert_data_frame(rows)
  checkmate::assert_character(versions, names = "unique", null.ok = TRUE)
  if (!requireNamespace("jsonlite", quietly = TRUE)) {
    return(invisible(FALSE)) # the tools step names jsonlite as missing
  }
  jsonlite::write_json(
    list(mode = mode, run_folder = run_dir, commit = git_head(), versions = as.list(versions), steps = rows),
    file.path(run_dir, "gate.json"),
    auto_unbox = TRUE,
    pretty = TRUE,
    digits = NA
  )
  invisible(TRUE)
}

# What to read after a FAIL: the first 10 test problems, then the last lines of each failed step's log (the whole log
# on CI, where the run folder isn't visible afterwards).
failure_report <- function(failed, run_dir, state, whole_logs) {
  checkmate::assert_character(failed, any.missing = FALSE)
  checkmate::assert_directory_exists(run_dir)
  checkmate::assert_environment(state)
  checkmate::assert_flag(whole_logs)
  out <- character()
  bad <- state$tests$bad
  if ("tests" %in% failed && !is.null(bad) && nrow(bad) > 0) {
    cascade <- state$tests$cascade
    heading <- sprintf(
      "---- tests: the first %d of %d problems (all in tests.json) ----",
      min(10, nrow(bad)),
      nrow(bad)
    )
    if (!is.null(cascade)) {
      # One line for the cascade, then its first 3 failures and the first failures it doesn't cover.
      others <- bad[!cascade$rows, , drop = FALSE]
      heading <- c(
        paste0("---- tests: ", cascade_text(cascade), " ----"),
        sprintf(
          "---- tests: its first 3, then the first %d of the %d other problems (all in tests.json) ----",
          min(7, nrow(others)),
          nrow(others)
        )
      )
      bad <- rbind(utils::head(bad[cascade$rows, , drop = FALSE], 3), others)
    }
    out <- c(out, heading, issue_text(utils::head(bad, 10)))
  }
  for (step in failed) {
    log <- file.path(run_dir, paste0(step, ".log"))
    lines <- if (file.exists(log)) readLines(log, warn = FALSE) else character()
    if (length(lines) == 0) {
      next
    }
    if (whole_logs) {
      out <- c(out, sprintf("---- %s: log ----", step), lines)
    } else {
      out <- c(out, sprintf("---- %s: the last lines of %s.log ----", step, step), utils::tail(lines, 20))
    }
  }
  out
}

usage_lines <- c(
  "Usage: Rscript quality-gate.R [fast|tests|full|lint|nosuggests] [options]",
  "",
  "  fast        tools, style, docs in sync, \\value, spelling, pkgdown, R CMD check --as-cran without tests (default)",
  "  tests       tools, the tests under covr (once), coverage and the lines this branch adds",
  "  full        everything: fast steps, tests, coverage, CRAN-like check with tests, no-Suggests check, tarball",
  "  lint        the quick static steps only",
  "  nosuggests  R CMD check with only the hard dependencies on the library path (CI's check-no-suggests job)",
  "",
  "Options:",
  "  --steps a,b    run only these steps of the mode (tools always runs); the run is marked PARTIAL",
  "  --filter RE    run only the test files whose names match RE, plainly, without coverage; PARTIAL",
  "  --no-coverage  run the tests plainly, without covr and without coverage; PARTIAL",
  "  --no-retry     do not re-run failing test files once",
  "  --out DIR      the folder for the run folders (default: QUALITY_GATE_OUT, else quality-gate/ in the system temp folder)",
  "  --list         show the steps of each mode and which ones this package would skip, then stop",
  "  --update-wordlist  add the unknown words found by the spelling step to inst/WORDLIST",
  "  --help         this text",
  "",
  "Exit codes: 0 every step passed or skipped; 1 a step failed; 2 usage, settings or tools problem (the gate could",
  "not judge the package); 3 the only failures are tests that passed on the re-run (a person decides)."
)

# The command line as a list; `error` is a message when the arguments don't make sense (the gate then exits 2).
parse_args <- function(args) {
  checkmate::assert_character(args, any.missing = FALSE)
  opts <- list(
    mode = "fast",
    update = FALSE,
    no_coverage = FALSE,
    no_retry = FALSE,
    steps = character(),
    filter = NULL,
    out = NULL,
    list = FALSE,
    help = FALSE,
    error = NULL
  )
  value_flags <- c("--steps", "--filter", "--out")
  modes_given <- character()
  i <- 1L
  while (i <= length(args)) {
    arg <- args[[i]]
    key <- sub("=.*$", "", arg)
    if (key %in% value_flags) {
      if (grepl("=", arg, fixed = TRUE)) {
        value <- sub("^[^=]*=", "", arg)
      } else if (i < length(args)) {
        i <- i + 1L
        value <- args[[i]]
      } else {
        opts$error <- paste(key, "needs a value")
        return(opts)
      }
      switch(
        key,
        `--steps` = {
          opts$steps <- strsplit(value, ",", fixed = TRUE)[[1]]
        },
        `--filter` = {
          opts$filter <- value
        },
        `--out` = {
          opts$out <- value
        }
      )
    } else if (arg == "--update-wordlist") {
      opts$update <- TRUE
    } else if (arg == "--no-coverage") {
      opts$no_coverage <- TRUE
    } else if (arg == "--no-retry") {
      opts$no_retry <- TRUE
    } else if (arg == "--list") {
      opts$list <- TRUE
    } else if (arg == "--help" || arg == "-h") {
      opts$help <- TRUE
    } else if (startsWith(arg, "-")) {
      opts$error <- paste("unknown option", arg)
      return(opts)
    } else if (arg %in% modes) {
      modes_given <- c(modes_given, arg)
    } else {
      opts$error <- paste0("unknown mode '", arg, "' (one of ", toString(modes), ")")
      return(opts)
    }
    i <- i + 1L
  }
  if (length(modes_given) > 1) {
    opts$error <- "give one mode only"
    return(opts)
  }
  if (length(modes_given) == 1) {
    opts$mode <- modes_given
  }
  unknown <- setdiff(opts$steps, steps_for(opts$mode))
  if (length(unknown) > 0) {
    opts$error <- paste0(
      "--steps names ",
      toString(unknown),
      ", which mode '",
      opts$mode,
      "' doesn't run (it runs ",
      toString(steps_for(opts$mode)),
      ")"
    )
  }
  opts
}

# --list: each mode's steps, with the ones this package would skip and why.
list_steps <- function(uses) {
  checkmate::assert_list(uses, types = "logical")
  out <- character()
  for (mode in modes) {
    steps <- steps_for(mode)
    why <- vapply(
      steps,
      function(step) {
        reason <- step_skip_reason(step, uses)
        if (is.null(reason)) "" else paste0(" (skips: ", reason, ")")
      },
      character(1)
    )
    out <- c(out, paste0(mode, ": ", paste0(steps, why, collapse = ", ")))
  }
  out
}

main <- function(args) {
  checkmate::assert_character(args, any.missing = FALSE)
  opts <- parse_args(args)
  if (opts$help) {
    cli::cat_line(usage_lines)
    quit(status = 0)
  }
  if (!is.null(opts$error)) {
    cli::cat_line("FAIL usage: ", opts$error)
    cli::cat_line("Run with --help for the options.")
    quit(status = 2)
  }
  update <- opts$update
  mode <- opts$mode
  if (!file.exists("DESCRIPTION")) {
    cli::cli_abort("Run the gate from the package root (no DESCRIPTION in {.path {getwd()}}).")
  }
  settings <- tryCatch(read_settings(), error = function(e) conditionMessage(e))
  if (is.character(settings)) {
    cli::cat_line("FAIL settings: ", settings, " (fix the Config/quality-gate fields in DESCRIPTION)")
    cli::cat_line("FAILED: settings")
    quit(status = 2)
  }
  uses <- package_uses()
  if (opts$list) {
    cli::cat_line(list_steps(uses))
    quit(status = 0)
  }
  # --no-coverage leaves out what CI's coverage job measures, so in the modes that measure it the run is partial too.
  partial <- length(opts$steps) > 0 || !is.null(opts$filter) || (opts$no_coverage && mode %in% c("tests", "full"))
  run_dir <- run_folder(if (is.null(opts$out)) default_out() else opts$out, mode)
  state <- new.env()
  state$statuses <- character()
  state$mode <- mode
  state$no_coverage <- opts$no_coverage || !is.null(opts$filter)
  state$no_retry <- opts$no_retry
  state$filter <- opts$filter
  state$flaky <- FALSE
  rows <- data.frame(step = character(), status = character(), seconds = numeric(), detail = character())
  versions <- NULL
  cli::cli_h1("Quality gate: {mode}")
  cli::cat_line("Run folder: ", run_dir)
  ran <- steps_for(mode)
  if (length(opts$steps) > 0) {
    ran <- ran[ran %in% c("tools", opts$steps)]
  }
  for (step in ran) {
    log <- file.path(run_dir, paste0(step, ".log"))
    file.create(log)
    started <- Sys.time()
    res <- run_step(step, mode, update, uses, settings, run_dir, log, state)
    secs <- as.numeric(difftime(Sys.time(), started, units = "secs"))
    state$statuses[step] <- res$status
    rows[nrow(rows) + 1L, ] <- list(step, res$status, round(secs, 1), res$detail)
    if (step == "tools") {
      versions <- tool_versions()
    }
    write_gate_json(run_dir, mode, rows, versions)
    detail <- if (nzchar(res$detail)) paste0(": ", res$detail) else ""
    cli::cat_line(sprintf("%-4s %-10s (%3.0fs)%s", res$status, step, secs, detail))
    if (step == "tools" && res$status == "FAIL") {
      break
    }
  }
  statuses <- state$statuses
  failed <- names(statuses)[statuses == "FAIL"]
  cli::cat_line("Run folder: ", run_dir)
  if (partial) {
    cli::cat_line(
      "PARTIAL: only ",
      toString(ran),
      if (!is.null(opts$filter)) paste0(", tests filtered by '", opts$filter, "'") else "",
      if (opts$no_coverage && is.null(opts$filter)) ", without coverage" else "",
      " ran; this is not merge evidence."
    )
  }
  if (length(failed) > 0) {
    cli::cat_line(failure_report(failed, run_dir, state, whole_logs = identical(Sys.getenv("CI"), "true")))
    code <- exit_code(failed, isTRUE(state$flaky))
    note <- if (code == 3L) " (every failing test passed on the re-run: a probable flake, exit code 3)" else ""
    cli::cat_line("FAILED: ", paste(failed, collapse = ", "), note)
    quit(status = code)
  }
  cli::cat_line("All steps passed (", sum(statuses == "SKIP"), " skipped)", if (partial) "; partial run." else ".")
  invisible(statuses)
}

# The gate itself needs checkmate and cli: say so plainly, in base R, when they're missing.
ensure_gate_packages <- function() {
  pkgs <- c("checkmate", "cli")
  absent <- pkgs[!vapply(pkgs, requireNamespace, logical(1), quietly = TRUE)]
  if (length(absent) > 0) {
    message("FAIL tools: missing R packages ", toString(absent), "; .libPaths()[1] = ", .libPaths()[1])
    message("FAILED: tools")
    quit(status = 2)
  }
}

# Run only under Rscript: sourcing the file (as the self-test does) defines the functions without running the gate.
if (sys.nframe() == 0L) {
  ensure_gate_packages()
  main(commandArgs(trailingOnly = TRUE))
}
