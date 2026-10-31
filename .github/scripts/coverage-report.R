# Writes the coverage part of the pull request's CI report (test-coverage.yaml): the figure and its limit, the
# difference from main, and on a pull request the added R/ lines that the job's tests don't run. The untested lines
# are a report only: the gate's new_lines step is the check, run locally. The job's tests skip the browser and
# snapshot tests, so a line listed here may still be run by one of them.
# Environment: COV_DIR (coverage.dcf and coverage.rds from the coverage step), BASELINE_DIR (coverage.dcf from main,
# when BASELINE_FOUND is true), BASELINE_SHA, EVENT_NAME, OUT (the Markdown part to write).

env <- function(name) Sys.getenv(name)

read_figures <- function(dir) {
  file <- file.path(dir, "coverage.dcf")
  if (!file.exists(file)) {
    return(NULL)
  }
  figures <- read.dcf(file)
  list(
    percent = as.numeric(figures[1, "Percent"]),
    limit = as.numeric(figures[1, "Limit"]),
    passed = as.logical(figures[1, "Passed"])
  )
}

# The lines a unified diff with no context adds, per file (the same reading as the gate's added_lines_in_diff()).
added_lines <- function(diff) {
  rows <- list()
  file <- NA_character_
  for (line in diff) {
    if (startsWith(line, "+++ ")) {
      file <- if (line == "+++ /dev/null") NA_character_ else sub("^\\+\\+\\+ b/", "", line)
    } else if (startsWith(line, "@@ ") && !is.na(file)) {
      hunk <- regmatches(line, regexec("\\+([0-9]+)(,([0-9]+))?", line))[[1]]
      count <- if (nzchar(hunk[4])) as.integer(hunk[4]) else 1L
      if (count > 0) {
        rows[[length(rows) + 1L]] <- data.frame(file = file, line = seq(as.integer(hunk[2]), length.out = count))
      }
    }
  }
  do.call(rbind, c(list(data.frame(file = character(), line = integer())), rows))
}

# 3, 4, 5, 9 -> "3-5, 9".
line_ranges <- function(lines) {
  lines <- sort(unique(lines))
  starts <- lines[c(TRUE, diff(lines) != 1)]
  ends <- lines[c(diff(lines) != 1, TRUE)]
  paste(ifelse(starts == ends, starts, paste0(starts, "-", ends)), collapse = ", ")
}

# The pull request's merge commit (HEAD) against its base (HEAD^1): the checkout has fetch-depth 2.
untested_lines <- function(cov) {
  diff <- system2(
    "git",
    c("diff", "--unified=0", "--no-color", "--no-ext-diff", "HEAD^1", "HEAD", "--", "R/"),
    stdout = TRUE
  )
  added <- added_lines(diff)
  if (nrow(added) == 0) {
    return(NULL)
  }
  # covr counts expressions; tally them by line, keeping a line run when any expression on it ran.
  tally <- covr::tally_coverage(cov, by = "line")
  tally <- stats::aggregate(value ~ filename + line, data = tally, FUN = max)
  runnable <- merge(added, tally, by.x = c("file", "line"), by.y = c("filename", "line"))
  runnable[runnable$value == 0, c("file", "line"), drop = FALSE]
}

untested_text <- function(cov) {
  untested <- untested_lines(cov)
  if (is.null(untested)) {
    return("_This pull request adds no lines in `R/`._")
  }
  if (nrow(untested) == 0) {
    return("_Every added `R/` line that covr counts is run by the tests in this job._")
  }
  by_file <- split(untested$line, untested$file)
  rows <- vapply(names(by_file), function(f) sprintf("| `%s` | %s |", f, line_ranges(by_file[[f]])), character(1))
  shown <- utils::head(rows, 50)
  c(
    "<details>",
    sprintf(
      paste(
        "<summary>%d added <code>R/</code> line%s not run by the tests in this job",
        "(browser and snapshot tests excluded; a report, not a check)</summary>"
      ),
      nrow(untested),
      if (nrow(untested) == 1) "" else "s"
    ),
    "",
    "| File | Lines |",
    "| :--- | :--- |",
    shown,
    if (length(rows) > length(shown)) sprintf("\nAnd %d more files.", length(rows) - length(shown)),
    "",
    "</details>"
  )
}

coverage_report <- function() {
  figures <- read_figures(env("COV_DIR"))
  if (is.null(figures)) {
    "\u274c **Coverage:** not measured: the tests failed before covr finished (see the run's log)."
  } else {
    versus <- if (identical(env("EVENT_NAME"), "pull_request")) " · no figure from `main` yet" else ""
    if (identical(env("BASELINE_FOUND"), "true")) {
      base <- read_figures(env("BASELINE_DIR"))
      if (!is.null(base)) {
        versus <- sprintf(
          " · **%+.1f** points from `main` at %s (%.1f%%)",
          figures$percent - base$percent,
          substr(env("BASELINE_SHA"), 1, 7),
          base$percent
        )
      }
    }
    verdict <- if (isTRUE(figures$passed)) "" else " · **Under the limit: the job fails.**"
    first <- sprintf(
      "%s **Coverage:** %.1f%% of R lines, without the browser and snapshot tests · limit %g%% (from `DESCRIPTION`)%s%s",
      if (isTRUE(figures$passed)) "\u2705" else "\u274c",
      figures$percent,
      figures$limit,
      versus,
      verdict
    )
    cov_file <- file.path(env("COV_DIR"), "coverage.rds")
    if (identical(env("EVENT_NAME"), "pull_request") && file.exists(cov_file)) {
      c(first, "", untested_text(readRDS(cov_file)))
    } else {
      first
    }
  }
}

# A fault in the report must not decide the job: the coverage step does.
out <- tryCatch(coverage_report(), error = function(e) {
  message("::warning::The coverage report failed: ", conditionMessage(e))
  sprintf("\u26a0\ufe0f **Coverage:** the report failed (%s); the job's log has the figure.", conditionMessage(e))
})
writeLines(out, env("OUT"))
