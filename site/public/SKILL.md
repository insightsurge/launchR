---
name: launchr
description: Use when working on an R package made with launchR, its CI, its quality gate, its checklists or a launchR upgrade.
---

# Working on a launchR package

An AI coding agent working on an R package made with launchR should follow this skill. The maintainer owns the package; launchR provides its shared CI, quality gate, repository checklists and templates.

## How to tell a package uses launchR

Check for these indicators in the repository:

- `DESCRIPTION` has a `Config/launchR/version` field:
  ```dcf
  Config/launchR/version: x.y.z
  ```
- Workflow caller files in `.github/workflows/` call shared workflows from launchR:
  ```yaml
  uses: insightsurge/launchR/.github/workflows/<check>.yaml@vX.Y.Z
  ```
- If the package has been ejected, the checks live in `.launchr/` and `.github/workflows/launchr-*.yaml`.

## Where documentation lives

The package's own files hold the project-specific configuration. Upstream launchR documentation holds general mechanics and CLI commands:

- `.github/workflows/README.md`: How CI checks run, local quality-gate runs, modifying checks, updates and eject.
- `tests/README.md`: Test file kinds, suffix conventions, skip conditions and running tests locally.
- `.github/CONTRIBUTING.md`: Development workflow, commit formatting, and checks to run before a pull request.
- `AGENTS.md` and `.agents/rules/`: Instructions for coding agents when the AI setup part was enabled.
- `DESCRIPTION`: Package metadata, `Config/launchR/version`, and quality-gate settings under `Config/quality-gate/*`.

## To do this | Read this

Consult the package's own files first. Consult launchR's repository on GitHub only for what is not kept inside the package.

| To do this | Read this |
| --- | --- |
| Start a package | Visit <https://launch-r.web.app/#start> for the browser generator, or launchR's README on GitHub: [How a package is made](https://github.com/insightsurge/launchR#how-a-package-is-made) and [The command line](https://github.com/insightsurge/launchR#the-command-line) (`launchr.R new` flags). |
| Add launchR's checks to an existing package | Visit <https://launch-r.web.app/#yours> to add CI, a website or the GitHub setup, or launchR's README on GitHub: [Add CI to an existing package](https://github.com/insightsurge/launchR#add-ci-to-an-existing-package). |
| Run the checks locally | `.github/workflows/README.md` ("Run the checks on your computer") for the quality gate snippet and prerequisites, `.agents/rules/checks.md`, and `.github/CONTRIBUTING.md` ("Before you open a pull request"). For gate modes (`fast`, `tests`, `full`) and exit codes, see launchR's README: [The quality gate](https://github.com/insightsurge/launchR#the-quality-gate). |
| Read the pull request's CI report and fix a failure | `.github/CONTRIBUTING.md` ("Workflow" and "Before you open a pull request") and `.agents/rules/checks.md` for diagnosing failures and fixing root causes. For PR report comments and token permissions, see launchR's README: [How your checks reach launchR](https://github.com/insightsurge/launchR#how-your-checks-reach-launchr). |
| Know which tests run where (test file kinds) | `tests/README.md` ("Test file kinds") in a new package, or `.github/workflows/README.md` ("Test file kinds") in a package set up by the existing-package route, for file naming conventions (`-browser.R`, `-snap.R`, `-extended.R`), skip rules, and `.agents/rules/tests.md`. |
| Set up the GitHub repository (labels, root issue, checklists) | Run **Set up this repository** (`github-setup.yaml`) from the package's Actions tab; the R line and what each run reports are in launchR's README, [Set up GitHub](https://github.com/insightsurge/launchR#set-up-github). For the checklist stages (Set up, Before public, After public, Before CRAN, After acceptance, and Next release with the QC sections), when each opens, how boxes tick and nest, the root issue structure and labels, see launchR's README: [Set up GitHub](https://github.com/insightsurge/launchR#set-up-github). |
| Move to a newer launchR version | `.github/workflows/README.md` ("Updates") for how a newer launchR version reaches the caller files, and the [launchR releases page](https://github.com/insightsurge/launchR/releases) for each version's notes and what to change. A package with no `Config/launchR/checklists` line in DESCRIPTION gets a Set up checklist on its next "Set up this repository" run. |
| Change when a check runs, turn one off, or turn the CI report comment off | `.github/workflows/README.md` ("Changing a check") for schedules, platforms, timeouts, deleting check files, and turning off comments with `ci-report: false`. |
| Copy the checks into the package so nothing depends on launchR (eject) | `.github/workflows/README.md` ("Leaving launchR") for the R eject snippet, or launchR's README: [The command line](https://github.com/insightsurge/launchR#the-command-line) (`launchr.R eject`). |

## Rules for the agent

- Fix the cause of a failing check, never loosen a check or skip it.
- Don't edit the `uses:` line, the `permissions:` block or the `ci-report` line of a caller file unless the person asks.
- Regenerate `man/` and `NAMESPACE` with `devtools::document()`, never by hand.
- A private or company package: check the organisation's policy before downloading and running launchR's scripts locally (CI runs the same checks either way).
- Report what you ran and what it printed.

## Reporting problems

Report a bug or a false alarm in launchR itself (its shared workflows, quality gate or command line) at
<https://github.com/insightsurge/launchR/issues>.
