# Maintaining launchR

For anyone changing launchR itself. How the pieces fit is in the [README](README.md); this page says what to touch
for the common jobs, how to release, what each test covers, and what the shared workflows are allowed to do.

The one idea behind everything: **`lists/` and `template/` are the single source.** The website
(`site/src/form/engine.js`) and the command line (`cli/R/`) both read them and must build the same package. A change
to a choice, a check or a file goes into the lists or the template first, and the two readers follow.

## Add a check

A check is a reusable workflow here, plus a short caller file in each package that names it. Take `no-suggests` as the
model and search for its name (and `no_suggests`, its key) to see every place. In order:

1. **The reusable workflow:** `.github/workflows/<check>.yaml`, with `on: workflow_call`, `permissions: contents: read`
   at the top (a job asks for more itself), and a `report` job if the check has a part in the pull request comment.
   Copy the marked block `# launchr-fetch-start` ... `# launchr-fetch-end` exactly: `eject` removes that block to make
   the copy that runs without launchR (`cli/R/eject.R`).
2. **`lists/checks.tsv`:** one row. `key` (underscores) and `check` (the workflow's name), `label` and `help` (the
   words on the site), whether it is on in `starter` and `everything`, `events` (`pr`, `push`, `schedule`, `manual`;
   `schedule` makes it a weekly check), `cron` (an odd minute, because GitHub delays scheduled runs at round hours),
   the systems for public and private packages, and `test_kinds` (which kinds of test file this check runs, for the
   package's `tests/README.md`).
3. **The caller template:** `template/.github/workflows/<check>.yaml`. Its trigger lines start with the placeholders
   `{{c_<key>_pr}}`, `{{c_<key>_push}}`, `{{c_<key>_manual}}` and `{{c_<key>_schedule}}`; copy a neighbour. It calls
   `insightsurge/launchR/.github/workflows/<check>.yaml@v{{kit_version}}`.
4. **`lists/files.tsv`:** a row for the caller file with part `ci` and the check's `check` name (the file is left out
   when the check is off).
5. **The pull request report:** if the check writes a part, add its workflow file to `workflows` in
   `.github/pr-report.json` (and a section there if it needs a new one). The part's name (`tests-3-no-suggests`) puts
   it in the section named by the text before the first `-` (`tests`, `security` or `style`). Add a line to `hints` there:
   what to do when the check fails, shown under its failed jobs. Give the workflow the `ci-report` input and the `report`
   job's `inputs.ci-report` condition, as the others have, add `ci-report: {{ci_report}}` to its caller template, and
   add its key to `REPORTING` in `site/src/form/app.js`.
