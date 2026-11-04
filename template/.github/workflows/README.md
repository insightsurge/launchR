# How CI works here

Each file in this folder is one check. The check itself lives in the launchR repository and this file only says when
and where it runs, so it stays short. Nothing needs installing: GitHub runs these by itself.

| File | What it does | When it runs |
| --- | --- | --- |
{{checks_table}}
{{^has_checks}}
| None yet | Come back to the site to add one | |
{{/has_checks}}

These are the checks chosen when the package was set up. To add another later, come back to the site and choose only
that check.

{{#has_skeleton}}
Which test files each check runs: `tests/README.md`.

{{/has_skeleton}}
{{^has_skeleton}}
## Test file kinds

Most tests run in every check. Files whose name ends in a kind run only where they can:

| File name ends in | What it holds | Runs in |
| --- | --- | --- |
| `-browser.R` | Tests that drive a browser (chromote); start them with `options(chromote.timeout = 60)`, as Chrome can start slowly on CI | {{runs_browser}} |
| `-snap.R` | Snapshot tests (`expect_snapshot()`) | {{runs_snap}} |
| `-extended.R` | Slow or detailed tests | {{runs_extended}} |

Start each browser file with `skip_on_cran()` and each extended file with
`skip_if_not(identical(Sys.getenv("EXTENDED_TESTS"), "true"))`, so CRAN and R CMD check skip them.

{{/has_skeleton}}
{{#has_coverage}}
## Codecov

The coverage check decides on its own. To also show coverage on Codecov:

1. Sign in at <https://about.codecov.io> with GitHub and add this repository.
2. Copy its upload token. On GitHub, add it as a repository secret named `CODECOV_TOKEN` (Settings, then Secrets and
   variables, then Actions).
3. In `coverage.yaml`, remove the `#` before the `secrets:` and `CODECOV_TOKEN:` lines.

`codecov.yml` at the top of the package keeps Codecov to reporting: no blocking status and no second comment.

{{/has_coverage}}
## Changing a check

- **Which branches or times:** edit the `on:` block at the top of the file. Times are UTC.
- **Which systems and R versions:** edit `platforms` under `with:`.
- **How long a job may run:** `timeout-minutes` under `with:`, in minutes. 0 keeps launchR's default: 60 on Mac (its
  minutes cost ten times), 120 elsewhere, 60 for coverage and 90 for no-suggests.
- **Older pull request runs:** a new push to a pull request stops the older run of each check, to save minutes. To let
  them finish, set `cancel-in-progress: false` in the file's `concurrency:` block.
- **Turn a check off:** delete its file.
- **Keep a check but run it only by hand:** keep only `workflow_dispatch:` under `on:`.
- **A secret-scan false alarm:** the scan uses launchR's rules, not a `.gitleaks.toml` in the package. Silence a false alarm
  with a `gitleaks:allow` comment on that line; a real secret must be removed and its key rotated. To clear a false alarm already in history, add its fingerprint
  line (in the scan's log, as `file:rule:line` or `commit:file:rule:line`) to `.gitleaksignore` in a pull request; it applies once
  merged. Keep `^\.gitleaksignore$` in `.Rbuildignore`, or R CMD check notes it as a hidden file.
- **Keep the `permissions:` block as it is:** a check that reports on pull requests needs what it lists, or it stops before it starts.

Scheduled runs use the default branch only, and GitHub pauses them on public repositories after 60 days with no activity.
{{#has_time_limit}}

## The time limit

`r-cmd-check` fails when the tests take longer than `test-time-limit` seconds on Linux with R release (180 by default;
0 turns it off). CRAN asks for quick checks. Move slow tests to a `-extended.R` file, or make them faster.
{{/has_time_limit}}
{{#has_checks}}

## Run the checks on your computer

The quality gate runs most of these checks locally: style, docs in sync, spelling, tests, coverage and R CMD check as
CRAN runs it. It needs these packages once:

```r
install.packages(c(
  "checkmate", "cli", "devtools", "jsonlite", "spelling", "roxygen2", "lintr",
  "callr", "covr", "withr", "testthat", "pkgbuild", "processx", "rcmdcheck", "pkgdown"
))
```

The style step also needs [Air](https://posit-dev.github.io/air/), and [Biome](https://biomejs.dev) when the package
has JS or CSS. A missing one is named in the first FAIL line; without pkgdown, the website step is skipped. Then, from the
package's folder, in R:

```r
gate <- tempfile(fileext = ".R")
download.file("https://raw.githubusercontent.com/insightsurge/launchR/v{{kit_version}}/quality-gate/quality-gate.R", gate)
system2(file.path(R.home("bin"), "Rscript"), c(gate, "full"))
```

Use `fast` instead of `full` for a quicker run. It prints one PASS or FAIL line per step. It runs the extended tests
when `EXTENDED_TESTS` is `true`, which the package's `.Renviron` sets (`tests/README.md`). On Windows, `full` skips the
step that checks the package without its optional packages, because symlinks may need extra privileges there; the
`no-suggests` check on GitHub runs it on Linux.

## Updates

Dependabot opens a pull request when launchR has a new minor or major version (`0.6.0`, `1.0.0`), and changes only
the `@v...` part of these files. Patch versions (`0.6.1`) arrive with the next minor version; to take one sooner,
change the `@v...` part yourself. Updates to other actions you add come in their own pull requests. Dependabot
waits 3 days after a release by default; a `cooldown` block in `.github/dependabot.yml` changes that.

- To decline one version, close the pull request.
- To stop for good, comment `@dependabot ignore this dependency` on it, or delete `.github/dependabot.yml`.

Your CI keeps working on the old version either way.

## Leaving launchR

To keep your own copy of the checks, for example if your organisation blocks outside workflows, run launchR's `eject`
command. The checks then live in this repository and nothing depends on launchR. "Run the checks on your computer"
above then uses the copy of the gate in `.launchr/`. From the package's folder, in R, this downloads launchR
{{kit_version}} and runs it:

```r
archive <- tempfile(fileext = ".tar.gz")
download.file("https://github.com/insightsurge/launchR/archive/refs/tags/v{{kit_version}}.tar.gz", archive, mode = "wb")
folder <- tempfile()
untar(archive, exdir = folder)
launchr <- list.dirs(folder, recursive = FALSE)[1]
system2(file.path(R.home("bin"), "Rscript"), c(shQuote(file.path(launchr, "cli", "launchr.R")), "eject"))
```

Run it again with a newer launchR release to refresh the copies. In a clone of launchR, `Rscript cli/launchr.R eject`
does the same.
{{/has_checks}}
