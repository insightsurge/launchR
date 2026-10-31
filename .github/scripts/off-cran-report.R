# Writes the off-CRAN tests' part of the pull request's CI report, for one R version: the counts (with the tests in
# browser, snapshot and extended files), the failing and skipped tests, the slowest test files and the files that got
# slower than on main. Sourced by off-cran-tests.yaml's test step, which runs the tests with file_time_reporter and
# calls write_off_cran_report(results, reporter$seconds(), reporter$elapsed()) before it decides whether the job
# fails.
# Environment: R_LABEL (the matrix's R version), OUT (the Markdown part), TIMINGS (a CSV of seconds per file, kept
# from main runs), BASELINE_DIR, BASELINE_FOUND and BASELINE_SHA (main's timings, from main-baseline).

# A file counts as slower when it takes at least this much longer than on main, both relatively and in seconds.
slower_ratio <- 1.25
slower_seconds <- 10

# testthat's parallel progress reporter (a line per file as it finishes, with its time) that also keeps each file's
# elapsed time. Two processes run the files at once, and in a parallel run the results' own test times are
# about zero, so the times come from when each file's first event and its end arrive (testthat sends a parallel
# reporter the events as they happen).
file_time_reporter <- R6::R6Class(
  "FileTimeReporter",
  inherit = testthat::ParallelProgressReporter,
  public = list(
    starts = list(),
    ends = list(),
    current = NA_character_,
    began = NULL,
    finished = NULL,
    start_reporter = function() {
      self$began <- Sys.time()
      super$start_reporter()
    },
    end_reporter = function() {
      self$finished <- Sys.time()
      super$end_reporter()
    },
    # How long the whole run took, start to end (shorter than the files' sum: two run at once).
    elapsed = function() as.numeric(difftime(self$finished, self$began, units = "secs")),
    start_file = function(file) {
      self$current <- file
      if (is.null(self$starts[[file]])) {
        self$starts[[file]] <- Sys.time()
      }
      super$start_file(file)
    },
    end_file = function() {
      self$ends[[self$current]] <- Sys.time()
      super$end_file()
    },
    seconds = function() {
      files <- intersect(names(self$starts), names(self$ends))
      secs <- vapply(files, function(f) as.numeric(difftime(self$ends[[f]], self$starts[[f]], units = "secs")), 1)
      data.frame(file = files, seconds = unname(secs))
    }
  )
)

# Seconds as minutes ("14.1 min"), or as seconds under a minute ("42 s").
duration <- function(seconds) {
  ifelse(seconds >= 60, sprintf("%.1f min", seconds / 60), sprintf("%.0f s", seconds))
}

# The first lines of a test's message, on one line for a table cell.
short_message <- function(message) {
  lines <- utils::head(strsplit(message, "\n", fixed = TRUE)[[1]], 3)
  text <- paste(trimws(lines), collapse = " ")
  text <- gsub("|", "\\|", text, fixed = TRUE)
  if (nchar(text) > 200) paste0(substr(text, 1, 200), "...") else text
}

# One row per failing, erroring or skipped test, with its first such message.
problem_rows <- function(results, classes) {
  rows <- lapply(results, function(test) {
    hits <- Filter(function(e) inherits(e, classes), test$results)
    if (length(hits) == 0) {
      return(NULL)
    }
    data.frame(file = test$file, test = test$test, message = short_message(conditionMessage(hits[[1]])))
  })
  do.call(rbind, c(list(data.frame(file = character(), test = character(), message = character())), rows))
}

# At most `max` rows, then a line saying how many were left out (the job's log has them all).
table_lines <- function(rows, max = 30) {
  shown <- utils::head(rows, max)
  test <- gsub("|", "\\|", shown$test, fixed = TRUE)
  c(
    "| File | Test | Message |",
    "| :--- | :--- | :--- |",
    sprintf("| `%s` | %s | %s |", shown$file, test, shown$message),
    if (nrow(rows) > max) c("", sprintf("And %d more: see the job's log.", nrow(rows) - max))
  )
}

plural <- function(n, word) sprintf("%d %s%s", n, word, if (n == 1) "" else "s")

