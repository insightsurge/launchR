#!/usr/bin/env bash
# The steps of .github/workflows/sandbox-e2e.yaml: a package made on the site runs its own checks in a public sandbox
# repository, pointed at the launchR commit under test. One step per call:
#
#   prepare   unzip the package and point every caller at LAUNCHR_SHA instead of the release tag
#   push      push it to the sandbox's default branch and start r-cmd-check-extended (it has no push trigger)
#   pr        open a pull request that plants a fake secret
#   wait      wait for every run of both commits, cancelling what is still running at the deadline
#   report    write the report to WORK/report.md and the job summary, and fail when a check failed (other than
#             secret-scan on the pull request, which must fail), linking each failed job, and when the pull request
#             has other than one report comment. A job GitHub never gave a runner (as when no macOS runner is
#             free) is listed apart, not as a failure: the run still fails, as the test is not finished
#   comment   post WORK/report.md (or, when the run stopped before it, a short note) as one comment on launchR pull
#             request RELEASE_PR, updating it on a re-run; GH_TOKEN here is launchR's own token, not the sandbox's
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
REPORT="${WORK}/report.md"
MARKER="<!-- launchr-sandbox-e2e -->"
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
  save CALLER_COUNT "${count}"
  echo "Pointed ${count} callers at launchR ${LAUNCHR_SHA}."
}

push() {
  : "${LAUNCHR_SHA:?}"
  local branch repo="${WORK}/repo"
  branch=$(gh api "repos/${SANDBOX_REPO}" --jq .default_branch)
  grep -qE "^    branches: \[([^]]*, )?${branch}[],]" "${PKG}/.github/workflows/r-cmd-check.yaml" || {
    echo "::error::The package's checks run on another branch than the sandbox's default branch (${branch})."
    exit 1
  }
  # Close what an earlier run left open.
  local number closed
  closed=$(gh pr list -R "${SANDBOX_REPO}" --state open --json number,headRefName \
    --jq '.[] | select(.headRefName | startswith("sandbox-e2e-")) | .number')
  for number in ${closed}; do gh pr close "${number}" -R "${SANDBOX_REPO}" --delete-branch; done
  save CLOSED_PRS "$(tr '\n' ',' <<< "${closed}" | sed 's/,*$//')"

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
  save WAIT_START "$(date +%s)"
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
      save WAIT_CANCELLED "$(wc -w <<< "${open}" | tr -d ' ')"
      break
    fi
    echo "$(date -u +%H:%M) waiting: $(wc -w <<< "${open}" | tr -d " ") running, not started: ${missing:-none}"
    sleep 60
  done
  save WAIT_END "$(date +%s)"
}

# The jobs of one run as JSON lines. GitHub has answered with no result for a job that had finished long before
# (2026-11-04), so a job without one is asked about again, up to three times, before it counts as not finished.
run_jobs() {
  local jobs try
  for try in 1 2 3; do
    jobs=$(gh api --paginate "repos/${SANDBOX_REPO}/actions/runs/$1/jobs?filter=latest&per_page=100" \
      --jq '.jobs[] | {name, conclusion, html_url, runner: (.runner_id // 0), steps: (.steps | length),
        failed: [.steps[]? | select(.conclusion == "failure") | .name]}')
    jq -e 'select(.conclusion == null)' <<< "${jobs}" >/dev/null || break
    [ "${try}" -eq 3 ] || sleep "${JOBS_RETRY_SECONDS:-20}"
  done
  printf '%s\n' "${jobs}"
}

