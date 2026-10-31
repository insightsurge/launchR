# The one place that finds the kit's files: a clone first, an installed package second.
kit_path <- function(...) {
  root <- getOption("kit.root")
  if (!is.null(root)) {
    return(file.path(root, ...))
  }
  system.file(..., package = "rpkgkit", mustWork = TRUE)
}

read_list <- function(name) {
  utils::read.delim(
    kit_path("lists", name),
    fileEncoding = "UTF-8",
    quote = "",
    comment.char = "#",
    stringsAsFactors = FALSE,
    na.strings = character(),
    colClasses = "character"
  )
}

kit_setting <- function(key) {
  settings <- read_list("settings.tsv")
  settings$value[settings$key == key]
}

# Reads a file as UTF-8 with \n line endings, so a clone checked out with Windows line endings builds the same files.
read_text <- function(path) {
  text <- readChar(path, file.size(path), useBytes = TRUE)
  Encoding(text) <- "UTF-8"
  gsub("\r\n", "\n", text, fixed = TRUE)
}

write_text <- function(text, path) {
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  writeBin(charToRaw(enc2utf8(text)), path)
  invisible(path)
}
