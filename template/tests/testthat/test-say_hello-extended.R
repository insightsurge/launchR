# Extended tests: slow or detailed ones that CRAN and R CMD check skip. On your computer they run when the
# package's .Renviron sets EXTENDED_TESTS=true; which checks run them: tests/README.md.
skip_if_not(
  identical(Sys.getenv("EXTENDED_TESTS"), "true"),
  "an extended test: it runs when EXTENDED_TESTS is true (tests/README.md)"
)

test_that("say_hello() greets every name in a long list", {
  people <- paste0("person", seq_len(1000))
  greetings <- vapply(people, say_hello, character(1), USE.NAMES = FALSE)
  expect_identical(greetings, paste0("Hello, ", people, "!"))
})
