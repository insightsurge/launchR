#!/usr/bin/env bash
# The steps of .github/workflows/sandbox-e2e.yaml: a package made on the site runs its own checks in a public sandbox
# repository, pointed at the launchR commit under test. One step per call:
#
#   prepare   unzip the package and point every caller at LAUNCHR_SHA instead of the release tag
#   push      push it to the sandbox's default branch and start r-cmd-check-extended (it has no push trigger)
#   pr        open a pull request that plants a fake secret
#   wait      wait for every run of both commits, cancelling what is still running at the deadline
#   report    fail when a check failed (other than secret-scan on the pull request, which must fail), linking each
#             failed job, and when the pull request has other than one report comment
#
# Needs: bash, git, gh, jq, unzip, openssl. Environment: SANDBOX_REPO (owner/name), SANDBOX_PACKAGE (the package's
# name), WORK (an empty folder; on GitHub, RUNNER_TEMP/sandbox by default), and for push, pr, wait and report GH_TOKEN (a token for the sandbox alone: contents,
# pull requests, actions and workflows read and write). push and pr write their results (MAIN_SHA, PR_SHA, PR_NUMBER,
# BRANCH) to WORK/state, which the later steps read; on GitHub they also go to GITHUB_ENV.
set -euo pipefail

: "${SANDBOX_REPO:?}" "${SANDBOX_PACKAGE:?}"
WORK="${WORK:-${RUNNER_TEMP:?Set WORK}/sandbox}"
PKG="${WORK}/package/${SANDBOX_PACKAGE}"
STATE="${WORK}/state"
SUMMARY="${GITHUB_STEP_SUMMARY:-/dev/stdout}"
CALLER_RE='insightsurge/launchR/\.github/workflows/[a-z-]+\.yaml@'
# shellcheck source=/dev/null
[ -f "${STATE}" ] && . "${STATE}"

save() {
  echo "$1=$2" >> "${STATE}"
  if [ -n "${GITHUB_ENV:-}" ]; then echo "$1=$2" >> "${GITHUB_ENV}"; fi
  export "$1=$2"
}

# git over HTTPS with GH_TOKEN, and nothing written to .git/config.
sgit() { git -c credential.helper= -c credential.helper='!gh auth git-credential' "$@"; }

# The caller files that a push to the default branch (or, with pull_request, a pull request into it) starts.
# github-setup.yaml runs on a push only when its own file changed, so it is not expected; when it runs, it counts.
callers() {
  local event=$1 file
  for file in "${PKG}"/.github/workflows/*.yaml; do
    case "$(basename "${file}")" in github-setup.yaml) continue ;; esac
    if [ "${event}" = push ] || grep -q "^  ${event}:" "${file}"; then echo ".github/workflows/$(basename "${file}")"; fi
  done
}

prepare() {
  : "${ZIP:?}" "${LAUNCHR_SHA:?}"
  mkdir -p "${WORK}/package"
  unzip -q "${ZIP}" -d "${WORK}/package"
  [ -f "${PKG}/DESCRIPTION" ] || { echo "::error::The zip has no ${SANDBOX_PACKAGE}/DESCRIPTION."; exit 1; }
  local count
  count=$({ grep -rhoE "${CALLER_RE}v[0-9.]+" "${PKG}/.github/workflows" || true; } | wc -l | tr -d ' ')
  [ "${count}" -gt 0 ] || { echo "::error::No caller in the zip names a launchR release tag."; exit 1; }
  sed -i.bak -E "s#(${CALLER_RE})v[0-9.]+#\1${LAUNCHR_SHA}#" "${PKG}"/.github/workflows/*.yaml
  rm -f "${PKG}"/.github/workflows/*.bak
  if grep -rnE "${CALLER_RE}v" "${PKG}/.github/workflows"; then
    echo "::error::A caller still names a release tag (above)."
    exit 1
  fi
  # Dependabot would open pull requests in the sandbox to move these callers back to a tag; it is not a check.
  rm -f "${PKG}/.github/dependabot.yml"
  echo "Pointed ${count} callers at launchR ${LAUNCHR_SHA}."
}

push() {
  : "${LAUNCHR_SHA:?}"
  local branch repo="${WORK}/repo"
  branch=$(gh api "repos/${SANDBOX_REPO}" --jq .default_branch)
  grep -q "branches: \[${branch}\]" "${PKG}/.github/workflows/r-cmd-check.yaml" || {
    echo "::error::The package's checks run on another branch than the sandbox's default branch (${branch})."
    exit 1
  }
  # Close what an earlier run left open.
  gh pr list -R "${SANDBOX_REPO}" --state open --json number,headRefName \
    --jq '.[] | select(.headRefName | startswith("sandbox-e2e-")) | .number' |
    while read -r number; do gh pr close "${number}" -R "${SANDBOX_REPO}" --delete-branch; done

  # A new commit on top of the default branch whose files are exactly the package's (history kept, nothing forced).
  git init -q -b "${branch}" "${repo}"
  cd "${repo}"
  git config user.name "github-actions[bot]"
  git config user.email "41898282+github-actions[bot]@users.noreply.github.com"
  git remote add origin "https://github.com/${SANDBOX_REPO}.git"
  if sgit fetch -q --depth=1 origin "${branch}"; then git reset -q --soft FETCH_HEAD; fi
  cp -R "${PKG}/." .
  git add -A
  git commit -q --allow-empty -m "Package from the site, checks at launchR ${LAUNCHR_SHA}" \
    -m "${RUN_URL:-Run by hand}"
  sgit push -q origin "HEAD:refs/heads/${branch}"
  save MAIN_SHA "$(git rev-parse HEAD)"
  save BRANCH "${branch}"
  echo "Pushed ${MAIN_SHA} to ${SANDBOX_REPO}@${branch}."

  # r-cmd-check-extended runs weekly or by hand. GitHub may need a moment to see the new file.
  local try
  for try in 1 2 3 4 5 6 7 8 9 10; do
    if gh workflow run r-cmd-check-extended.yaml -R "${SANDBOX_REPO}" --ref "${branch}"; then return 0; fi
    echo "Not startable yet (try ${try}); waiting."
    sleep 15
  done
  echo "::error::Could not start r-cmd-check-extended in the sandbox."
  exit 1
}

pr() {
  : "${MAIN_SHA:?}" "${BRANCH:?}"
  local head="sandbox-e2e-${GITHUB_RUN_ID:-$(date +%s)}" secret
  cd "${WORK}/repo"
  git switch -q -c "${head}" "${MAIN_SHA}"
  # A made-up key, new each run, that gitleaks' generic rule catches and GitHub's push protection does not (it is no
  # provider's format). In .github/, which R CMD build leaves out, so no other check sees it.
  secret="Zq8$(openssl rand -base64 48 | tr -dc 'A-Za-z0-9' | head -c 32)"
  printf 'SANDBOX_API_KEY = "%s"\n' "${secret}" > .github/e2e-fake-secret.txt
  git add .github/e2e-fake-secret.txt
  git commit -q -m "Plant a fake secret for secret-scan to catch"
  sgit push -q origin "HEAD:refs/heads/${head}"
  save PR_SHA "$(git rev-parse HEAD)"
  local url
  url=$(gh pr create -R "${SANDBOX_REPO}" --base "${BRANCH}" --head "${head}" \
    --title "Sandbox test: a planted secret" \
    --body "Opened by launchR's sandbox test (${RUN_URL:-run by hand}). secret-scan must fail here; every other check must pass, and the CI report must be one comment.")
  save PR_NUMBER "${url##*/}"
  echo "Opened ${url}."
}

