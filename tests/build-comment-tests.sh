#!/usr/bin/env bash
# Tests for .github/actions/pr-report-comment/build-comment.sh, with a fake `gh` that answers from canned files.
# Needs: bash, jq, perl, unzip, zip, iconv. No network, no R. Run: bash tests/build-comment-tests.sh
set -euo pipefail

K="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="${K}/.github/actions/pr-report-comment/build-comment.sh"
ROOT=$(mktemp -d)
trap 'rm -rf "${ROOT}"' EXIT
for tool in jq perl unzip zip iconv; do command -v "${tool}" >/dev/null || { echo "missing tool: ${tool}"; exit 2; }; done

# The fake gh. It answers the five calls build-comment.sh makes, from files in $FAKE:
#   gh api repos/R/pulls/N --jq .head.sha                              -> $FAKE/head_sha (text)
#   gh api repos/R/actions/workflows/WF/runs?... --jq F                -> F applied to $FAKE/runs-WF.json
#   gh api --paginate repos/R/actions/runs/ID/jobs --jq F              -> F applied to $FAKE/jobs-ID.json
#   gh api --paginate repos/R/actions/runs/ID/artifacts --jq F         -> F applied to $FAKE/artifacts-ID.json
#   gh api repos/R/actions/artifacts/AID/zip                           -> the bytes of $FAKE/zip-AID.zip
# The script's own jq filters run for real; a missing JSON file stands for "nothing there".
mkdir -p "${ROOT}/bin"
cat >"${ROOT}/bin/gh" <<'FAKE'
#!/usr/bin/env bash
set -euo pipefail
[ "$1" = api ] || { echo "fake gh: unexpected call: $*" >&2; exit 1; }
shift
path="" filter=""
while [ $# -gt 0 ]; do
  case "$1" in
    --paginate) ;;
    --jq) filter="$2"; shift ;;
    *) path="$1" ;;
  esac
  shift
done
echo "${path}" >>"${FAKE}/calls.log"
path_only="${path%%\?*}"
emit() { # file, empty-json
  if [ -f "$1" ]; then jq -r "${filter}" "$1"; else echo "$2" | jq -r "${filter}"; fi
}
case "${path_only}" in
  repos/*/pulls/*) cat "${FAKE}/head_sha" ;;
  repos/*/actions/workflows/*/runs)
    wf="${path_only#repos/*/actions/workflows/}"; wf="${wf%/runs}"
    emit "${FAKE}/runs-${wf}.json" '{"workflow_runs":[]}' ;;
  repos/*/actions/runs/*/jobs)
    id="${path_only#repos/*/actions/runs/}"; id="${id%/jobs}"
    emit "${FAKE}/jobs-${id}.json" '{"jobs":[]}' ;;
  repos/*/actions/runs/*/artifacts)
    id="${path_only#repos/*/actions/runs/}"; id="${id%/artifacts}"
    emit "${FAKE}/artifacts-${id}.json" '{"artifacts":[]}' ;;
  repos/*/actions/artifacts/*/zip)
    id="${path_only#repos/*/actions/artifacts/}"; id="${id%/zip}"
    cat "${FAKE}/zip-${id}.zip" ;;
  *) echo "fake gh: unexpected path: ${path}" >&2; exit 1 ;;
esac
FAKE
chmod +x "${ROOT}/bin/gh"

PR=7
SHA=abcdef0123456789abcdef0123456789abcdef01
passed=0 failed=0

