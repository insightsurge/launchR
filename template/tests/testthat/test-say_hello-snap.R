# A snapshot test: the first run saves the output to _snaps/say_hello-snap.md, and later runs compare with it. Review
# a changed snapshot with testthat::snapshot_review(). These run in full-tests, and skip on CRAN (tests/README.md).
test_that("say_hello() explains a wrong input", {
  expect_snapshot(say_hello(1), error = TRUE)
})
