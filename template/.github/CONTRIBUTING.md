# Contributing to {{package}}

Thank you for helping with {{package}}. To report a bug or suggest an idea, open an issue with one of the issue forms.
To change something yourself, read the workflow below and open a pull request.

## Setup

- **R**: the current release is recommended. The minimum version is in `DESCRIPTION`.
- **Development packages**: from the package root, run `pak::local_install_dev_deps()` (or
  `devtools::install_dev_deps()`).
- **Air**, the formatter for R code: <https://posit-dev.github.io/air/>. The settings are in `air.toml`.
- **Biome**, only if the repository has a `biome.json`: the formatter and linter for JavaScript and CSS in `inst/`,
  <https://biomejs.dev>.
- **Google Chrome or Chromium**, only if the repository has browser tests.
- If you use renv, set up your own library; the repository does not ship one.

CI runs on every pull request, so you do not need anything else installed. How CI works is in
[`.github/workflows/README.md`](workflows/README.md).

## Workflow

1. **Start with an issue**, using an issue form. State the goal and a "done when" checklist. One issue per piece of
   work; ask first if the change is large. Keep its description current when scope or decisions change. Tick the
   items a pull request delivers, and say what stays open.
2. **Make a branch** from `main` for that issue.
3. **Commit with Conventional Commits**, short: `feat:`, `fix:`, `docs:`, `chore:`, `test:`, `ci:`, `refactor:`.
4. **Open a pull request** using the template. Keep the sections that apply, put repeatable checks in its table and
   one-off observations in Notes.
5. **Suggest a label** in the pull request: one of `enhancement`, `bug`, `documentation` or `chore`. The maintainer
   applies it; the release notes are built from it.
6. **The maintainer merges** once CI is green. Pull requests are squash-merged, so the pull request title becomes the
   commit message on `main`: keep it a Conventional Commit.

Update every text that describes what you changed, in the same pull request: help pages (through roxygen2), articles,
the README, `NEWS.md` and the examples; workflow comments and the instruction files if the repository has them
(`AGENTS.md`, `CLAUDE.md`); and any other page or file that describes the behaviour, including ones added later. It
works both ways: if you edit an article or an example, check that the help page still agrees. Search the repository
for the old wording and list the search terms in the pull request.

Changes reach `main` through pull requests. Never force-push, push to `main`, or skip checks with `--no-verify`. CI on
a pull request from a fork waits for a maintainer to approve the run. Leave "Allow edits by maintainers" on, so a
maintainer can fix a small thing, such as a typo or a failing format check, on your branch.

Stacked pull requests are fine. Base the second one on the branch below it, and say so in its description.

## Before you open a pull request

From the package root:

```r
devtools::document()   # help pages and NAMESPACE, from the roxygen2 comments
devtools::test()       # the tests
devtools::check()      # the same R CMD check that CI runs, with the same pass mark
```

```sh
air format .           # R code style
```

- Commit the files `devtools::document()` changes together with the source.
- An unknown word fails the spelling check: list it in your pull request, and the maintainer adds agreed words to
  `inst/WORDLIST`.
- A failing check on a pull request is read from its log in the Checks tab. Fix the first failure and push again.

## Code in short

- Write help and offline examples with roxygen2. Every exported function documents its return value.
- Call other packages as `pkg::fn()` and add them to `DESCRIPTION` first.
- Check arguments at the top of exported functions, and give messages that say what to do next.
- Keep JavaScript and CSS in `inst/` plain and readable. Bundle what the package needs; do not load anything from a
  CDN.
- Accessibility: meaning never rests on colour alone. Honour `prefers-reduced-motion`.

## Tests

Tests use testthat, one test file per R file. Add a test for every new behaviour and every fixed bug, and keep example
data made up. Browser and snapshot tests that CRAN skips live in their own files and run in CI.

## NEWS.md

Add one bullet for each user-facing change, in the same pull request. Write it for users, in the present tense, start
with the function or feature, and end with the issue number:

```md
* `say_hello()` gains a `name` argument (#123).
```

Release headings and versions belong to the maintainer.

## Licence of contributions

Contributions use the package's licence (see `LICENSE`). Before adding third-party files, check that their licence
allows it, and say where they came from.

## Conduct and data

Everyone taking part follows the [code of conduct](CODE_OF_CONDUCT.md). Be kind and patient, and give feedback on the
work, not the person. For a security problem, do not open an issue; follow the [security policy](SECURITY.md). For
questions, use [Discussions](https://github.com/{{owner}}/{{package}}/discussions) rather than an issue.

Use made-up data in examples and screenshots. Leave out private data, credentials and machine paths.
