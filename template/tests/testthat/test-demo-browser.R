test_that("the demo page's button says hello in a browser", {
  skip_on_cran()
  skip_if_not_installed("chromote")
  skip_if(is.null(chromote::find_chrome()), "No Chrome on this machine")

  # Chrome can take more than chromote's default 10 seconds to start on a busy CI runner.
  old <- options(chromote.timeout = 60)
  on.exit(options(old), add = TRUE)

  page <- system.file("www", "demo.html", package = "{{package}}")
  # A file URL has three slashes, and a Windows path (C:/...) goes after them: file:///C:/...
  url <- utils::URLencode(paste0("file:///", sub("^/", "", normalizePath(page, winslash = "/"))))
  session <- chromote::ChromoteSession$new()
  on.exit(session$close(), add = TRUE)
  session$Page$navigate(url)

  # Runs some JavaScript in the page and returns its value.
  evaluate <- function(js) session$Runtime$evaluate(js)$result$value
  # Waits until the JavaScript is true, for up to `seconds`, instead of sleeping a fixed time.
  wait_until <- function(js, seconds = 10) {
    deadline <- Sys.time() + seconds
    while (!isTRUE(evaluate(js)) && Sys.time() < deadline) Sys.sleep(0.1)
    isTRUE(evaluate(js))
  }
  expect_true(wait_until("document.readyState === 'complete' && document.querySelector('#hello') !== null"))
  evaluate("document.querySelector('#hello').click()")
  expect_true(wait_until("document.querySelector('#hello').textContent === 'Hello!'"))
  expect_identical(evaluate("document.querySelector('#hello').textContent"), "Hello!")
})
