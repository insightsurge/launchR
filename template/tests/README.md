# Tests

Tests live in `tests/testthat/`, one file per topic, named `test-<topic>.R`. Run them all with `devtools::test()`, or
in RStudio choose Build, then Test Package. Learn more: <https://r-pkgs.org/testing-basics.html>.

## Test file kinds

Most tests go in a plain `test-<topic>.R` file and run everywhere. Some tests can't run everywhere, so
they go in a file whose name ends in a kind. The examples next to each are in `tests/testthat/`:

| File name ends in | What it holds | Example | Runs in |
| --- | --- | --- | --- |
| `.R` (plain) | Quick tests that run everywhere | `test-say_hello.R` | {{runs_plain}} |
{{browser_row}}
| `-snap.R` | Snapshot tests (`expect_snapshot()`): the output is saved in `_snaps/` and compared on later runs | `test-say_hello-snap.R` | {{runs_snap}} |
| `-extended.R` | Slow or detailed tests | `test-say_hello-extended.R` | {{runs_extended}} |

{{full_tests_line}}CRAN skips every kind but the plain one. Snapshot tests
skip on CRAN by themselves; start each other file, or each test in it, with a skip line, so it skips there too:

```r
{{browser_skip}}
skip_if_not(identical(Sys.getenv("EXTENDED_TESTS"), "true"), "an extended test")   # -extended.R files
```

## On your computer

`devtools::test()` runs the plain, snapshot and browser tests. The extended ones run too when `EXTENDED_TESTS` is
`true`: the package's `.Renviron` sets it when one of your checks runs them in CI. `.Renviron` is kept out of git, so a
fresh clone doesn't have it; to run the extended tests there, add the line `EXTENDED_TESTS=true` to a `.Renviron` in
the package's folder, or run:

```r
Sys.setenv(EXTENDED_TESTS = "true")
devtools::test()
```

When a snapshot changes on purpose, accept the new one with `testthat::snapshot_accept()`, or look first with
`testthat::snapshot_review()`. Commit the files in `tests/testthat/_snaps/`: CI compares with them, and refuses to
create a missing one.
