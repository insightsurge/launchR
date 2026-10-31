# The fake behind tests/fake-gh/gh. State lives in FAKE_GH_DIR:
#   repo.txt        "owner/name VISIBILITY branch"
#   labels.txt      name|color|description
#   issues.txt      number|STATE|title      body-N.md holds each body
#   subs.txt        numbers linked under the root issue
#   api/<name>.json  canned answers for `gh api`, named after the endpoint with every non-letter or digit as _
#   log.txt         every call, one per line
# Switches: FAKE_GH_SIGNED_OUT=1, FAKE_GH_RATE_LIMIT=1 (the first issue create is refused once).
args <- commandArgs(TRUE)
dir <- Sys.getenv("FAKE_GH_DIR")
path <- function(...) file.path(dir, ...)
cat(paste(args, collapse = " "), "\n", file = path("log.txt"), append = TRUE)
fail <- function(text) {
  message(text)
  quit(status = 1L)
}
opt <- function(name) {
  at <- match(name, args)
  if (is.na(at)) "" else args[at + 1]
}
read_lines <- function(file) if (file.exists(path(file))) readLines(path(file), warn = FALSE) else character()
jq <- function(file, expression) {
  out <- system2("jq", c("-r", shQuote(expression), shQuote(file)), stdout = TRUE)
  cat(out, sep = "\n")
}

if (args[1] == "auth") {
  if (nzchar(Sys.getenv("FAKE_GH_SIGNED_OUT"))) fail("You are not logged into any GitHub hosts.")
  quit(status = 0L)
}
if (args[1] == "repo" && args[2] == "view") {
  if (!file.exists(path("repo.txt"))) fail("no git remotes found")
  cat(read_lines("repo.txt"), sep = "\n")
  quit(status = 0L)
}
if (args[1] == "label" && args[2] == "list") {
  cat(read_lines("labels.txt"), sep = "\n")
  quit(status = 0L)
}
if (args[1] == "label" && args[2] == "create") {
  rows <- read_lines("labels.txt")
  rows <- rows[!startsWith(rows, paste0(args[3], "|"))]
  writeLines(c(rows, paste(args[3], opt("--color"), opt("--description"), sep = "|")), path("labels.txt"))
  quit(status = 0L)
}
if (args[1] == "issue" && args[2] == "list") {
  cat(read_lines("issues.txt"), sep = "\n")
  quit(status = 0L)
}
if (args[1] == "issue" && args[2] == "view") {
  cat(readLines(path(sprintf("body-%s.md", args[3])), warn = FALSE), sep = "\n")
  quit(status = 0L)
}
if (args[1] == "issue" && args[2] == "create") {
  flag <- path("rate-limit-done")
  if (nzchar(Sys.getenv("FAKE_GH_RATE_LIMIT")) && !file.exists(flag)) {
    file.create(flag)
    fail("HTTP 403: You have exceeded a secondary rate limit.")
  }
  rows <- read_lines("issues.txt")
  number <- length(rows) + 1L
  writeLines(c(rows, sprintf("%d|OPEN|%s", number, opt("--title"))), path("issues.txt"))
  file.copy(opt("--body-file"), path(sprintf("body-%d.md", number)), overwrite = TRUE)
  cat(sprintf("https://github.com/%s/issues/%d\n", strsplit(read_lines("repo.txt"), " ")[[1]][1], number))
  quit(status = 0L)
}
if (args[1] == "issue" && args[2] == "edit") {
  file.copy(opt("--body-file"), path(sprintf("body-%s.md", args[3])), overwrite = TRUE)
  quit(status = 0L)
}
if (args[1] == "issue" && args[2] == "close") {
  rows <- read_lines("issues.txt")
  at <- startsWith(rows, paste0(args[3], "|"))
  rows[at] <- sub("\\|OPEN\\|", "|CLOSED|", rows[at])
  writeLines(rows, path("issues.txt"))
  quit(status = 0L)
}
if (args[1] == "api") {
  endpoint <- args[grepl("^repos/", args)][1]
  if (is.na(endpoint)) fail("fake gh: no endpoint")
  if (grepl("/issues/[0-9]+/sub_issues$", endpoint) && "POST" %in% args) {
    number <- as.integer(sub("sub_issue_id=", "", opt("-F"))) - 1000L
    if (as.character(number) %in% read_lines("subs.txt")) fail("HTTP 422: Validation Failed")
    cat(number, "\n", file = path("subs.txt"), append = TRUE, sep = "")
    quit(status = 0L)
  }
  if (grepl("/issues/[0-9]+/sub_issues$", endpoint)) {
    cat(read_lines("subs.txt"), sep = "\n")
    quit(status = 0L)
  }
  if (grepl("/issues/[0-9]+$", endpoint)) {
    cat(as.integer(sub(".*/", "", endpoint)) + 1000L, "\n", sep = "")
    quit(status = 0L)
  }
  name <- gsub("[^A-Za-z0-9]", "_", sub("^repos/[^/]+/[^/]+/?", "", endpoint))
  canned <- path("api", paste0(if (nzchar(name)) name else "repo", ".json"))
  if (!file.exists(canned)) fail(paste("HTTP 404: Not Found", endpoint))
  jq(canned, opt("--jq"))
  quit(status = 0L)
}
fail(paste("fake gh doesn't know:", paste(args, collapse = " ")))