# The runs of one commit as JSON lines: id, path (without @ref), event, status, conclusion, html_url, name.
runs_of() {
  gh api --paginate "repos/${SANDBOX_REPO}/actions/runs?head_sha=$1&per_page=100" \
    --jq '.workflow_runs[] | {id, path: (.path | sub("@.*$"; "")), event, status, conclusion, html_url, name}'
}

all_runs() {
  runs_of "${MAIN_SHA}" | jq -c '. + {commit: "main"}'
  runs_of "${PR_SHA}" | jq -c 'select(.event == "pull_request") | . + {commit: "pr"}'
}

wait_runs() {
  : "${MAIN_SHA:?}" "${PR_SHA:?}"
  local deadline=$(( $(date +%s) + ${WAIT_MINUTES:-200} * 60 )) runs missing open settled=0
  while :; do
    runs=$(all_runs)
    missing=$( { callers push | sed 's/^/main /'; callers pull_request | sed 's/^/pr /'; } |
      while read -r commit path; do
        jq -e --arg c "${commit}" --arg p "${path}" 'select(.commit == $c and .path == $p)' <<< "${runs}" >/dev/null ||
          echo "${commit}:${path}"
      done)
    open=$(jq -r 'select(.status != "completed") | .id' <<< "${runs}")
    if [ -z "${missing}" ] && [ -z "${open}" ]; then
      # Once more after a minute, for a run that started late.
      settled=$((settled + 1))
      [ "${settled}" -ge 2 ] && break
    else
      settled=0
    fi
    if [ "$(date +%s)" -ge "${deadline}" ]; then
      echo "::error::Still waiting after ${WAIT_MINUTES:-200} minutes. Not started: ${missing:-none}."
      for id in ${open}; do gh api -X POST "repos/${SANDBOX_REPO}/actions/runs/${id}/cancel" >/dev/null || true; done
      echo "Cancelled the runs still going: ${open:-none}."
      break
    fi
    echo "$(date -u +%H:%M) waiting: $(wc -w <<< "${open}" | tr -d " ") running, not started: ${missing:-none}"
    sleep 60
  done
}

