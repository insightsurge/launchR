test_that("the demo page's button says hello in a browser", {
  skip_on_cran()
  skip_if_not_installed("chromote")
  skip_if(is.null(chromote::find_chrome()), "No Chrome on this machine")

  # Chrome can take more than chromote's default 10 seconds to start on a busy CI runner.
  old <- options(chromote.timeout = 60)
  on.exit(options(old), add = TRUE)

  page <- system.file("www", "demo.html", package = "{{package}}")
  session <- chromote::ChromoteSession$new()
  on.exit(session$close(), add = TRUE)
  session$Page$navigate(paste0("file://", page))
  Sys.sleep(1)
  session$Runtime$evaluate("document.querySelector('#hello').click()")
  text <- session$Runtime$evaluate("document.querySelector('#hello').textContent")$result$value
  expect_identical(text, "Hello!")
})
