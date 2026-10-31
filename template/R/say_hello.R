#' Say hello
#'
#' Builds a greeting. Replace this example with your package's first function.
#'
#' @param name Who to greet, as a single string.
#' @returns A single string.
#' @examples
#' say_hello("world")
#' @export
say_hello <- function(name) {
  if (!is.character(name) || length(name) != 1L || is.na(name)) {
    stop("`name` must be a single string.", call. = FALSE)
  }
  paste0("Hello, ", name, "!")
}