# ---- case setup helpers (all work in the current case folder: $W, with $FAKE inside it) ----
new_case() { # name
  W="${ROOT}/$1"; FAKE="${W}/fake"; mkdir -p "${FAKE}" "${W}/.github/workflows"
  echo "${SHA}" >"${FAKE}/head_sha"
  : >"${W}/out.env"
  cat >"${W}/config.json" <<'JSON'
{"title": "CI report", "header": "ci-report", "report_job": "report",
 "workflows": ["alpha.yaml", "beta.yaml"],
 "sections": [{"key": "tests", "title": "Tests"}, {"key": "style", "title": "Code style"}]}
JSON
}
caller() { printf 'on:\n  pull_request:\n    branches: [main]\njobs: {}\n' >"${W}/.github/workflows/$1"; }
# run WORKFLOW ID STATUS CONCLUSION [PR_NUMBER]
add_run() {
  jq -n --arg id "$2" --arg st "$3" --arg c "$4" --argjson pr "${5:-${PR}}" --arg url "https://example.test/runs/$2" \
    '{workflow_runs: [{id: ($id|tonumber), status: $st, conclusion: (if $c == "null" then null else $c end),
      html_url: $url, pull_requests: [{number: $pr}]}]}' >"${FAKE}/runs-$1.json"
}
# jobs RUN_ID "status|conclusion|name|failed step" ...   (conclusion "null" = none, step "" = none)
add_jobs() {
  local id="$1"; shift
  printf '%s\n' "$@" | jq -R -s '{jobs: (split("\n") | map(select(. != "") | split("|") |
    {status: .[0], conclusion: (if .[1] == "null" then null else .[1] end), name: .[2],
     html_url: ("https://example.test/job/" + (.[2] | gsub("[^A-Za-z0-9]"; "-"))),
     steps: (if .[3] == "" then [] else [{name: .[3], conclusion: "failure"}] end)}))}' >"${FAKE}/jobs-${id}.json"
}
# artifact RUN_ID ARTIFACT_ID NAME CONTENT_FILE [expired]  (appends to the run's artifact list; zips the content)
add_artifact() {
  local run="$1" aid="$2" name="$3" content="$4" expired="${5:-false}" f="${FAKE}/artifacts-$1.json"
  [ -f "${f}" ] || echo '{"artifacts":[]}' >"${f}"
  jq --argjson id "${aid}" --arg n "${name}" --argjson e "${expired}" \
    '.artifacts += [{id: $id, name: $n, expired: $e}]' "${f}" >"${f}.new" && mv "${f}.new" "${f}"
  local d="${FAKE}/zipsrc-${aid}"; mkdir -p "${d}"; cp "${content}" "${d}/report.md"
  (cd "${d}" && zip -q -r "${FAKE}/zip-${aid}.zip" report.md)
}
text() { local f="${FAKE}/text-$RANDOM.md"; printf '%s\n' "$1" >"${f}"; echo "${f}"; }
# A finished, passing workflow with one part.
simple_ok() { # workflow runid artid partname text
  caller "$1"; add_run "$1" "$2" completed success
  add_jobs "$2" "completed|success|build|" "completed|success|report|"
  add_artifact "$2" "$3" "pr-report-$4" "$(text "$5")"
}
run_script() {
  (cd "${W}" && env PATH="${ROOT}/bin:${PATH}" FAKE="${FAKE}" GITHUB_REPOSITORY=o/r GITHUB_OUTPUT="${W}/out.env" \
    CONFIG="${W}/config.json" PR_NUMBER="${PR}" HEAD_SHA="${SHA}" OUT="${W}/comment.md" GH_TOKEN=x \
    bash "${SCRIPT}" >"${W}/stdout.txt" 2>"${W}/stderr.txt") || { echo "script exited non-zero in ${W}"; cat "${W}/stderr.txt"; exit 1; }
}
C() { cat "${W}/comment.md"; }
has() { C | grep -qF -- "$1" || { echo "  expected in comment: $1"; exit 1; }; }
hasnt() { if C | grep -qF -- "$1"; then echo "  not expected in comment: $1"; exit 1; fi; }
# Line number of the first line containing text.
line_of() { C | grep -nF -- "$1" | head -n 1 | cut -d: -f1; }
before() { local a b; a=$(line_of "$1"); b=$(line_of "$2"); [ -n "${a}" ] && [ -n "${b}" ] && [ "${a}" -lt "${b}" ] || { echo "  expected '$1' before '$2'"; exit 1; }; }
outhas() { grep -qxF -- "$1" "${W}/out.env" || { echo "  expected output: $1 (got: $(tr '\n' ' ' <"${W}/out.env"))"; exit 1; }; }

check() { # case-function, description
  if ( set -e; "$1" ) ; then echo "ok   $2"; passed=$((passed+1)); else echo "FAIL $2"; failed=$((failed+1)); fi
}

# Note: assertions must end the case with `exit 1` (cases run in a subshell under `if`, where set -e is ignored).
# ---- cases ----
c1() {
  new_case c1; echo "ffffffffffffffffffffffffffffffffffffffff" >"${FAKE}/head_sha"
  simple_ok alpha.yaml 100 1 tests-1-unit "unit part"
  run_script
  outhas "post=false"; outhas "header=ci-report"
  [ ! -e "${W}/comment.md" ] || { echo "  comment written"; exit 1; }
  if grep -q "post=true" "${W}/out.env"; then echo "  post=true written"; exit 1; fi
  # It stops before asking about any workflow.
  if grep -q "workflows/" "${FAKE}/calls.log"; then echo "  asked about workflows"; exit 1; fi
}
check c1 "pull request head moved on: post=false, no comment"

