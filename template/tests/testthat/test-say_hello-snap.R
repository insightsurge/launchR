# A snapshot test: the first run saves the output to _snaps/say_hello-snap.md, and later runs compare with it. Review
# a changed snapshot with testthat::snapshot_review(). They skip on CRAN; which checks run them: tests/README.md.
test_that("say_hello() explains a wrong input", {
  expect_snapshot(say_hello(1), error = TRUE)
})
