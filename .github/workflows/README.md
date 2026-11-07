# launchR's workflows

This folder holds two kinds of workflow:

- **The checks that packages call.** A package made by launchR has a short caller file for each check it chose
  (`template/.github/workflows/`), which runs the file here at a release tag (`@vX.Y.Z`) with the package's own token.
  When each check runs in a package comes from `events` in `lists/checks.tsv`. What a package's maintainers read about
  them is `template/.github/workflows/README.md`.
- **launchR's own workflows**, which run only in this repository.

Each workflow's opening comment says what it does in detail. This file is the overview: change it when you add,
rename or remove a workflow, or change when one runs or where its result shows.

## The checks that packages call

All start with `on: workflow_call`, and need no secret beyond the caller's token unless the table says so.

| Workflow | What it does | Part of the pull request report |
| --- | --- | --- |
| `r-cmd-check.yaml` | R CMD check as CRAN runs it: any error, warning or note fails | Yes |
| `r-cmd-check-extended.yaml` | R CMD check with the extended tests on macOS and Windows; weekly and by hand | No |
| `full-tests.yaml` | Every test file, nothing skipped: browser, snapshot and extended tests | Yes |
| `coverage.yaml` | Test coverage against the limit in `DESCRIPTION`; sends the figure to Codecov when the package has `CODECOV_TOKEN` | Yes |
| `no-suggests.yaml` | R CMD check without the Suggests packages (the gate's `nosuggests` mode) | Yes |
| `lint.yaml` | The gate's lint mode: Air, Biome, lintr, docs in sync, `\value`, spelling | Yes |
| `secret-scan.yaml` | gitleaks over the pushed commits | Yes |
| `pkgdown.yaml` | Builds the package's site from `main` and publishes it to GitHub Pages | No |
| `github-setup.yaml` | Labels, the root issue and the stage checklists, started by hand ("Run workflow"); writes a linked report to the run summary; also runs as a dry run, changing nothing, when its caller file is pushed | No |

The pull request report is one comment that each check adds its part to (`.github/pr-report.json` lists the parts). It
covers only the checks a package has caller files for. Each check that reports takes a `ci-report` input (default
`true`); a package that leaves the comment out passes `false` from every caller file.

## launchR's own workflows

| Workflow | What it does | Started by | Result shows in | Needs |
| --- | --- | --- | --- | --- |
| `site-tests.yaml` | The site in a browser, the zip, the site and command line making the same packages, the command line's and report builder's tests, the gate matrix on template and gate changes, and actionlint, caller compatibility and zizmor on the workflows | Every pull request to `main`, a push to `main`, or by hand | The pull request's Checks tab | Nothing |
| `deploy-site.yaml` | Builds the site and publishes it to Firebase Hosting | A push to `main` that changes `site/`, `template/`, `lists/` or the Firebase files, or by hand | The Actions tab | Repository variables for Google sign-in (no stored key); skipped until they are set |
| `sandbox-e2e.yaml` | A package made on the site runs every check in the public sandbox repository, against this commit, before a release | By hand only (Actions, sandbox-e2e, Run workflow) | The Actions tab; with `release_pr`, also one comment on that pull request | The `SANDBOX_TOKEN` secret |

**Runs started by hand show only under Actions,** never in a pull request's Checks tab, even when started on the pull
request's branch: GitHub lists there only the runs that the pull request itself started. That is why `sandbox-e2e.yaml`
takes a `release_pr` number to post its result on the pull request.

## Shared steps

| Path | What it does |
| --- | --- |
| `.github/actions/pr-report-part/` | Saves one check's part of the pull request report, and adds it to the job summary |
| `.github/actions/pr-report-comment/` | Gathers the parts into the one report comment; the only step with `pull-requests: write` |
| `.github/actions/main-baseline/` | Fetches the figures a pull request is compared with (coverage, test times) from the latest run on `main` |
| `.github/scripts/r-changes.sh` | Tells the R jobs to skip their steps on a pull request that changes only documentation |
| `.github/scripts/check-times.sh` | The R CMD check times for the report |
| `.github/scripts/coverage-report.R` | The coverage part of the report |
| `.github/scripts/full-tests-report.R` | The full tests' part of the report |
| `.github/scripts/build-site.R` | Builds a package's pkgdown site, keeping the AI instruction files out of it |

## More

- Adding a check, the release steps and the sandbox test's setup: `CONTRIBUTING.md`.
- What the workflows are allowed to do, and why: "Security model of the reusable workflows" in `CONTRIBUTING.md`.
- Linter settings: `.github/actionlint.yaml` and `.github/zizmor.yml`.