6. **Words that list the checks:** `.github/workflows/README.md` (launchR's overview of its workflows), the package's
   `template/.github/workflows/README.md`, the root README's checks table
   and "seven automatic checks", the site's text (`site/src/components/Story.astro`, `site/public/llms-full.txt`),
   `quality-gate/quality-gate.R` if a gate mode mirrors the check, and `lists/checklists.tsv` if a stage checklist
   mentions CI (a new checklist stage also goes in `lists/stages.tsv` and in the plans that start with it). Search for a neighbouring check's name to find them.
7. **Tests:** run the route comparison and the command line's tests (below). `tests/cli-tests.R` checks the lists
   against each other, and the browser tests drive the form.

Nothing makes a missing step fail by itself except the tests above, so run them.

## Add a template file

1. Put the file in `template/`. Use `{{placeholder}}` for anything that changes per package; the values come from
   `cli/R/build.R` (command line) and `site/src/form/engine.js` (site). A new placeholder must be added to both.
   Text that appears only for some packages goes in the template too, between lines `{{#has_x}}` and `{{/has_x}}`
   (`{{^has_x}}` for "when not"); the code only sets `has_x` to true or false. Per-check lists such as the test kinds
   are columns in `lists/checks.tsv`.
2. Add one row to `lists/files.tsv`: `path`, `part` (the part that includes it, such as `skeleton`, `github` or `ci`), `check`
   (the check that needs it, or `any` for "at least one check is on"), `release` (`cran` or `any`), and `existing`
   (for the route of a package that already exists: the check that brings the file along).
3. If it belongs to a new part, add the part to `lists/parts.tsv` and to the plans in `lists/plans.tsv`.
4. Run `node tests/compare-routes.mjs`: it builds every plan both ways and compares every file, so a placeholder only
   one reader knows shows up there. If the file should reach existing packages, check the `existing` route too.

## Release

launchR's version is the tag its users name in their caller files (`@vX.Y.Z`), so a release is a tag.

1. **Bump the version in the three places that hold it:** `lists/settings.tsv` (`kit_version`), `cli/DESCRIPTION`
   (`Version`) and `cli/github-setup.R` (`version <-`). `tests/cli-tests.R` fails when they differ. Everything else
   (the caller files, the package's `DESCRIPTION`, the next-steps text on the site) takes it from `kit_version`.
2. Open a pull request and let the checks pass (the `workflow-lint` job's caller compatibility check verifies
   the previous release's callers against this commit's workflows, and this commit's callers against its own workflows
   because the new tag does not exist yet). **Run the sandbox test on its branch** (Actions, sandbox-e2e, Run
   workflow, pick the branch, and give the pull request's number; below): it runs a site-made package's checks on
   GitHub's Linux, Mac and Windows runners against this commit, takes about 35 minutes when it passes, and posts its
   report on the pull request. Merge when it passes.
3. **Tag the merge commit right after the merge**, `vX.Y.Z` on `main`, and push the tag. Until the tag exists, a new
   package made from `main` points at a version that does not exist yet and its checks fail.
4. **The site:** `.github/workflows/deploy-site.yaml` publishes it when a change to `site/`, `template/` or `lists/`
   reaches `main`, so the live site already offers the new version before you tag. Tag promptly, or merge the
   version bump last.
5. **What users see:** each package's `.github/dependabot.yml` has a `launchr` group. Dependabot opens one pull request
   per minor or major release that changes only the `@v...` part of the caller files. Patch releases are ignored on
   purpose ("launchR patch releases arrive with the next minor release"), so a fix that users must have goes into a
   minor release. A user who has run `eject` has no callers and sees nothing.

## Tests

| Test | What it covers | Run it |
| --- | --- | --- |
| `tests/compare-routes.mjs` | The site and the command line build the same files for every plan | `node tests/compare-routes.mjs` |
| `tests/cli-tests.R` | The command line against a stand-in for `gh` (about 90 s; needs `jq` and `git`), the lists' consistency, the version in three places | `Rscript tests/cli-tests.R` |
| `tests/build-comment-tests.sh` | The pull request report builder (`.github/actions/pr-report-comment/build-comment.sh`) with a fake `gh`: states, ordering, cutting long parts, matrix races. Needs `jq`, `perl`, `unzip`, `zip`, `iconv` | `bash tests/build-comment-tests.sh` |
| `tests/caller-compat.sh` | Caller compatibility with actionlint: previous release callers against this commit's workflows, and this commit's callers against the tag in `lists/settings.tsv` (or this commit if untagged) | `bash tests/caller-compat.sh` |
| `tests/gate-matrix.sh` | Generated packages for the main sets of choices pass the quality gate (slow, needs R packages; runs in CI on template, list, CLI and gate changes) | `bash tests/gate-matrix.sh` |
| `tests/check-zip.mjs` | The site's zip is sound (after `npm --prefix site run build`) | `node tests/check-zip.mjs` |
| `site/tests/form.spec.js` | The form, each plan's download and its zip, in a real browser (Playwright) | `npm --prefix site run build`, then `cd site && npx playwright test` |
| actionlint | Mistakes in `.github/workflows/` (types, expressions, the shell in `run:` steps). Settings: `.github/actionlint.yaml` | `actionlint` from the repository root |
| `tests/sandbox-e2e.sh` | A package made on the site (`site/tests/sandbox-package.spec.js`: public CRAN plan, every check, R devel, browser tests on every system) runs its own checks in the public sandbox repository, pointed at the commit under test: a push to the default branch, and a pull request whose planted secret secret-scan must catch. Fails on any other failed check (linking each failed job) and unless the pull request has one report comment | By hand before a release: `.github/workflows/sandbox-e2e.yaml` (Run workflow) |
| zizmor | Security problems in `.github/workflows/` and `.github/actions/` (unpinned actions, token left in `.git`, injection, too-wide permissions). Settings: `.github/zizmor.yml` | `zizmor .github/workflows .github/actions` (set `GH_TOKEN` for the online checks) |

The pull request workflow `.github/workflows/site-tests.yaml` runs the browser tests, the zip check, the route
comparison, the command line's tests, the report builder's tests, the gate matrix (`tests/gate-matrix.sh`, when
templates, lists, the CLI, the quality gate or `tests/gate-matrix.sh` change), and (job `workflow-lint`) actionlint,
caller compatibility (`tests/caller-compat.sh`), and zizmor.
The sandbox test is not part of that workflow: run it by hand before a release. Both linters are pinned to an exact version there, with a checksum;
to raise one, change the version and checksum together, run it locally, and fix or (with a one-line reason in its
config file) allow what it finds.

## The sandbox test

`.github/workflows/sandbox-e2e.yaml` finds what only GitHub's runners show (v0.0.12's full tests hung for two hours on
Windows, a bash step ran under PowerShell). Run it by hand before a release, and after a change to a reusable
workflow or an action in `.github/`. Its first job builds the site and makes the package in a browser; the second
rewrites every caller's `@vX.Y.Z` to the commit under test, pushes the package as a new commit on the sandbox's default
branch, starts r-cmd-check-extended by hand (it has no push trigger), waits for the default branch's coverage and full-tests runs (up to 60 minutes), opens a pull request that adds
`.github/e2e-fake-secret.txt` with a made-up key, waits for every run (giving up and cancelling at 200 minutes), and
writes the report to the job summary: a count of the runs by result (✅ passed, ❌ failed, ⏳ no runner, 🔒 the key
caught), the verdict, what it did with links (the commit under test, the sandbox commit,
the pull request, how long it waited), a table of the runs and each problem. A job that GitHub never gave a
runner (it happens when no macOS runner is free) is listed on its own line as "no runner", not as a test failure,
and its matrix's summary job is not counted either; the run still fails, so run the test again later. Given a launchR pull request number when
started (`release_pr`), a third job posts the report there as one comment, updated on a re-run, or a short note
when the run stopped before its report; it uses launchR's own token, limited to that job, and never the sandbox's.
A run started by hand shows only under Actions (sandbox-e2e), never in a pull request's Checks tab: give
`release_pr` to see its result on the pull request.
The pull request in the sandbox stays open until the next run closes it, for a look
at its report comment. Dependabot's file is left out of the sandbox copy: it would open pull requests moving the callers
back to a tag.

What it needs, once:

- **The sandbox:** the public repository `insightsurge/launchr-sandbox` (`SANDBOX_REPO` in the workflow), empty or
  not, with `main` as its default branch. Public, so its runs cost no minutes; nothing private goes there. It is for
  launchR alone: Wiki, Projects and Discussions are off (Issues stay on: the "Set up this repository" dry run
  reads them and stops when they are off), workflows from outside contributors' pull requests
  wait for approval, and an interaction limit lets only collaborators open issues or pull requests or comment.
  GitHub ends that limit after six months (next on 2027-05-04): set it again under Settings, Moderation options,
  Interaction limits.
- **The token:** a fine-grained personal access token for that repository alone, with read and write access to
  Actions, Contents, Pull requests and Workflows (pushing files under `.github/workflows/` needs Workflows), kept as the
  launchR repository secret `SANDBOX_TOKEN`. When it expires the push step fails with an error from GitHub: make a new
  one the same way and replace the secret. The workflow runs only when started by hand, so no pull request can reach
  the token, and the job that runs npm packages never sees it.

## Security model of the reusable workflows

A package's caller file runs launchR's workflow with the **caller's token**. What that token may do is what the
caller's `permissions:` block says, and a called workflow can only narrow it.

- **Default is read-only.** Every workflow starts with `permissions: contents: read`. A job that needs more asks
  for it on that job.
- **Jobs that run the package's code** (R CMD check, tests, lint, coverage) have a read-only token,
  and their checkouts do not leave the token in `.git` (`persist-credentials: false`). `coverage.yaml` keeps it in
  one checkout because it runs `git fetch` for the base branch; the token is read-only.
- **Write access is rare.** Besides the Pages deploy below, two jobs can write. The `report` job has `pull-requests: write` and `actions: read`, runs no package code (it
  checks out only `.github` and launchR), and copies the report parts in as Markdown without running them. It is
  skipped for pull requests from forks and from Dependabot, whose tokens cannot write; they get the job summary. The `github-setup` job has `issues: write` for labels and checklists; it runs only launchR's
  own script, never the package's code, and only when started by hand, or as a dry run that changes nothing when its file is pushed.
- **`pull_request`, never `pull_request_target`:** a pull request from outside never runs with the base repository's
  secrets.
- **Secrets:** none are inherited. The only one is the optional `CODECOV_TOKEN`, which a package passes in its
  `coverage.yaml` caller.
- **launchR's own scripts** are fetched at `job.workflow_sha`, the commit of the workflow file being run, so a workflow
  at `@vX.Y.Z` runs the scripts of `vX.Y.Z`.
- **Pages deploy** (`pkgdown.yaml`): its one job builds the site (this runs the package's code) and publishes it, so
  it has `pages: write` and `id-token: write`. It runs on the default branch only and never on pull requests.
- **Actions we call:** GitHub's (`actions/*`) and r-lib's (`r-lib/actions/*`) by major-version tag, which Dependabot
  keeps current; every other action by full commit SHA with the version in a comment. zizmor enforces this
  (`.github/zizmor.yml`).
- **launchR's own site deploy** (`deploy-site.yaml`): the job that runs `npm ci` has `contents: read` only; the job that
  can sign in to Google (`id-token: write`) only downloads the built site and installs `firebase-tools` from its own
  lockfile with install scripts off. Keep it that way.
- When you add a workflow or a job, say why in a comment next to each permission, and run actionlint and zizmor.
  A new workflow, or a change to when one runs or where its result shows, also updates `.github/workflows/README.md`.
