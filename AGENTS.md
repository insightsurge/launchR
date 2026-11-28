# Working on launchR

For anyone changing launchR itself, person or AI. How the pieces fit and what each folder holds is in
[README.md](README.md) ("In this repository"); what to touch for each job, how to release, and what each test
covers is in [CONTRIBUTING.md](CONTRIBUTING.md) (read its section for your job before you start).

## Running tests

- Cheap, run while iterating: `node tests/compare-routes.mjs`, `Rscript tests/cli-tests.R`,
  `bash tests/build-comment-tests.sh`.
- Slow, left to CI or the maintainer, never run unprompted: `bash tests/gate-matrix.sh`, the Playwright tests in
  `site/tests/`, and `tests/sandbox-e2e.sh` (run by hand before a release).
- CONTRIBUTING.md's Tests table has every command.

## House rules

- A change to a choice, a check or a template file goes into `lists/` or `template/` first; the site and the command
  line follow.
- Every change starts with an issue; bigger pull requests that ship related work together are preferred over many
  small ones. Releases are tags (CONTRIBUTING.md, "Release"); do not cut one without being asked.
- A change to how something works updates every text that describes it in the same pull request.
- Keep the `launchr-fetch-start` / `launchr-fetch-end` block in the reusable workflows exactly as it is (`eject`
  relies on it).
