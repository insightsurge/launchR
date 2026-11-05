#!/usr/bin/env bash
# Checks caller compatibility:
# 1. Previous release tag's callers against this commit's reusable workflows.
# 2. This commit's callers against workflows at tag v<kit_version> in lists/settings.tsv.
# Uses actionlint to validate inputs, secrets, and uses.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ACTIONLINT="${ACTIONLINT:-actionlint}"

for tool in git Rscript; do
  command -v "$tool" >/dev/null 2>&1 || { echo "missing required tool: $tool" >&2; exit 2; }
done

command -v "$ACTIONLINT" >/dev/null 2>&1 || { echo "actionlint not found at '$ACTIONLINT'" >&2; exit 2; }

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

render_callers() {
  local cli="$1"
  local dest="$2"

  mkdir -p "$dest"
  Rscript "$cli" new comppkg --yes --title "Compat Tools" --author "Asha Rao" \
    --owner sample-org --no-git --preset everything --plan a --path "${dest}/pkg-a" >/dev/null 2>&1

  Rscript "$cli" new comppkg --yes --title "Compat Tools" --author "Asha Rao" \
    --owner sample-org --no-git --preset everything --plan d --path "${dest}/pkg-d" >/dev/null 2>&1

  Rscript "$cli" new comppkg --yes --title "Compat Tools" --author "Asha Rao" \
    --owner sample-org --no-git --preset everything --plan a --no-ci-report --path "${dest}/pkg-noci" >/dev/null 2>&1
}

