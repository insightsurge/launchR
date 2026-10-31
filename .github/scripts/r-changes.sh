#!/usr/bin/env bash
# Writes r=true to the step's outputs unless this run is for a pull request that changes only documentation that
# R CMD check, the tests and coverage never read (the website's articles and settings, the README, the docs folder and
# the repository's own notes). The R jobs still start and report, so every check still reports; their R steps are
# skipped. Needs a checkout with fetch-depth 2: a pull request's merge commit and its base.
set -euo pipefail

if [ "${GITHUB_EVENT_NAME:-}" != "pull_request" ]; then
  echo "r=true" >>"$GITHUB_OUTPUT"
  exit 0
fi

changed=$(git diff --name-only --no-renames HEAD^1 HEAD)
r=false
if [ -z "$changed" ]; then
  r=true
fi
while IFS= read -r file; do
  [ -z "$file" ] && continue
  case "$file" in
    README.md | _pkgdown.yml | AGENTS.md | CLAUDE.md | docs/* | pkgdown/* | vignettes/articles/* | \
      .github/ISSUE_TEMPLATE/* | .github/*.md | .claude/*) ;;
    *) r=true ;;
  esac
done <<<"$changed"

echo "Files changed by this pull request:"
printf '  %s\n' $changed
if [ "$r" = true ]; then
  echo "R steps run."
else
  echo "Documentation only: the R steps are skipped."
fi
echo "r=$r" >>"$GITHUB_OUTPUT"