c2() {
  new_case c2
  simple_ok alpha.yaml 100 1 style-1-lint "LINT-TEXT"
  simple_ok beta.yaml 200 2 tests-2-integration "INTEGRATION-TEXT"
  add_artifact 200 3 pr-report-tests-1-unit "$(text "UNIT-TEXT")"
  run_script
  outhas "post=true"; outhas "header=ci-report"
  has "## ✅ CI report: all 2 checks passed · \`${SHA:0:7}\`"
  # Sections follow the config (Tests before Code style); parts sort by name inside a section.
  before "### Tests" "### Code style"
  before "UNIT-TEXT" "INTEGRATION-TEXT"; before "INTEGRATION-TEXT" "### Code style"; before "### Code style" "LINT-TEXT"
  has "**Runs:** [alpha](https://example.test/runs/100) · [beta](https://example.test/runs/200)"; hasnt "(success)"
  hasnt "Failed jobs"; hasnt "Still running"; hasnt "Not started"; hasnt "wrote no summary"
}
check c2 "all passed: parts in config order, title and header"

c3() {
  new_case c3
  simple_ok alpha.yaml 100 1 tests-1-unit "UNIT"
  caller beta.yaml; add_run beta.yaml 200 completed failure
  add_jobs 200 "completed|success|lint|" "completed|failure|check (ubuntu)|Run tests" "completed|failure|timed|" "completed|failure|report|Post"
  add_artifact 200 2 pr-report-style-1-lint "$(text "LINT")"
  jq '.hints = {"beta.yaml": "do the beta fix.", "alpha.yaml": "never shown: alpha passed."}' "${W}/config.json" >"${W}/c.new" && mv "${W}/c.new" "${W}/config.json"
  run_script
  has "## ❌ CI report: 1 of 2 checks failed (beta)"
  has "- beta: do the beta fix."; hasnt "never shown"
  has "**Failed jobs**, each with the step it failed at:"
  before "**Failed jobs**" "### Tests"
  has "- [check (ubuntu)](https://example.test/job/check--ubuntu-) (beta): failed at \"Run tests\""
  has "- [timed](https://example.test/job/timed) (beta): failure"
  hasnt "(beta): failed at \"Post\""   # the report job is not listed
  has "[beta](https://example.test/runs/200) (failure)"
}
check c3 "failed run: failed jobs listed with the step; report job left out"

c4() {
  new_case c4
  simple_ok alpha.yaml 100 1 tests-1-unit "UNIT"
  caller beta.yaml    # caller exists, no run for this commit
  run_script
  has "Not started for this commit: beta."
  hasnt "Still running"
  has "## ✅ CI report: all 1 check passed"
  hasnt "[beta]"
  has "[alpha]"
}
check c4 "caller without a run: 'Not started', not counted as running"

c5() {
  new_case c5
  caller alpha.yaml; add_run alpha.yaml 100 in_progress null
  add_jobs 100 "completed|success|build|" "in_progress|null|slow|" "queued|null|report|"
  add_artifact 100 1 pr-report-tests-1-unit "$(text "PARTIAL")"
  run_script
  has "## ⏳ CI report: running"
  has "⏳ Still running: alpha."
  has "[alpha](https://example.test/runs/100) (running)"
  hasnt "wrote no summary"
  has "PARTIAL"   # parts saved so far are still shown
}
check c5 "run in progress: shown as running / still running"

c6() {
  new_case c6
  # beta has a caller with no pull_request trigger; alpha has no caller file at all.
  printf 'on:\n  push:\n    branches: [main]\n# pull_request: in a comment\njobs: {}\n' >"${W}/.github/workflows/beta.yaml"
  run_script
  hasnt "alpha"; hasnt "beta"; hasnt "Not started"
  has "## ✅ CI report: passed"
  has "_Nothing reported yet._"
  hasnt "**Runs:**"
  if grep -q "workflows/" "${FAKE}/calls.log"; then echo "  asked about workflows"; exit 1; fi
}
check c6 "workflows that are off (no caller / no pull_request trigger): not mentioned"

