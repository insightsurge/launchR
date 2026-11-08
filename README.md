# launchR <img src="site/public/logo-animated.svg" align="right" width="120" alt="launchR hex logo" />

**Start an R package with its checks already running.** launchR makes a new R package, or adds automatic checks to
one you have, from a short form at <https://launch-r.web.app> or from one R command. Each check in your package is a
short file that calls a check kept here, so fixes reach you as a one-line update.

- **Ready on day one:** DESCRIPTION, an example function with tests and help, READMEs that explain your setup, issue
  forms, labels and stage checklists on GitHub.
- **Seven automatic checks on GitHub (CI)**, from R CMD check to secret scanning, with one report comment on each pull
  request.
- **The same checks on your computer:** one quality-gate script prints a PASS or FAIL line per step.
- **No lock-in:** the files you get carry no conditions, and `eject` copies the checks into your repository.

## Get started

1. Open <https://launch-r.web.app>, click **Start your package** and answer a few questions. Nothing you type leaves
   your browser.
2. Download the zip named after your package, unzip it and open it in RStudio or Positron.
3. Follow the next steps on the site to put it on GitHub, from the R console or with GitHub Desktop. The checks start on
   your first push.

Already have a package? Choose **Already have a package?** on the form to add the checks, and if you want a website or
the GitHub setup. To make a new package from R instead: in a clone of this repository, `Rscript cli/launchr.R new mypkg`
asks the same questions ([The command line](#the-command-line)).

<img src=".github/readme/01-your-package.png" alt="The first screen of the form: package name, what it does, author, GitHub name, a choice of four plans, and a summary card of what the package gets" width="720" />

<details>
<summary>The rest of the form, screen by screen</summary>

**Customise a plan, step 2: CI checks.** Which checks run, on which systems and R versions, and when.

<img src=".github/readme/02-ci-checks.png" alt="The CI checks step: check chips, the R versions by systems matrix, and the summary card" width="720" />

**Step 3: Issues and checklists.** Issue forms, labels and the stage checklists.

<img src=".github/readme/03-issues-and-checklists.png" alt="The issues and checklists step: issue form cards, labels and checklist chips" width="720" />

**Step 4: README and website.** Badges and a pkgdown site.

<img src=".github/readme/04-readme-and-website.png" alt="The README and website step: badge choices and the website switch" width="720" />

**Step 5: Extras.** Licence, JS or CSS in the package, and instructions for AI assistants.

<img src=".github/readme/05-extras.png" alt="The extras step: licence, front-end files and AI instructions" width="720" />

**The preview window.** Each checklist and issue form as GitHub will show it.

<img src=".github/readme/06-preview-window.png" alt="The preview window showing the Set up checklist as a GitHub issue" width="720" />

**After the download.** The next steps, from the R console or with GitHub Desktop.

<img src=".github/readme/07-next-steps.png" alt="The next steps page: numbered steps with commands to copy" width="720" />

**An existing package.** The parts you choose (the checks by default, a website, issue forms, labels and checklists); `R/` and `tests/` are left alone.

<img src=".github/readme/08-existing-package.png" alt="The existing package view: package name, GitHub name and which parts to add" width="720" />

</details>

## Your plan decides the defaults

| Plan | Repository | CRAN | What changes |
| --- | --- | --- | --- |
| Public, going to CRAN | public | yes | R CMD check runs as CRAN does, on Linux, Windows and Mac |
| Public, not for CRAN | public | no | R CMD check without CRAN's extra rules |
| Private for now | private | later | Linux only, to save GitHub minutes; CRAN rules from the start |
| Private for good | private | no | Linux only, and no weekly check on other systems |

## What your package gets

| Part | What it adds | Default |
| --- | --- | --- |
| Package skeleton | DESCRIPTION, an example function, a test of each kind, help pages | on |
| CI | The checks below, one short file each in `.github/workflows/` | on |
| GitHub setup | Issue forms, a PR template, labels and stage checklists | on |
| AI setup | `AGENTS.md` with rules files in `.agents/rules/` (the same in every package), and `CLAUDE.md` importing it | off |
| Website | A pkgdown site published to GitHub Pages | off |
| Front-end | JavaScript and CSS, with browser tests | off |

### The checks

| Check | What it does | Runs on |
| --- | --- | --- |
| `r-cmd-check` | R CMD check, as CRAN runs it for a CRAN package | pull requests, pushes, weekly |
| `lint` | Style, docs in sync with the code, spelling | pull requests, pushes |
| `no-suggests` | The package works without its optional packages | pull requests, pushes |
| `secret-scan` | Catches passwords and tokens committed by mistake | pull requests, pushes |
| `coverage` | How much of the code the tests run, with a lower limit | pull requests, pushes |
| `full-tests` | Every test, including the browser, snapshot and extended tests CRAN skips | pull requests, pushes, weekly |
| `r-cmd-check-extended` | R CMD check on more systems, with the extended tests | weekly |

`secret-scan` uses launchR's own rules, not a `.gitleaks.toml` in the package: a false alarm is silenced with a `gitleaks:allow` comment on that line, and a real secret must be removed and its key rotated. To clear a false alarm already in history, add its fingerprint line (in the scan's log, as `file:rule:line` or `commit:file:rule:line`) to `.gitleaksignore` in a pull request; it applies once merged. Keep `^\.gitleaksignore$` in `.Rbuildignore`, or R CMD check notes it as a hidden file.

Every check except `secret-scan` can also be started by hand from the Actions tab. You choose the systems, R versions,
oldest R and weekly time on the site; the package's `.github/workflows/README.md` lists what you chose and how to
change it, and `tests/README.md` explains the test file kinds.

## Add CI to an existing package

To add launchR's checks to a package you already have, choose **Set up an existing package** on the site
(<https://launch-r.web.app/#yours>). The zip holds the CI files and the settings files the chosen checks read, and, if you choose
them, a website and the GitHub setup; the site says what to do with each. `R/` and `tests/` are left alone, and a package
not going to CRAN adds one line to DESCRIPTION by hand.

## Set up GitHub

With the GitHub setup part, your repository gets a **Set up this repository** workflow. Its first run, from your first
push, only lists what it would make, in the run summary and the job log. Run it from the Actions tab to create the
labels, a root issue and the stage checklists you chose (`lists/stages.tsv`; DESCRIPTION's `Config/launchR/checklists`
lists them, and a plan starts with its own). It ticks the boxes it can check, such as "CI is green on the default
branch", and links each repository setting it can't change. Each run ends with a report of what changed, or what a
dry run would change: the labels made or removed, the root issue and each checklist with its link, the boxes ticked
and unticked, and what is still to do. On GitHub it is the run's summary page; in R and the command line it is printed
with full addresses. The first real run also says why to keep the workflow: later runs tick boxes and open the
next checklist (or use the R line below and delete the workflow). Run it again at any time: it edits only the lines it wrote. Labels that aren't launchR's, such as
GitHub's own (duplicate, question, ...) and any you made, stay; to
remove them, tick **Also remove labels that aren't launchR's** when you click Run workflow. Dependabot's labels are kept.

The stage checklists, and when each opens:

| Checklist | Opens | What it covers |
| --- | --- | --- |
| Set up | On the first run, for every plan | Your own code in place of the example, DESCRIPTION, the repository files, CI and the settings every package needs |
| Before public | While the repository is private | Making sure nothing private goes public, and the switch to public |
| After public | Once the repository is public | The settings that come with being public, Windows and Mac in CI, the website, and making the package easy to find |
| Before CRAN | For a package going to CRAN, until it is on CRAN | The checks and the points CRAN's reviewers read, then the submission |
| After acceptance | Once the package is on CRAN | Telling people, the GitHub release and the development version |
| Next release | From the first run for a package not for CRAN; once the package is on CRAN for one that is | A fresh list for each release: checks, docs, version, NEWS and the GitHub release. A new list opens after each release is shipped. |
| QC | Not a list of its own: sections of Next release, for teams with a quality process (any plan; on for plan d) | Scope and risk, tests, review, and the evidence to keep for each release |

A checklist can have boxes under a box (one level). A box with others under it ticks when every box under it is ticked.
A box marked optional does not keep a checklist open: it closes when every other box is ticked. Boxes that can be checked (a
file, a setting, CI results, the website, CRAN status) tick themselves, and un-tick when they stop being true; the rest are yours to tick.

A package made before Set up was a checklist has no `Config/launchR/checklists` line in DESCRIPTION, so its next run
opens a Set up list (and a Next release list too, for a package not for CRAN). A package whose line is only
`QC before release`, the old QC checklist, now gets Next release with the QC sections (a package going to CRAN: once it is on CRAN); add `Set up` to the line to get
that list as well. An issue called "Checklist: QC before release" that is already open is no longer updated.

The same from R, with the [GitHub CLI](https://cli.github.com) signed in, from your package's folder; this can also
tick the settings boxes:

```r
source("https://raw.githubusercontent.com/insightsurge/launchR/vX.Y.Z/cli/github-setup.R")
```

## The command line

Needs R 4.1 or newer and a clone of this repository; `gh` only for GitHub setup.

```bash
Rscript cli/launchr.R new mypkg                       # asks its questions
Rscript cli/launchr.R new mypkg --yes --owner my-org  # takes the defaults
Rscript cli/launchr.R gate full                       # run the quality gate in the current package
Rscript cli/launchr.R github-setup --dry-run          # show the GitHub changes, change nothing
Rscript cli/launchr.R github-setup --remove-other-labels  # also remove labels that aren't launchR's (not Dependabot's)
Rscript cli/launchr.R eject                           # copy launchR's checks into the current package
```

| `new` flag | Meaning |
| --- | --- |
| `--yes` | Use the flags and defaults instead of asking |
| `--owner NAME` | Your GitHub username or organisation (needed with `--yes`) |
| `--plan a` to `d` | The plan, as on the site: a public CRAN (default), b public not for CRAN, c private for now, d private for good |
| `--title`, `--author`, `--email`, `--year` | DESCRIPTION fields; the same rules as the site's form |
| `--description TEXT` | DESCRIPTION's Description, a sentence or two (default: the title) |
| `--min-r 4.3` | The oldest R the package supports, as x.y (default 4.1); DESCRIPTION gets 4.3.0 |
| `--no-ci-report` | Leave out the CI report comment on pull requests (`ci-report: false` in each check's file) |
| `--licence mit` / `proprietary` | The licence (default: proprietary for plan d, MIT otherwise) |
| `--badges check,lifecycle` | README badges, from `lists/badges.tsv` (`none` for no badges) |
| `--navbar reference,news,search` | The website's navbar items, from `lists/navbar.tsv` |
| `--forms bug,docs`, `--labels bug,idea` | Which issue forms (`lists/forms.tsv`) and labels (`lists/labels.tsv`); a form's label, and `epic` (the set-up step's root issue uses it), are always kept |
| `--checklists set-up,before-public,next-release,qc` | Which stage checklists the package gets, from `lists/stages.tsv` (`none` for no checklist); the plan's own list is the default, and DESCRIPTION records the choice as `Config/launchR/checklists`. `qc` needs `next-release` |
| `--qc`, `--no-qc` | Add or remove the QC sections of Next release (on for plan d, offered to every plan) |
| `--preset starter` / `everything` | Which parts and checks are on |
| `--public`, `--internal` | Older spelling of the plan: public, and not going to CRAN |
| `--path DIR` | Where to write the package (default: a folder named after it) |
| `--no-git` | Don't make the first git commit |

When it has written the package, `new` prints a few next steps: open the folder, install the dependencies and run the tests, and put the package on GitHub.

## The quality gate

`quality-gate/quality-gate.R` runs the checks on your computer, from the package's folder:

| Mode | Steps |
| --- | --- |
| `fast` (default) | Tools, style, docs in sync, `\value` sections, spelling, pkgdown, R CMD check without tests |
| `tests` | The tests once under covr, coverage, and a check that new lines are tested |
| `full` | Everything above, plus R CMD check with tests, the built tarball, and the no-Suggests check |
| `lint` | The quick static steps only |
| `nosuggests` | R CMD check with only the hard dependencies installed |

It prints one PASS, FAIL or SKIP line per step and exits 0 (all passed), 1 (a step failed), 2 (it could not judge the
package) or 3 (only flaky tests failed). `Rscript quality-gate/quality-gate.R --help` lists the options. A generated
package's `.github/workflows/README.md` shows how to run it without cloning launchR.

## How your checks reach launchR

Your package holds only short caller files. Each one names a check here and a launchR release:

```yaml
# .github/workflows/r-cmd-check.yaml in your package (shortened)
on:
  pull_request:
    branches: [main, master]
jobs:
  check:
    uses: insightsurge/launchR/.github/workflows/r-cmd-check.yaml@vX.Y.Z
    with:
      platforms: ubuntu/release, windows/release, macos/release
```

```mermaid
sequenceDiagram
  autonumber
  actor Dev as You
  participant GH as GitHub Actions
  participant Caller as Your caller file
  participant Shared as launchR's check (at vX.Y.Z)
  participant PR as Your pull request
  Dev->>GH: push, open a pull request, or Run workflow (weekly runs start on their own)
  GH->>Caller: start the check (a newer push to the same pull request stops the older run)
  Caller->>Shared: uses ...@vX.Y.Z, with your settings
  Shared->>Shared: check out your package, and launchR's scripts at the same version into .launchr/
  Shared->>Shared: on a pull request that changes only documentation, skip the R work
  Shared->>Shared: install R and packages, run the check (one job per system and R version)
  Shared-->>GH: pass or fail, and a job summary
  Shared->>PR: on a pull request, update one report comment that covers every check (unless ci-report is false)
```

- **Permissions:** each check reads your code; only the report job can write a pull request comment. Pull requests
  from forks and from Dependabot get the job summary instead.
- **Updates:** `.github/dependabot.yml` opens a pull request when launchR has a new minor or major release. It changes
  only the `@v...` part of the caller files. Close it to stay where you are.
- **Leaving:** `eject` copies the checks, their scripts and the quality gate into your repository (`.launchr/` and
  `.github/workflows/launchr-*.yaml`), so nothing calls launchR any more.

## How a package is made

The website and the command line read the same template and lists, and build the same files.

```mermaid
flowchart LR
  you([You]) -->|form| site["Website<br/>launch-r.web.app"]
  you -->|"Rscript cli/launchr.R new"| cli["Command line<br/>(R)"]
  subgraph repo["This repository"]
    lists["lists/*.tsv<br/>plans, parts, checks, files, settings"]
    template["template/<br/>files with {{placeholders}}"]
  end
  lists --> site
  template --> site
  lists --> cli
  template --> cli
  site -->|zip, built in your browser| pkg[["Your package"]]
  cli -->|folder and first git commit| pkg
```

- The lists hold every choice and default: the four plans, the parts, the checks with their schedules and systems,
  which template file belongs to which part, and the rules for names.
- The site's engine (`site/src/form/engine.js`) and the command line (`cli/R/`) fill the placeholders the same way.
  `tests/compare-routes.mjs` builds every plan through both and compares every file.
- Your answers stay in your browser: the site builds the zip there.

## In this repository

| Folder | What it holds |
| --- | --- |
| `site/` | The website (Astro): landing page and form. The form's logic is in `src/form/` |
| `cli/` | The command line: `launchr.R`, with the work in `R/` |
| `template/` | The package files, with `{{placeholders}}` |
| `lists/` | Tab-separated lists read by both the site and the command line |
| `.github/workflows/` | The reusable checks that packages call, and this repository's own site deploy, site tests and sandbox test. Overview, with what starts each and where its result shows: its `README.md` |
| `.github/actions/`, `.github/scripts/` | Shared steps the checks use: the PR report, baselines, change detection |
| `.github/readme/` | The README's screenshots of the form; retake them when the form changes |
| `quality-gate/` | The quality gate |
| `tests/` | Tests for the command line, the two routes, the zip, the PR report builder, caller compatibility, generated packages against the gate, and the sandbox test's steps |
| `CONTRIBUTING.md` | For maintainers: add a check or a template file, make a release, run the tests, how the shared workflows are secured |

## Develop and test

```bash
npm --prefix site install
npm --prefix site run dev          # the site, with the template bundled in

Rscript tests/cli-tests.R          # the command line, against a stand-in for gh (about 90 s; needs jq and git; --verbose lists every check)
node tests/compare-routes.mjs      # the site and the command line build the same files, for every plan
node tests/check-zip.mjs           # the zip is sound
bash tests/build-comment-tests.sh  # the pull request report builder, against a fake gh (needs jq, perl, unzip, zip)
tests/gate-matrix.sh               # generated packages pass the quality gate

npx --prefix site playwright install chromium   # once: the browser for the site's tests
npm --prefix site run build
(cd site && npx playwright test)   # the form, each plan's download and its zip, in a real browser
```

Every pull request runs the browser tests, the route comparison, the zip check, the command line's tests, the report
builder's tests, and three checks of the workflows in `.github/` (actionlint for mistakes, the caller compatibility
check, zizmor for security problems) in `.github/workflows/site-tests.yaml`. `CONTRIBUTING.md` says what each test covers and how to run the
linters.

**Before a release, the sandbox test.** Local tests can't show what only GitHub's runners do, such as a step that
hangs on Windows. `.github/workflows/sandbox-e2e.yaml`, started by hand (Actions, sandbox-e2e, Run workflow, on `main`
or the release branch), makes a package on the site with every check, R devel on Linux and browser tests on Linux, Mac
and Windows, points its checks at the launchR commit under test, and runs them in the public repository
`insightsurge/launchr-sandbox`: a push to its default branch, and a pull request with a planted fake secret that
secret-scan must catch. It fails when any other check fails, with a link to each failed job, or when the pull request
gets other than one report comment. A passing run takes about 35 minutes (it waits for the default branch's coverage and full-tests runs before it opens its pull request); given the release pull request's number,
it posts its report there as one comment. It needs the `SANDBOX_TOKEN` secret described in
`CONTRIBUTING.md`.

The site is published to Firebase Hosting by `.github/workflows/deploy-site.yaml` when a change to `site/`,
`template/` or `lists/` reaches `main`, or when the workflow is started by hand. Google Analytics loads only on that
address, and only after a visitor accepts it in the cookie banner (`site/src/consent.js`).

## Licence

launchR is under the MIT licence (`LICENSE`). The files in `template/`, which are what end up in your package, are
under the Zero-Clause BSD licence (`template-LICENSE`), which asks nothing of you: no notice to keep, no credit to give.
New packages start with the MIT licence in your name, or a proprietary one for a private package that won't go to CRAN;
you can change it.
