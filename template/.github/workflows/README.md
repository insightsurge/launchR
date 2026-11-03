# How CI works here

Each file in this folder is one check. The check itself lives in the launchR repository and this file only says when
and where it runs, so it stays short. Nothing needs installing: GitHub runs these by itself.

| File | What it does | When it runs |
| --- | --- | --- |
{{checks_table}}

These are the checks chosen when the package was set up. To add another later, come back to the site and choose only
that check. Which test files each check runs: `tests/README.md`.

{{codecov_note}}## Changing a check

- **Which branches or times:** edit the `on:` block at the top of the file. Times are UTC.
- **Which systems and R versions:** edit `platforms` under `with:`.
- **Turn a check off:** delete its file.
- **Keep a check but run it only by hand:** keep only `workflow_dispatch:` under `on:`.
- **Keep the `permissions:` block as it is:** a check that reports on pull requests needs what it lists, or it stops before it starts.

Scheduled runs use the default branch only, and GitHub pauses them on public repositories after 60 days with no activity.

{{time_limit_section}}## Run the checks on your computer

The quality gate runs most of these checks locally: style, docs in sync, spelling, tests, coverage and R CMD check as
CRAN runs it. It needs these packages once:

```r
install.packages(c(
  "checkmate", "cli", "devtools", "jsonlite", "spelling", "roxygen2", "lintr",
  "callr", "covr", "withr", "testthat", "pkgbuild", "processx", "rcmdcheck"
))
```

The style step also needs [Air](https://posit-dev.github.io/air/), and [Biome](https://biomejs.dev) when the package
has JS or CSS. A missing one is named in the first FAIL line. Then, from the package's folder, in R:

```r
gate <- tempfile(fileext = ".R")
download.file("https://raw.githubusercontent.com/insightsurge/launchR/v{{kit_version}}/quality-gate/quality-gate.R", gate)
system2(file.path(R.home("bin"), "Rscript"), c(gate, "full"))
```

Use `fast` instead of `full` for a quicker run. It prints one PASS or FAIL line per step.

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
above then uses the copy of the gate in `.launchr/`.
