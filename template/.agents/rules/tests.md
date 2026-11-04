# Tests

- Tests use testthat, in `tests/testthat/`, one file per R file: `R/clean.R` is tested in `test-clean.R`. Test kinds
  (browser, snapshot, extended) and how to run them are in `tests/README.md`.
- **Every new behaviour and every fixed bug gets a test.** For a bug, the test fails before the fix and passes after.
- **Every R line you add is run by a test.** The quality gate checks this. `# nocov` is only for a line that can't
  be tested, with a comment saying why.
- **Don't change or delete an existing test to make it pass.** If a test is wrong, say so and ask.
- Use made-up data. No network or files outside `tempdir()` in plain tests; anything that needs them gets a skip line
  (`skip_on_cran()`, `skip_if_offline()`).
- Clean up with `withr::local_*()`: temporary files, options and environment variables.
- **Snapshots:** commit the files in `tests/testthat/_snaps/`. Accept a changed snapshot only when the change is on
  purpose, and say so in the pull request.
- Coverage has a lower limit, set in `DESCRIPTION` (`Config/quality-gate/coverage`). Don't lower it.
