# The checks behind the automatic ticks. Each returns TRUE, FALSE, or NA when the answer can't be found (no access,
# offline, nothing to read). NA never changes a box.
kit_cache <- new.env()

cached <- function(key, compute) {
  if (!exists(key, envir = kit_cache, inherits = FALSE)) assign(key, compute(), envir = kit_cache)
  get(key, envir = kit_cache, inherits = FALSE)
}

# Fills {repo}, {owner}, {branch} and {package} in a list cell.
fill_in <- function(text, ctx) {
  for (key in c("repo", "owner", "branch", "package")) {
    text <- gsub(sprintf("{%s}", key), ctx[[key]], text, fixed = TRUE)
  }
  text
}

as_state <- function(text) {
  if (is.na(text)) NA else if (identical(text, "true")) TRUE else if (identical(text, "false")) FALSE else NA
}

tick_file <- function(target) file.exists(target)

tick_placeholder <- function(target) {
  parts <- strsplit(target, "|", fixed = TRUE)[[1]]
  file.exists(parts[1]) && !grepl(parts[2], read_text(parts[1]), fixed = TRUE)
}

# target is "endpoint|jq"; the jq expression must print true or false (or nothing, when the field is hidden).
tick_setting <- function(target, ctx) {
  if (!ctx$connected) {
    return(NA)
  }
  at <- regexpr("|", target, fixed = TRUE)
  endpoint <- fill_in(substr(target, 1, at - 1), ctx)
  jq <- fill_in(substring(target, at + 1), ctx)
  cached(paste(endpoint, jq), function() as_state(gh_api_text(endpoint, jq)))
}

# Every check run on the default branch's latest commit has finished and passed. Unfinished runs leave the box alone.
tick_ci <- function(ctx) {
  jq <- paste(
    "if (.check_runs | length) == 0 then false",
    "elif any(.check_runs[]; .status != \"completed\") then null",
    "else all(.check_runs[]; .conclusion == \"success\" or .conclusion == \"skipped\" or .conclusion == \"neutral\") end"
  )
  tick_setting(sprintf("repos/{repo}/commits/{branch}/check-runs?per_page=100|%s", jq), ctx)
}

http_status <- function(url) {
  headers <- tryCatch(suppressWarnings(curlGetHeaders(url, redirect = TRUE)), error = function(e) NULL)
  if (is.null(headers)) NA_integer_ else as.integer(attr(headers, "status"))
}

status_of <- function(url) {
  cached(paste("http", url), function() getOption("kit.http", http_status)(url))
}

# The website's address: the Pages setting when GitHub knows it, else the github.io address in DESCRIPTION's URL field.
site_url <- function(ctx) {
  url <- if (ctx$connected) gh_api_text(sprintf("repos/%s/pages", ctx$repo), ".html_url") else NA_character_
  if (!is.na(url) && nzchar(url)) {
    return(url)
  }
  field <- tryCatch(read.dcf("DESCRIPTION", fields = "URL")[[1]], error = function(e) NA_character_)
  urls <- trimws(strsplit(if (is.na(field)) "" else field, "[,\n ]+")[[1]])
  urls <- urls[grepl("github[.]io", urls)]
  if (length(urls) > 0) urls[1] else NA_character_
}

tick_site <- function(ctx) {
  url <- cached("site-url", function() site_url(ctx))
  if (is.na(url)) {
    return(NA)
  }
  status <- status_of(url)
  if (is.na(status)) NA else status == 200L
}

on_cran <- function(package) {
  status <- status_of(sprintf("https://cran.r-project.org/web/packages/%s/index.html", package))
  if (is.na(status)) NA else status == 200L
}

tick_state <- function(row, ctx) {
  switch(row$kind,
    file = tick_file(row$target),
    placeholder = tick_placeholder(row$target),
    setting = tick_setting(row$target, ctx),
    ci = tick_ci(ctx),
    site = tick_site(ctx),
    cran = on_cran(ctx$package),
    NA
  )
}