# A collapsed section; `open` shows it expanded (for failures, which need acting on).
details <- function(summary, body, open = FALSE) {
  c(if (open) "<details open>" else "<details>", sprintf("<summary>%s</summary>", summary), "", body, "", "</details>")
}

# `silent`: the selected files that reported no test, which skipped as a whole (a file skipped from its first line).
write_off_cran_report <- function(results, timings, elapsed = NA_real_, silent = character()) {
  label <- Sys.getenv("R_LABEL")
  frame <- as.data.frame(results)
  utils::write.csv(timings, Sys.getenv("TIMINGS"), row.names = FALSE)

  failed <- problem_rows(results, c("expectation_failure", "expectation_error"))
  skipped <- problem_rows(results, "expectation_skip")
  passed <- nrow(frame) - nrow(failed) - nrow(skipped)
  ok <- nrow(failed) == 0 && nrow(skipped) == 0 && length(silent) == 0
  # The tests in each kind of file: test-<name>-browser.R, -snap.R and -extended.R.
  kind <- factor(
    sub("^.*-(browser|snap|extended)[.]R$", "\\1", frame$file),
    levels = c("browser", "snap", "extended"),
    labels = c("browser", "snapshot", "extended")
  )
  kinds <- table(kind)
  first <- sprintf(
    "%s **Off-CRAN tests, R %s:** %d passed · %d failed · %d skipped%s · %s%s",
    if (ok) "\u2705" else "\u274c",
    label,
    passed,
    nrow(failed),
    nrow(skipped),
    if (is.na(elapsed)) "" else paste0(" · ", duration(elapsed)),
    paste0(kinds, " in ", names(kinds), " files", collapse = ", "),
    if (nrow(skipped) > 0 || length(silent) > 0) " (a skip fails this job: these tests must run)" else ""
  )
  out <- first
  if (nrow(failed) > 0) {
    out <- c(out, "", details(plural(nrow(failed), "failing test"), table_lines(failed), open = TRUE))
  }
  if (nrow(skipped) > 0) {
    out <- c(out, "", details(plural(nrow(skipped), "skipped test"), table_lines(skipped), open = TRUE))
  }
  if (length(silent) > 0) {
    out <- c(
      out,
      "",
      details(
        sprintf("%d file%s where no test ran", length(silent), if (length(silent) == 1) "" else "s"),
        sprintf("- `%s`", silent),
        open = TRUE
      )
    )
  }

  slowest <- utils::head(timings[order(-timings$seconds), ], 5)
  timing_rows <- sprintf("| `%s` | %s |", slowest$file, duration(slowest$seconds))
  timing_body <- c("| File | Time |", "| :--- | ---: |", timing_rows)
  if (!identical(Sys.getenv("BASELINE_FOUND"), "true") && identical(Sys.getenv("GITHUB_EVENT_NAME"), "pull_request")) {
    timing_body <- c(timing_body, "", "_No test times from `main` to compare with._")
  }
  if (identical(Sys.getenv("BASELINE_FOUND"), "true")) {
    base_file <- file.path(Sys.getenv("BASELINE_DIR"), basename(Sys.getenv("TIMINGS")))
    if (file.exists(base_file)) {
      base <- utils::read.csv(base_file)
      both <- merge(timings, base, by = "file", suffixes = c("", "_main"))
      slower <- both[
        both$seconds >= both$seconds_main * slower_ratio &
          both$seconds - both$seconds_main >= slower_seconds,
      ]
      sha <- substr(Sys.getenv("BASELINE_SHA"), 1, 7)
      timing_body <- c(
        timing_body,
        "",
        if (nrow(slower) == 0) {
          sprintf("No file is much slower than on `main` at %s.", sha)
        } else {
          c(
            sprintf("Slower than on `main` at %s:", sha),
            "",
            "| File | Here | `main` |",
            "| :--- | ---: | ---: |",
            sprintf("| `%s` | %s | %s |", slower$file, duration(slower$seconds), duration(slower$seconds_main))
          )
        }
      )
    }
  }
  out <- c(
    out,
    "",
    details(
      sprintf(
        "Slowest test files, R %s (%d files add up to %s; two run at once)",
        label,
        nrow(timings),
        duration(sum(timings$seconds))
      ),
      timing_body
    )
  )
  writeLines(out, Sys.getenv("OUT"))
}