c7() {
  new_case c7
  caller alpha.yaml; add_run alpha.yaml 100 completed success
  add_jobs 100 "completed|success|build|"
  local big="${FAKE}/big.txt"; head -c 25000 /dev/zero | tr '\0' 'x' >"${big}"; echo >>"${big}"
  add_artifact 100 1 pr-report-tests-1-big "${big}"
  run_script
  local run_len; run_len=$(C | grep -o 'x\{100,\}' | head -n 1 | tr -d '\n' | wc -c | tr -d ' ')
  [ "${run_len}" = 20000 ] || { echo "  longest run of x: ${run_len}"; exit 1; }
}
check c7 "a part over 20000 characters is cut to 20000"

c8() {
  new_case c8
  caller alpha.yaml; add_run alpha.yaml 100 completed failure
  add_jobs 100 "completed|failure|matrix / job (a)|Step A" "completed|failure|matrix / all-green|Check all"
  add_artifact 100 1 pr-report-tests-1-unit "$(text "U")"
  jq '.summary_jobs = ["all-green"]' "${W}/config.json" >"${W}/c.new" && mv "${W}/c.new" "${W}/config.json"
  run_script
  has "**Failed jobs**"; has "matrix / job (a)"; hasnt "all-green"
  # Alone, the summary job is listed.
  add_jobs 100 "completed|success|matrix / job (a)|" "completed|failure|matrix / all-green|Check all"
  run_script
  has "**Failed jobs**"; has "matrix / all-green"
}
check c8 "summary job listed only when it failed on its own"

c9() {
  new_case c9
  caller alpha.yaml; add_run alpha.yaml 100 in_progress null
  # Only the report job is still running (name is 'caller / report'): the run counts as finished.
  add_jobs 100 "completed|success|build|" "in_progress|null|ci / report|"
  add_artifact 100 1 pr-report-tests-1-unit "$(text "U")"
  run_script
  has "## ✅ CI report: all 1 check passed"; hasnt "Still running"; has "[alpha](https://example.test/runs/100)"
}
check c9 "only the report job pending: run counts as finished"

c10() {
  new_case c10
  caller alpha.yaml; add_run alpha.yaml 100 completed success
  add_jobs 100 "completed|success|build|"
  add_artifact 100 1 pr-report-tests-1-old "$(text "EXPIRED")" true
  add_artifact 100 2 pr-report-badname "$(text "BADNAME")"
  add_artifact 100 3 other-artifact "$(text "OTHER")"
  run_script
  has "Finished, but wrote no summary (see the run): alpha."
  hasnt "EXPIRED"; hasnt "BADNAME"; hasnt "OTHER"
  has "_Nothing reported yet._"
}
check c10 "expired, badly named and foreign artifacts are ignored: 'Finished without a report'"

c11() {
  new_case c11
  caller alpha.yaml; add_run alpha.yaml 100 completed success 99   # another pull request's run
  run_script
  has "Not started for this commit: alpha."
}
check c11 "a run of another pull request on the same commit is ignored"

c12() {
  new_case c12
  caller alpha.yaml; add_run alpha.yaml 100 completed success
  add_jobs 100 "completed|success|build|"
  local big="${FAKE}/big.txt"; head -c 19000 /dev/zero | tr '\0' 'y' >"${big}"; echo >>"${big}"
  for i in 1 2 3 4; do add_artifact 100 "${i}" "pr-report-tests-${i}-big" "${big}"; done
  run_script
  has "(Cut short: the full parts are in each job summary.)"
  # 60000 characters of comment plus the note.
  local size; size=$(wc -c <"${W}/comment.md" | tr -d ' ')
  [ "${size}" -gt 60000 ] && [ "${size}" -lt 60200 ] || { echo "  size ${size}"; exit 1; }
  outhas "post=true"
}
check c12 "a comment over 60000 characters is cut with a note"

c13() {
  new_case c13
  simple_ok alpha.yaml 100 1 tests-1-unit "U"
  caller beta.yaml; add_run beta.yaml 200 completed cancelled
  add_jobs 200 "completed|cancelled|build|"
  run_script
  has "## ⏹️ CI report: cancelled"; has "[beta](https://example.test/runs/200) (cancelled)"; hasnt "Failed jobs"
}
check c13 "cancelled run: cancelled headline"