report() {
  : "${MAIN_SHA:?}" "${PR_SHA:?}" "${PR_NUMBER:?}"
  local runs problems=0 line id path commit conclusion url jobs bad job
  runs=$(all_runs)
  {
    echo "## Sandbox test"
    echo
    echo "Package pushed to [${SANDBOX_REPO}](https://github.com/${SANDBOX_REPO}/commit/${MAIN_SHA}), pull request [#${PR_NUMBER}](https://github.com/${SANDBOX_REPO}/pull/${PR_NUMBER})."
    echo
    echo "| Where | Workflow | Event | Result |"
    echo "| --- | --- | --- | --- |"
    jq -r '"| \(.commit) | [\(.path | sub(".github/workflows/"; ""))](\(.html_url)) | \(.event) | \(.conclusion // .status) |"' <<< "${runs}" | sort
    echo
  } >> "${SUMMARY}"

  # Expected runs that never started.
  while read -r commit path; do
    if ! jq -e --arg c "${commit}" --arg p "${path}" 'select(.commit == $c and .path == $p)' <<< "${runs}" >/dev/null; then
      echo "- ❌ ${path} never ran on the ${commit} commit." >> "${SUMMARY}"
      echo "::error::${path} never ran on the ${commit} commit."
      problems=$((problems + 1))
    fi
  done < <(callers push | sed 's/^/main /'; callers pull_request | sed 's/^/pr /')

  while read -r line; do
    id=$(jq -r .id <<< "${line}")
    path=$(jq -r .path <<< "${line}")
    commit=$(jq -r .commit <<< "${line}")
    conclusion=$(jq -r '.conclusion // .status' <<< "${line}")
    url=$(jq -r .html_url <<< "${line}")
    jobs=$(gh api --paginate "repos/${SANDBOX_REPO}/actions/runs/${id}/jobs?filter=latest&per_page=100" \
      --jq '.jobs[] | {name, conclusion, html_url}')
    bad=$(jq -c 'select(.conclusion != "success" and .conclusion != "skipped" and .conclusion != "neutral")' <<< "${jobs}")
    if [ "${commit}" = pr ] && [ "${path}" = .github/workflows/secret-scan.yaml ]; then
      # The scan itself must fail on the planted secret; its report job must still pass.
      if ! jq -e 'select((.name | sub(".* / "; "")) == "secret-scan" and .conclusion == "failure")' <<< "${jobs}" >/dev/null; then
        echo "- ❌ secret-scan did not fail on the planted secret: [run](${url})" >> "${SUMMARY}"
        echo "::error::secret-scan did not fail on the planted secret: ${url}"
        problems=$((problems + 1))
      fi
      bad=$(jq -c 'select((.name | sub(".* / "; "")) != "secret-scan")' <<< "${bad}")
      [ -n "${bad}" ] || continue
    elif [ "${conclusion}" = success ] || [ "${conclusion}" = skipped ]; then
      continue
    fi
    if [ -z "${bad}" ]; then
      # Failed with no failed job, such as a workflow file GitHub refused (startup_failure).
      echo "- ❌ ${path} on the ${commit} commit: ${conclusion}, [run](${url})" >> "${SUMMARY}"
      echo "::error::${path} on the ${commit} commit: ${conclusion}: ${url}"
      problems=$((problems + 1))
      continue
    fi
    while read -r job; do
      [ -n "${job}" ] || continue
      echo "- ❌ ${path} on the ${commit} commit, job \`$(jq -r .name <<< "${job}")\`: $(jq -r '.conclusion // "not finished"' <<< "${job}"), [log]($(jq -r .html_url <<< "${job}"))" >> "${SUMMARY}"
      echo "::error::${path} (${commit}), job $(jq -r .name <<< "${job}"): $(jq -r '.conclusion // "not finished"' <<< "${job}"): $(jq -r .html_url <<< "${job}")"
      problems=$((problems + 1))
    done <<< "${bad}"
  done <<< "${runs}"

  # One CI report comment, saying the secret scan failed.
  local comments count
  comments=$(gh api --paginate "repos/${SANDBOX_REPO}/issues/${PR_NUMBER}/comments" \
    --jq '.[] | select(.body | contains("<!-- Sticky Pull Request Comment")) | {body}' | jq -s .)
  count=$(jq length <<< "${comments}")
  if [ "${count}" != 1 ]; then
    echo "- ❌ The pull request has ${count} CI report comments, not one." >> "${SUMMARY}"
    echo "::error::The pull request has ${count} CI report comments, not one."
    problems=$((problems + 1))
  elif ! jq -e '.[0].body | contains("Secret scan:** failed")' <<< "${comments}" >/dev/null; then
    echo "- ❌ The CI report comment does not say the secret scan failed." >> "${SUMMARY}"
    echo "::error::The CI report comment does not say the secret scan failed."
    problems=$((problems + 1))
  fi

  if [ "${problems}" -gt 0 ]; then
    echo "**${problems} problem(s).**" >> "${SUMMARY}"
    exit 1
  fi
  echo "✅ Every check passed; secret-scan caught the planted secret and the report is one comment." >> "${SUMMARY}"
}

case "${1:-}" in
  prepare) prepare ;;
  push) push ;;
  pr) pr ;;
  wait) wait_runs ;;
  report) report ;;
  *) echo "Usage: $0 prepare|push|pr|wait|report" >&2; exit 2 ;;
esac
