# Working on launchR

For anyone changing launchR itself, person or AI. How the pieces fit is in [README.md](README.md); what to touch for
each job, how to release, and what each test covers is in [CONTRIBUTING.md](CONTRIBUTING.md) (read its section for your
job before you start).

## Layout

| Folder | What it holds |
| --- | --- |
| `lists/` and `template/` | The single source: choices, checks, files, checklists, and the package template. The site and the command line both read them. |
| `cli/` | The R command line (`launchr.R`, `github-setup.R`, `cli/R/`). |
| `site/` | The website and setup form (Astro; the form's logic is `site/src/form/`). |
| `.github/` | The reusable workflows, actions and scripts that packages call at a release tag. |
| `quality-gate/` | `quality-gate.R`, the local gate that mirrors the checks. |
| `tests/` | The tests; `tests/README.md` says what each checks. |

A change to a choice, a check or a template file goes into `lists/` or `template/` first, and the site and the command
line follow. Many jobs touch only `site/` or only the rest: keep to the one that fits.

## Running tests

- Cheap, run while iterating: `node tests/compare-routes.mjs`, `Rscript tests/cli-tests.R` (about 90 s, quiet by
  default; `--verbose` lists every check), `bash tests/build-comment-tests.sh`.
- Slow, left to CI or the maintainer: `bash tests/gate-matrix.sh`, the Playwright tests in `site/tests/`, and
  `tests/sandbox-e2e.sh` (run by hand before a release).
- Do not run the slow ones unprompted. The Tests table in CONTRIBUTING.md has every command.

## House rules

- Every change starts with an issue; bigger pull requests that ship related work together are preferred over many
  small ones. Releases are tags (CONTRIBUTING.md, "Release"); do not cut one without being asked.
- A change to how something works updates every text that describes it in the same pull request.
- Keep the `launchr-fetch-start` / `launchr-fetch-end` block in the reusable workflows exactly as it is (`eject` relies on it).
