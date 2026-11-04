# Working on this package

Rules for everyone who works here, person or AI. This file loads in every AI session, so it stays short. The detailed
rules are in `.agents/rules/`: read the file that fits before you start.

| Before you change | Read |
| --- | --- |
| R code in `R/` | `.agents/rules/r-code.md` |
| Tests in `tests/` | `.agents/rules/tests.md` |
| Help pages, README, NEWS or articles | `.agents/rules/docs.md` |
| `DESCRIPTION`, CI, or before a pull request | `.agents/rules/checks.md` |
| JavaScript or CSS in `inst/` | `.agents/rules/js-css.md` |
| Branches, commits and pull requests | `.agents/rules/git.md` |

## Always

- Change only what the task needs. Ask before adding a dependency, changing a check or deleting a file.
- `man/` and `NAMESPACE` come from `devtools::document()`, never from hand edits.
- Add a test for every change, and a `NEWS.md` bullet for anything users notice.
- Never push to the default branch (`main` or `master`), force-push or skip a check. When a check fails, fix the
  cause; don't loosen the check.
- Keep secrets, private data and machine paths out of code, tests, examples and commits.
- Report what you ran and what it printed, failures and skipped steps included.
