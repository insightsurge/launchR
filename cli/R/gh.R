# Running gh, kept apart from what the callers do with the answers.
gh_available <- function() nzchar(Sys.which("gh"))

# Quotes one argument for the shell that system2() uses: sh on Mac and Linux, cmd on Windows.
quote_arg <- function(x, windows = .Platform$OS.type == "windows") {
  shQuote(x, type = if (windows) "cmd" else "sh")
}

# Waits between calls that create things, because GitHub limits how fast they may come. Tests set kit.pause to 0.
kit_pause <- function(seconds) Sys.sleep(getOption("kit.pause", seconds))

rate_limited <- function(text) grepl("rate limit|secondary|abuse|HTTP 429|retry later", text, ignore.case = TRUE)

# Returns list(ok, out, err). Never stops: the caller decides what a failure means. A rate-limit answer is retried
# after a wait that grows each time.
gh <- function(args, input = NULL, tries = 3) {
  err_file <- tempfile("gh-err")
  on.exit(unlink(err_file))
  for (attempt in seq_len(tries)) {
    out <- tryCatch(
      suppressWarnings(system2("gh", vapply(args, quote_arg, ""), stdout = TRUE, stderr = err_file, input = input)),
      error = function(e) structure(character(), status = 127L)
    )
    status <- attr(out, "status")
    ok <- is.null(status) || status == 0L
    err <- if (file.exists(err_file)) paste(readLines(err_file, warn = FALSE), collapse = "\n") else ""
    if (ok || !rate_limited(err) || attempt == tries) {
      return(list(ok = ok, out = as.character(out), err = err))
    }
    Sys.sleep(getOption("kit.retry_wait", 30) * attempt)
  }
}

# Like gh(), but a failure stops the command with gh's own message.
gh_must <- function(args, input = NULL) {
  result <- gh(args, input)
  if (!result$ok) stop(sprintf("gh %s failed: %s", paste(args[seq_len(min(2, length(args)))], collapse = " "), result$err), call. = FALSE)
  result$out
}

# What gh prints for an API call run through --jq. NA when gh can't answer (no access, no such page, offline).
gh_api_text <- function(endpoint, jq) {
  result <- gh(c("api", endpoint, "--jq", jq))
  if (!result$ok) NA_character_ else trimws(paste(result$out, collapse = "\n"))
}

# Writes text where gh can read it with --body-file. Binary mode keeps the line endings as \n on Windows.
body_file <- function(lines) {
  path <- tempfile(fileext = ".md")
  write_text(paste0(paste(lines, collapse = "\n"), "\n"), path)
  path
}