c14() {
  new_case c14
  # A failure outranks a running workflow in the headline.
  caller alpha.yaml; add_run alpha.yaml 100 completed failure; add_jobs 100 "completed|failure|build|"
  caller beta.yaml; add_run beta.yaml 200 in_progress null; add_jobs 200 "in_progress|null|slow|"
  run_script
  has "## ❌ CI report: 1 of 2 checks failed (alpha)"; has "Still running: beta."
  has "- [build](https://example.test/job/build) (alpha): failure"
}
check c14 "failure outranks running in the headline; job without a failed step shows its conclusion"

c15() {
  new_case c15
  jq 'del(.title, .header, .report_job)' "${W}/config.json" >"${W}/c.new" && mv "${W}/c.new" "${W}/config.json"
  run_script
  outhas "header=pr-report"; has "## ✅ CI report: passed"
}
check c15 "config defaults: header 'pr-report', title 'CI report'"

c16() {
  new_case c16
  # A run whose matrix jobs are not created yet: only the job that builds the matrix is listed, and the report job
  # has not started. That is not a success.
  caller alpha.yaml; add_run alpha.yaml 100 in_progress null
  add_jobs 100 "completed|success|platforms|" "queued|null|report|"
  run_script
  has "## ⏳ CI report: running"; has "Still running: alpha."; hasnt "(success)"
  # The same run once its matrix has been built and the report job has started.
  add_jobs 100 "completed|success|platforms|" "completed|success|check (a)|" "in_progress|null|report|"
  run_script
  has "## ✅ CI report: all 1 check passed"; hasnt "Still running"
  # No report job listed at all yet: still running.
  add_jobs 100 "completed|success|platforms|"
  run_script
  has "Still running: alpha."
}
check c16 "matrix jobs not created yet (report job not started): running, not success"

c17() {
  new_case c17
  caller alpha.yaml; add_run alpha.yaml 100 completed success
  add_jobs 100 "completed|success|build|"
  # "é" is two bytes and "x" first puts the 20000-byte cut between them; "😀" is four bytes.
  local multi="${FAKE}/multi.txt"
  { printf 'x'; for _ in $(seq 1 15000); do printf 'é'; done; echo; } >"${multi}"
  add_artifact 100 1 pr-report-tests-1-two "${multi}"
  { printf 'xy'; for _ in $(seq 1 8000); do printf '😀'; done; echo; } >"${multi}"
  add_artifact 100 2 pr-report-tests-2-four "${multi}"
  run_script
  iconv -f UTF-8 -t UTF-8 "${W}/comment.md" >/dev/null || { echo "  the comment is not valid UTF-8"; exit 1; }
  has "é"; has "😀"
}
check c17 "a part cut in the middle of a multibyte character stays valid UTF-8"

c18() {
  new_case c18
  caller alpha.yaml; add_run alpha.yaml 100 completed success
  add_jobs 100 "completed|success|build|"
  local part="${FAKE}/open.txt"
  { printf '<details open>\n<summary>Details</summary>\n\n```\n'; head -c 25000 /dev/zero | tr '\0' 'z'; echo; } >"${part}"
  add_artifact 100 1 pr-report-tests-1-open "${part}"
  run_script
  local open shut fences
  open=$(C | grep -c '<details'); shut=$(C | grep -c '</details>'); fences=$(C | grep -c '^```')
  [ "${open}" = "${shut}" ] || { echo "  <details> ${open}, </details> ${shut}"; exit 1; }
  [ $((fences % 2)) = 0 ] || { echo "  an odd number of code fences: ${fences}"; exit 1; }
}
check c18 "a part cut inside <details> and a code block is closed again"

c19() {
  new_case c19
  caller alpha.yaml; add_run alpha.yaml 100 completed success
  add_jobs 100 "completed|success|build|"
  local part="${FAKE}/tilde.txt"
  # A ~~~~ fence with a ``` line inside it: only ~~~~ (or longer) closes it.
  { printf '~~~~\n```\n'; head -c 25000 /dev/zero | tr '\0' 'z'; echo; } >"${part}"
  add_artifact 100 1 pr-report-tests-1-tilde "${part}"
  run_script
  [ "$(C | grep -c '^~~~~$')" = 2 ] || { echo "  expected one opening and one closing ~~~~"; exit 1; }
}
check c19 "a part cut inside a ~~~~ fence is closed with the same fence"

echo
echo "${passed} ok, ${failed} failed"
[ "${failed}" = 0 ]
