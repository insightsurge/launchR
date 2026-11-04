# launchR's tests

What each file checks. How to run them all, and the workflow linters, is in [CONTRIBUTING.md](../CONTRIBUTING.md).

| File | What it checks |
| --- | --- |
| `compare-routes.mjs` | The site's engine and the command line build the same files for every plan |
| `cli-tests.R` | The command line against a stand-in for `gh` (`fake-gh/`); the lists agree with each other; the version is the same in `lists/settings.tsv`, `cli/DESCRIPTION` and `cli/github-setup.R` |
| `build-comment-tests.sh` | `.github/actions/pr-report-comment/build-comment.sh` with a fake `gh`: a run's state (running, failed, cancelled), the matrix race, section order, cutting long parts without breaking a character or leaving `<details>` open |
| `check-zip.mjs` | The zip the site builds is sound (run after building the site) |
| `gate-matrix.sh` | Generated packages for the main sets of choices pass the quality gate (slow; run by hand) |

The browser tests are in `site/tests/`. The workflow linters have no test file: `actionlint` and `zizmor` run on
`.github/workflows/` and `.github/actions/` in the `workflow-lint` job of `.github/workflows/site-tests.yaml`.
