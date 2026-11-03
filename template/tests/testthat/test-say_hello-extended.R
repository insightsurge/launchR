# Extended tests: slow or detailed ones that CRAN and R CMD check skip. Run them locally with
# Sys.setenv(EXTENDED_TESTS = "true"); which checks run them: tests/README.md.
skip_if_not(identical(Sys.getenv("EXTENDED_TESTS"), "true"))

test_that("say_hello() greets every name in a long list", {
  people <- paste0("person", seq_len(1000))
  greetings <- vapply(people, say_hello, character(1), USE.NAMES = FALSE)
  expect_identical(greetings, paste0("Hello, ", people, "!"))
})
