# This file is part of the standard setup for testthat, with one addition: a cap on the test workers.
#
# Where should you do additional testing?
# Learn more about the roles of various files in:
# * https://r-pkgs.org/testing-design.html#sec-tests-files-overview
# * https://testthat.r-lib.org/articles/special-files.html

library(testthat)
library({{package}})

# CRAN allows at most two cores, and testthat takes its number of workers from getOption("Ncpus") first: a session
# that has it above two is lowered to two while the tests run.
local({
  ncpus <- suppressWarnings(as.integer(getOption("Ncpus")))
  if (length(ncpus) == 1L && !is.na(ncpus) && ncpus > 2L) {
    old <- options(Ncpus = 2L)
    on.exit(options(old))
  }
  test_check("{{package}}")
})
