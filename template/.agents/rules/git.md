# Branches, commits and pull requests

- **Start with an issue,** opened with one of the issue forms: the goal and a "done when" checklist. One issue per
  piece of work.
- **Branch from the default branch** (`main` or `master`) for that issue. Changes reach it only through pull
  requests.
- **Commits:** Conventional Commits, short (`feat:`, `fix:`, `docs:`, `test:`, `ci:`, `refactor:`, `chore:`).
- **Pull requests** use the template. The title is a Conventional Commit, since squash merging makes it the commit
  on the default branch. List the checks you ran and what they printed.
- Don't commit build output (`*.Rcheck/`, `*.tar.gz`, `docs/`) or local settings (`.Renviron`, `.Rhistory`).
- Never force-push, rewrite history that is already pushed, or use `--no-verify`.
- The maintainer merges, once CI is green.
