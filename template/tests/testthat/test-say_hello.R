test_that("say_hello() greets by name", {
  expect_identical(say_hello("world"), "Hello, world!")
})

test_that("say_hello() rejects anything but one string", {
  expect_error(say_hello(1), "single string")
  expect_error(say_hello(c("a", "b")), "single string")
})