prepare_callers() {
  local callers_dir="$1"
  local check_dir="$2"

  for variant in pkg-a pkg-d pkg-noci; do
    if [ -d "${callers_dir}/${variant}/.github/workflows" ]; then
      for f in "${callers_dir}/${variant}/.github/workflows"/*.yaml "${callers_dir}/${variant}/.github/workflows"/*.yml; do
        [ -f "$f" ] || continue
        local bname
        bname="$(basename "$f")"
        sed -E 's|uses: insightsurge/launchR/\.github/workflows/([^@]+)@.*|uses: ./.github/workflows/\1|' \
          "$f" > "${check_dir}/.github/workflows/caller-${variant}-${bname}"
      done
    fi
  done
}

run_check() {
  local check_dir="$1"
  local dir_desc="$2"

  local files=()
  for f in "${check_dir}/.github/workflows"/caller-*.yaml "${check_dir}/.github/workflows"/caller-*.yml; do
    [ -f "$f" ] && files+=(".github/workflows/$(basename "$f")")
  done

  if [ ${#files[@]} -eq 0 ]; then
    echo "FAIL ${dir_desc}: no caller files generated to check"
    return 1
  fi

  local lint_out
  lint_out=$( (cd "$check_dir" && "$ACTIONLINT" -oneline "${files[@]}" 2>&1) || true )

  local call_findings=""
  local other_findings=""

  if [ -n "$lint_out" ]; then
    while IFS= read -r line; do
      [ -z "$line" ] && continue
      if echo "$line" | grep -qE '\[workflow-call\]|reusable workflow|input ".*" is typed as|unexpected input|missing input|unknown input|unexpected secret|missing secret|unknown secret'; then
        call_findings="${call_findings}${call_findings:+$'\n'}${line}"
      else
        other_findings="${other_findings}${other_findings:+$'\n'}${line}"
      fi
    done <<< "$lint_out"
  fi

  if [ -n "$other_findings" ]; then
    echo "Harmless non-call findings (${dir_desc}):"
    while IFS= read -r line; do
      [ -z "$line" ] && continue
      echo "  $line"
    done <<< "$other_findings"
  fi

  if [ -n "$call_findings" ]; then
    echo "FAIL ${dir_desc}"
    while IFS= read -r line; do
      [ -z "$line" ] && continue
      echo "  $line"
    done <<< "$call_findings"
    return 1
  else
    echo "PASS ${dir_desc}"
    return 0
  fi
}

exit_code=0

# ---- Direction 1: previous release callers against this commit's workflows ----
PREV_TAG="$(git tag -l "v*" --sort=-v:refname | head -n 1)"
if [ -z "$PREV_TAG" ]; then
  echo "FAIL direction 1: no previous release tag found"
  exit_code=1
else
  PREV_ARCHIVE="${TMP_DIR}/prev_archive"
  mkdir -p "$PREV_ARCHIVE"
  git archive "$PREV_TAG" | tar -x -C "$PREV_ARCHIVE"

  PREV_CALLERS="${TMP_DIR}/prev_callers"
  render_callers "$PREV_ARCHIVE/cli/launchr.R" "$PREV_CALLERS"

  CHECK_DIR_1="${TMP_DIR}/check_dir_1"
  mkdir -p "${CHECK_DIR_1}/.github/workflows"
  (cd "$CHECK_DIR_1" && git init -b main >/dev/null)
  [ -f "$REPO_ROOT/.github/actionlint.yaml" ] && cp "$REPO_ROOT/.github/actionlint.yaml" "${CHECK_DIR_1}/.github/"

  cp "$REPO_ROOT"/.github/workflows/*.yaml "${CHECK_DIR_1}/.github/workflows/" 2>/dev/null || true
  cp "$REPO_ROOT"/.github/workflows/*.yml "${CHECK_DIR_1}/.github/workflows/" 2>/dev/null || true

  prepare_callers "$PREV_CALLERS" "$CHECK_DIR_1"

  if ! run_check "$CHECK_DIR_1" "direction 1: previous release callers (${PREV_TAG}) against this commit's workflows"; then
    exit_code=1
  fi
fi

# ---- Direction 2: this commit's callers against tag in lists/settings.tsv ----
KIT_VERSION="$(awk -F'\t' '$1 == "kit_version" { print $2 }' "$REPO_ROOT/lists/settings.tsv")"
if [ -z "$KIT_VERSION" ]; then
  echo "FAIL direction 2: could not read kit_version from lists/settings.tsv"
  exit_code=1
else
  KIT_TAG="v${KIT_VERSION}"

  THIS_CALLERS="${TMP_DIR}/this_callers"
  render_callers "$REPO_ROOT/cli/launchr.R" "$THIS_CALLERS"

  CHECK_DIR_2="${TMP_DIR}/check_dir_2"
  mkdir -p "${CHECK_DIR_2}/.github/workflows"
  (cd "$CHECK_DIR_2" && git init -b main >/dev/null)
  [ -f "$REPO_ROOT/.github/actionlint.yaml" ] && cp "$REPO_ROOT/.github/actionlint.yaml" "${CHECK_DIR_2}/.github/"

  if git rev-parse -q --verify "refs/tags/${KIT_TAG}" >/dev/null; then
    for wf in $(git ls-tree -r --name-only "${KIT_TAG}" .github/workflows 2>/dev/null | grep -E '\.ya?ml$' || true); do
      mkdir -p "${CHECK_DIR_2}/$(dirname "$wf")"
      git show "${KIT_TAG}:${wf}" > "${CHECK_DIR_2}/${wf}"
    done
    dir2_desc="direction 2: this commit's callers against ${KIT_TAG} workflows"
  else
    echo "Tag ${KIT_TAG} does not exist yet; checking against this commit's workflows instead."
    cp "$REPO_ROOT"/.github/workflows/*.yaml "${CHECK_DIR_2}/.github/workflows/" 2>/dev/null || true
    cp "$REPO_ROOT"/.github/workflows/*.yml "${CHECK_DIR_2}/.github/workflows/" 2>/dev/null || true
    dir2_desc="direction 2: this commit's callers against this commit's workflows (${KIT_TAG} not tagged yet)"
  fi

  prepare_callers "$THIS_CALLERS" "$CHECK_DIR_2"

  if ! run_check "$CHECK_DIR_2" "$dir2_desc"; then
    exit_code=1
  fi
fi

exit "$exit_code"
