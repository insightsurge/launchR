# Extended tests: slow or detailed ones that CRAN and R-CMD-check skip. They run in full-tests, coverage and
# r-cmd-check-extended, and locally with Sys.setenv(EXTENDED_TESTS = "true") (tests/README.md).
skip_if_not(identical(Sys.getenv("EXTENDED_TESTS"), "true"))

test_that("say_hello() greets every name in a long list", {
  people <- paste0("person", seq_len(1000))
  greetings <- vapply(people, say_hello, character(1), USE.NAMES = FALSE)
  expect_identical(greetings, paste0("Hello, ", people, "!"))
})