report() {
  : "${MAIN_SHA:?}" "${PR_SHA:?}" "${PR_NUMBER:?}"
  local runs problems=0 line id path commit conclusion url jobs bad job norunner list="${WORK}/problems.md"
  local waiting="${WORK}/no-runner.md" verdicts="${WORK}/verdicts.tsv" caught
  runs=$(all_runs)
  : > "${list}"
  : > "${waiting}"
  : > "${verdicts}"
  # One line per run for the table: its id and its result, with an emoji.
  mark() { printf '%s\t%s\n' "${id}" "$1" >> "${verdicts}"; }

  # Expected runs that never started.
  while read -r commit path; do
    if ! jq -e --arg c "${commit}" --arg p "${path}" 'select(.commit == $c and .path == $p)' <<< "${runs}" >/dev/null; then
      echo "- ❌ ${path} never ran on the ${commit} commit." >> "${list}"
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
    jobs=$(run_jobs "${id}")
    # A job GitHub never gave a runner (cancelled with no runner and no steps, as when no macOS runner is free) is
    # not a test result: it is listed on its own. The matrix's summary job then fails only at its "Require every
    # matrix job to succeed" step; that follows from the missing runner, so it is not counted either.
    norunner=$(jq -c 'select(.conclusion == "cancelled" and .runner == 0 and .steps == 0)' <<< "${jobs}")
    if [ -n "${norunner}" ]; then
      jq -r --arg p "${path}" --arg c "${commit}" \
        '"- ⏳ \($p) on the \($c) commit, job `\(.name)`: GitHub had no runner for it, [job](\(.html_url))"' \
        <<< "${norunner}" >> "${waiting}"
      jobs=$(jq -c 'select((.conclusion == "cancelled" and .runner == 0 and .steps == 0) | not)
        | select(.failed != ["Require every matrix job to succeed"])' <<< "${jobs}")
      [ -n "${jobs}" ] || { mark "⏳ no runner"; continue; }
      jq -e 'select(.conclusion != "success" and .conclusion != "skipped" and .conclusion != "neutral")' \
        <<< "${jobs}" >/dev/null || { mark "⏳ no runner"; continue; }
    fi
    bad=$(jq -c 'select(.conclusion != "success" and .conclusion != "skipped" and .conclusion != "neutral")' <<< "${jobs}")
    if [ "${commit}" = pr ] && [ "${path}" = .github/workflows/secret-scan.yaml ]; then
      # The scan itself must fail on the planted secret; its report job must still pass.
      caught="🔒 caught the key"
      if ! jq -e 'select((.name | sub(".* / "; "")) == "secret-scan" and .conclusion == "failure")' <<< "${jobs}" >/dev/null; then
        echo "- ❌ secret-scan did not fail on the planted secret: [run](${url})" >> "${list}"
        echo "::error::secret-scan did not fail on the planted secret: ${url}"
        problems=$((problems + 1))
        caught="❌ 🔓 missed the key"
      fi
      bad=$(jq -c 'select((.name | sub(".* / "; "")) != "secret-scan")' <<< "${bad}")
      [ -n "${bad}" ] || { mark "${caught}"; continue; }
    elif [ "${conclusion}" = success ]; then
      mark "✅ passed"
      continue
    elif [ "${conclusion}" = skipped ]; then
      mark "⏭️ skipped"
      continue
    fi
    if [ -z "${bad}" ]; then
      # Failed with no failed job, such as a workflow file GitHub refused (startup_failure).
      echo "- ❌ ${path} on the ${commit} commit: ${conclusion}, [run](${url})" >> "${list}"
      echo "::error::${path} on the ${commit} commit: ${conclusion}: ${url}"
      problems=$((problems + 1))
      mark "❌ ${conclusion}"
      continue
    fi
    mark "❌ failed"
    while read -r job; do
      [ -n "${job}" ] || continue
      echo "- ❌ ${path} on the ${commit} commit, job \`$(jq -r .name <<< "${job}")\`: $(jq -r '.conclusion // "not finished"' <<< "${job}"), [log]($(jq -r .html_url <<< "${job}"))" >> "${list}"
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
    echo "- ❌ The pull request has ${count} CI report comments, not one." >> "${list}"
    echo "::error::The pull request has ${count} CI report comments, not one."
    problems=$((problems + 1))
  elif ! jq -e '.[0].body | contains("Secret scan:** failed")' <<< "${comments}" >/dev/null; then
    echo "- ❌ The CI report comment does not say the secret scan failed." >> "${list}"
    echo "::error::The CI report comment does not say the secret scan failed."
    problems=$((problems + 1))
  fi

  write_report "${runs}" "${problems}" "${list}" "${waiting}" "${verdicts}"
  cat "${REPORT}" >> "${SUMMARY}"
  if [ -s "${waiting}" ]; then echo "::error::GitHub had no runner for $(wc -l < "${waiting}" | tr -d ' ') job(s); run the test again."; fi
  [ "${problems}" -eq 0 ] && [ ! -s "${waiting}" ] || exit 1
}

# The report: the verdict, what the run did (with links), a table of the sandbox's runs, and the problems.
write_report() {
  local runs=$1 problems=$2 list=$3 waiting=$4 verdicts=$5 sandbox="https://github.com/${SANDBOX_REPO}" launchr minutes closed
  launchr="${GITHUB_SERVER_URL:-https://github.com}/${GITHUB_REPOSITORY:-insightsurge/launchR}"
  minutes=$(( (${WAIT_END:-${WAIT_START:-0}} - ${WAIT_START:-0}) / 60 ))
  closed=$(sed -E "s@([0-9]+)@[#\\1](${sandbox}/pull/\\1)@g; s@,@, @g" <<< "${CLOSED_PRS:-}")
  {
    echo "${MARKER}"
    echo "## Sandbox test"
    echo
    quick_look "${verdicts}"
    echo
    local unrun
    unrun=$(wc -l < "${waiting}" | tr -d ' ')
    if [ "${problems}" -gt 0 ]; then
      echo "❌ **${problems} problem(s)**, listed below.$([ "${unrun}" -gt 0 ] && echo " GitHub also had no runner for ${unrun} job(s).")"
    elif [ "${unrun}" -gt 0 ]; then
      echo "⏳ **Not finished: GitHub had no runner for ${unrun} job(s)**, listed below. Everything that ran passed. Run the test again when runners are free."
    else
      echo "✅ Every check passed; secret-scan caught the planted secret and the report is one comment."
    fi
    echo
    echo "### What it did"
    echo
    echo "1. Built the site and made \`${SANDBOX_PACKAGE}\` in a browser, with the choices in [\`sandbox-package.spec.js\`](${launchr}/blob/${LAUNCHR_SHA}/site/tests/sandbox-package.spec.js) ([run](${RUN_URL:-${launchr}/actions}))."
    echo "2. Pointed its ${CALLER_COUNT:-?} callers at launchR [\`${LAUNCHR_SHA:0:7}\`](${launchr}/commit/${LAUNCHR_SHA}) instead of a release tag."
    echo "3. Pushed it to the sandbox's \`${BRANCH:-main}\` as [\`${MAIN_SHA:0:7}\`](${sandbox}/commit/${MAIN_SHA}) and started r-cmd-check-extended by hand${closed:+, after closing ${closed} from an earlier run}."
    echo "4. Opened pull request [#${PR_NUMBER}](${sandbox}/pull/${PR_NUMBER}) with a planted fake key."
    echo "5. Waited ${minutes} minutes for $(jq -s length <<< "${runs}") runs$([ -n "${WAIT_CANCELLED:-}" ] && echo ", cancelling ${WAIT_CANCELLED} still going at the deadline")."
    echo
    echo "| Where | Workflow | Event | Result |"
    echo "| --- | --- | --- | --- |"
    jq -r --rawfile v "${verdicts}" '($v | split("\n") | map(select(. != "") | split("\t") | {(.[0]): .[1]}) | add // {}) as $m
      | "| \(.commit) | [\(.path | sub(".github/workflows/"; ""))](\(.html_url)) | \(.event) | \($m[.id | tostring] // (.conclusion // .status)) |"' \
      <<< "${runs}" | sort
    if [ -s "${list}" ]; then
      echo
      cat "${list}"
    fi
    if [ -s "${waiting}" ]; then
      echo
      cat "${waiting}"
    fi
  } > "${REPORT}"
}

# The first line of the report: how many of the sandbox's runs ended each way, in a fixed order.
quick_look() {
  local line="" n label
  for label in "✅|passed" "❌|failed" "⏳|had no runner" "⏭️|skipped"; do
    n=$(cut -f2 "$1" | grep -c "^${label%%|*}" || true)
    [ "${n}" -gt 0 ] || [ "${label%%|*}" = "✅" ] || continue
    line="${line:+${line} · }${label%%|*} **${n}** ${label#*|}"
  done
  if grep -q "🔒" "$1"; then line="${line} · 🔒 secret-scan caught the planted key"; fi
  if grep -q "missed the key" "$1"; then line="${line} · 🔓 secret-scan missed the planted key"; fi
  echo "${line}"
}

# Post the report on launchR pull request RELEASE_PR, or update the comment an earlier run posted there.
comment() {
  : "${RELEASE_PR:?}" "${GITHUB_REPOSITORY:?}" "${RUN_URL:?}"
  [[ "${RELEASE_PR}" =~ ^[0-9]+$ ]] || { echo "::error::release_pr must be a pull request number: ${RELEASE_PR}"; exit 1; }
  gh api "repos/${GITHUB_REPOSITORY}/pulls/${RELEASE_PR}" --jq .number >/dev/null ||
    { echo "::error::#${RELEASE_PR} is not a pull request in ${GITHUB_REPOSITORY}."; exit 1; }
  local body="${WORK}/comment.md" id
  mkdir -p "${WORK}"
  if [ -s "${REPORT}" ]; then
    { cat "${REPORT}"; echo; echo "[The run](${RUN_URL})"; } > "${body}"
  else
    printf '%s\n## Sandbox test\n\n❌ The run stopped before its report: see [the run](%s).\n' "${MARKER}" "${RUN_URL}" > "${body}"
  fi
  id=$(gh api --paginate "repos/${GITHUB_REPOSITORY}/issues/${RELEASE_PR}/comments" \
    --jq ".[] | select(.user.login == \"github-actions[bot]\" and (.body | startswith(\"${MARKER}\"))) | .id" | head -n 1)
  if [ -n "${id}" ]; then
    gh api -X PATCH "repos/${GITHUB_REPOSITORY}/issues/comments/${id}" -F "body=@${body}" --jq .html_url
  else
    gh api -X POST "repos/${GITHUB_REPOSITORY}/issues/${RELEASE_PR}/comments" -F "body=@${body}" --jq .html_url
  fi
}

case "${1:-}" in
  prepare) prepare ;;
  push) push ;;
  pr) pr ;;
  wait) wait_runs ;;
  report) report ;;
  comment) comment ;;
  *) echo "Usage: $0 prepare|push|pr|wait|report|comment" >&2; exit 2 ;;
esac
