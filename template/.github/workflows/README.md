# How CI works here

Each file in this folder is one check. The check itself lives in the launchR repository and this file only says when
and where it runs, so it stays short. Nothing needs installing: GitHub runs these by itself.

| File | What it does |
| --- | --- |
| `r-cmd-check.yaml` | R CMD check, the core check |
| `lint.yaml` | Style, docs in sync and spelling |
| `no-suggests.yaml` | Checks the package works without its optional packages |
| `secret-scan.yaml` | Catches passwords and tokens committed by mistake |
| `coverage.yaml` | Measures how much code your tests run |
| `off-cran-tests.yaml` | Runs the tests CRAN skips: browser, snapshot and extended test files, with Chrome |
| `extended-tests.yaml` | A full check on other systems, including any detailed tests you have marked |

Your package may not have all of these: a missing file means that check is off.

## Changing a check

- **Which branches or times:** edit the `on:` block at the top of the file. Times are UTC.
- **Which systems and R versions:** edit `platforms` under `with:`.
- **Turn a check off:** delete its file.
- **Keep a check but run it only by hand:** keep only `workflow_dispatch:` under `on:`.
- **Keep the `permissions:` block as it is:** a check that reports on pull requests needs what it lists, or it stops before it starts.

Scheduled runs use the default branch only, and GitHub pauses them on public repositories after 60 days with no activity.

## Test file kinds

Most tests go in `tests/testthat/test-<name>.R` and run everywhere. Three kinds of file, named by their ending, run
only where they can:

| File name ends in | What it holds | Runs in |
| --- | --- | --- |
| `-browser.R` | Tests that drive a browser (shinytest2, chromote) | `off-cran-tests` |
| `-snap.R` | Snapshot tests (`expect_snapshot()`) | `off-cran-tests` |
| `-extended.R` | Slow or detailed tests | `off-cran-tests`, `coverage`, `extended-tests` |

CRAN and `r-cmd-check` skip all three. Snapshot tests skip on CRAN by themselves. Start each browser or extended file
with a skip, so it skips there too:

```r
skip_on_cran()                                                    # -browser.R files
skip_if_not(identical(Sys.getenv("EXTENDED_TESTS"), "true"))      # -extended.R files
```

## The time limit

`r-cmd-check` fails when the tests take longer than `test-time-limit` seconds on Linux with R release (180 by default;
0 turns it off). CRAN asks for quick checks. Move slow tests to a `-extended.R` file, or make them faster.

## Run the checks on your computer

The quality gate runs most of these checks locally: style, docs in sync, spelling, tests, coverage and R CMD check as
CRAN runs it. From the package's folder, in R:

```r
gate <- tempfile(fileext = ".R")
download.file("https://raw.githubusercontent.com/insightsurge/launchR/v{{kit_version}}/quality-gate/quality-gate.R", gate)
system2(file.path(R.home("bin"), "Rscript"), c(gate, "full"))
```

Use `fast` instead of `full` for a quicker run. It prints one PASS or FAIL line per step.

## Updates

Dependabot opens a pull request when launchR has a new version, and changes only the `@v...` part of these files. It
waits 3 days after a release by default; a `cooldown` block in `.github/dependabot.yml` changes that.

- To decline one version, close the pull request.
- To stop for good, comment `@dependabot ignore this dependency` on it, or delete `.github/dependabot.yml`.

Your CI keeps working on the old version either way.

## Leaving launchR

To keep your own copy of the checks, for example if your organisation blocks outside workflows, run launchR's `eject`
command. The checks then live in this repository and nothing depends on launchR.
