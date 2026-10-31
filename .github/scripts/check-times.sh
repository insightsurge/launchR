#!/usr/bin/env bash
# The R CMD check times for the pull request's CI report (R-CMD-check.yaml). Plain bash, so it runs on every runner
# (Windows included) and in the summary job, which has no R.
#
#   check-times.sh note    In each check job, after R CMD check: writes one line (platform, result, tests' elapsed
#                          seconds, whole check's seconds, the limit) to OUT, and fails when the tests take longer
#                          than LIMIT_SECONDS on the job that sets it. Environment: PLATFORM, STATUS (the job's
#                          status so far), CHECK_START (epoch seconds before the check), LIMIT_SECONDS (empty for no
#                          limit), OUT.
#   check-times.sh report  In the summary job: turns the lines in DIR into the report part OUT. Environment: DIR,
#                          RESULT (the matrix's result), R_STEPS ("false" for a documentation-only change), OUT.
#
# R CMD check prints the tests' time in 00check.log as "[CPU/elapsed]" ("265s/129s", or "17m/11m" from 10 minutes),
# or as "[elapsed]" on Windows ("122s"), and only from 10 s (_R_CHECK_TIMINGS_, which --as-cran sets).
set -euo pipefail

minutes() {
  awk -v s="$1" 'BEGIN { printf "%.1f min", s / 60 }'
}

note() {
  local check log line stamp tests
  check=$(($(date +%s) - CHECK_START))
  log=$(ls check/*.Rcheck/00check.log 2>/dev/null | head -n 1 || true)
  line=$(grep -m 1 "Running.*testthat\.R" "${log:-/dev/null}" 2>/dev/null || true)
  stamp=$(printf '%s' "${line}" | sed -n 's/.*\[\([0-9.]*[sm]\/\)\{0,1\}\([0-9.]*\)\([sm]\)\].*/\2 \3/p')
  if [ -n "${stamp}" ]; then
    tests=$(printf '%s' "${stamp}" | awk '{ print ($2 == "m") ? $1 * 60 : $1 }')
  elif [ -n "${line}" ]; then
    tests="under10"
  else
    tests="none"
  fi
  printf '%s\t%s\t%s\t%s\t%s\n' "${PLATFORM}" "${STATUS}" "${tests}" "${check}" "${LIMIT_SECONDS:-}" >"${OUT}"
  echo "Tests: ${tests} s elapsed; whole check: ${check} s."
  # The limit counts only when the check itself passed: a failed check has its own error.
  if [ -n "${LIMIT_SECONDS:-}" ] && [ "${STATUS}" = "success" ]; then
    if [ "${tests}" = "none" ]; then
      echo "::error::00check.log has no \"Running 'testthat.R'\" line: R CMD check did not run the tests."
      exit 1
    fi
    if [ "${tests}" != "under10" ] && awk -v t="${tests}" -v l="${LIMIT_SECONDS}" 'BEGIN { exit !(t > l) }'; then
      echo "::error::The tests took ${tests} s, over the ${LIMIT_SECONDS} s limit. Move detailed tests of an example app to a -extended.R file (tests/README.md) or make them faster."
      exit 1
    fi
  fi
}

report() {
  if [ "${R_STEPS:-}" = "false" ]; then
    echo "⏭️ **R CMD check (as CRAN):** not run: this pull request changes only documentation." >"${OUT}"
    return
  fi
  local total=0 passed=0 headline_time="" rows=() file platform status tests check limit icon shown
  for file in $(ls "${DIR}"/check-time-*.txt 2>/dev/null | sort); do
    IFS=$'\t' read -r platform status tests check limit <"${file}"
    total=$((total + 1))
    case "${status}" in
      success) icon="✅"; passed=$((passed + 1)) ;;
      cancelled) icon="⏹️" ;;
      *) icon="❌" ;;
    esac
    case "${tests}" in
      under10) shown="under 0.2 min" ;;
      none) shown="not run" ;;
      *) shown=$(minutes "${tests}") ;;
    esac
    rows+=("| ${platform} | ${icon} | ${shown} | $(minutes "${check}") |")
    if [ -n "${limit}" ]; then
      headline_time=" · tests ${shown} on ${platform} (limit $(minutes "${limit}"))"
    fi
  done
  local mark="❌"
  [ "${RESULT}" = "success" ] && mark="✅"
  [ "${RESULT}" = "cancelled" ] && mark="⏹️"
  {
    if [ "${total}" -eq 0 ]; then
      echo "${mark} **R CMD check (as CRAN):** no platform reported its times (see the run)"
      return
    fi
    echo "${mark} **R CMD check (as CRAN):** ${passed} of ${total} platforms passed${headline_time}"
    echo
    echo "<details>"
    echo "<summary>Time per platform (the tests, and the whole check)</summary>"
    echo
    echo "| Platform | Result | Tests | Whole check |"
    echo "| :--- | :---: | ---: | ---: |"
    printf '%s\n' "${rows[@]}"
    echo
    echo "</details>"
  } >"${OUT}"
}

case "${1:-}" in
  note) note ;;
  report) report ;;
  *)
    echo "Usage: check-times.sh note|report" >&2
    exit 2
    ;;
esac
