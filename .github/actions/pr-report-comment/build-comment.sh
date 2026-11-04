#!/usr/bin/env bash
# Builds the pull request's report comment from the parts that pr-report-part saved: for each workflow in the
# config, the latest pull_request run for the pull request's head commit, and that run's pr-report-* artifacts.
# The parts are plain Markdown: they are copied into the comment, never run. Writes the comment to $OUT and the
# outputs `post` (false when the pull request has a newer commit) and `header` to $GITHUB_OUTPUT.
# Needs: gh, jq, perl, unzip; GH_TOKEN with actions: read; CONFIG, PR_NUMBER, HEAD_SHA, OUT. Generic: no
# repository-specific code.
set -euo pipefail

repo="${GITHUB_REPOSITORY}"
work=$(mktemp -d)
max_part=20000     # characters kept from one part
max_comment=60000  # GitHub's limit is 65,536

# Cuts Markdown read from stdin to at most $1 bytes, without leaving a half character (a UTF-8 character is up to four
# bytes) or an open <details> block or code fence: what the cut dropped is closed again, so the rest of the comment
# is not swallowed. Text within the limit passes through unchanged.
cut_markdown() {
  perl -0777 -e '
    my $max = shift; local $/; my $t = <STDIN>;
    if (length($t) > $max) {
      $t = substr($t, 0, $max);
      $t =~ s/(?:[\xC2-\xDF]|[\xE0-\xEF][\x80-\xBF]?|[\xF0-\xF4][\x80-\xBF]{0,2})\z//;
      # A fence closes only with the same character, at least as long, alone on its line (CommonMark).
      my $fence = "";
      for my $line (split /\n/, $t) {
        if ($fence eq "") { $fence = $1 if $line =~ /^ {0,3}(`{3,}|~{3,})/; next; }
        my $c = substr($fence, 0, 1);
        $fence = "" if $line =~ /^ {0,3}(\Q$c\E{3,})\s*$/ && length($1) >= length($fence);
      }
      $t .= "\n$fence\n" if $fence ne "";
      my $open = () = $t =~ /<details\b/g; my $shut = () = $t =~ /<\/details>/g;
      $t .= "\n</details>\n" x ($open - $shut) if $open > $shut;
    }
    print $t;' "$1"
}

header=$(jq -r '.header // "pr-report"' "${CONFIG}")
title=$(jq -r '.title // "CI report"' "${CONFIG}")
report_job=$(jq -r '.report_job // "report"' "${CONFIG}")
echo "header=${header}" >>"${GITHUB_OUTPUT}"

# An older commit's run must not overwrite the report of a newer one.
current=$(gh api "repos/${repo}/pulls/${PR_NUMBER}" --jq .head.sha)
if [ "${current}" != "${HEAD_SHA}" ]; then
  echo "The pull request is now at ${current}, not ${HEAD_SHA}: not posting."
  echo "post=false" >>"${GITHUB_OUTPUT}"
  exit 0
fi

footer=()
states=()
waiting=()
notstarted=()
silent=()
failures=()
summary_jobs=$(jq -r '.summary_jobs // [] | .[]' "${CONFIG}")
mkdir -p "${work}/parts"
while IFS= read -r workflow; do
  # A check is on when its caller file exists. One that's off, or has no pull_request trigger, never reports here.
  caller=".github/workflows/${workflow}"
  if [ ! -f "${caller}" ] || ! grep -Eq '^[[:space:]]*pull_request:' "${caller}"; then
    continue
  fi
  # The newest run for this commit and this pull request: two pull requests can share a commit.
  run=$(gh api "repos/${repo}/actions/workflows/${workflow}/runs?head_sha=${HEAD_SHA}&event=pull_request&per_page=20" \
    --jq "[.workflow_runs[] | select(any(.pull_requests[]; .number == ${PR_NUMBER}))][0] // empty |
      [.id, .status, (.conclusion // \"-\"), .html_url] | @tsv")
  # No run yet. This does not hold the comment at "running": a check can have no run for good (the pull request goes
  # into a branch the caller doesn't list, or the caller's trigger doesn't match), and the comment would never finish.
  # Every started run being done is what ends it. A run that is only late is still caught: GitHub creates a push's runs
  # together, so by the time one run has finished the others are listed, and the next report corrects the comment.
  if [ -z "${run}" ]; then
    notstarted+=("${workflow%.*}")
    continue
  fi
  # No empty fields: read would join two tabs into one ("-" stands for a run with no conclusion yet).
  IFS=$'\t' read -r id status conclusion url <<<"${run}"
  # A run is finished for the report when all its jobs but the report jobs are: its own report job (and this one)
  # may still be running.
  # Each job: its status, conclusion, name, link and the first step that failed ("-" when none).
  # The sixth field is "true" for a report job.
  all_jobs=$(gh api --paginate "repos/${repo}/actions/runs/${id}/jobs" \
    --jq ".jobs[] | [.status, (.conclusion // \"-\"), .name, .html_url,
       ([.steps[]? | select(.conclusion == \"failure\") | .name][0] // \"-\"),
       ((.name | split(\" / \") | last) == \"${report_job}\" | tostring)] | @tsv")
  jobs=$(printf '%s\n' "${all_jobs}" | awk -F '\t' '$6 != "true"' | cut -f 1-5)
  # The report job needs all the others, so it has started only when they are done. Before that, a run may still be
  # about to create its matrix jobs (only the job that builds the matrix is listed), which would look like a success.
  report_started=$(printf '%s\n' "${all_jobs}" | awk -F '\t' '$6 == "true" && ($1 == "in_progress" || $1 == "completed")' | wc -l)
  pending=$(printf '%s\n' "${jobs}" | awk -F '\t' '$1 != "" && $1 != "completed"' | wc -l)
  failed=$(printf '%s\n' "${jobs}" | awk -F '\t' '$2 == "failure" || $2 == "timed_out"' | wc -l)
  cancelled=$(printf '%s\n' "${jobs}" | awk -F '\t' '$2 == "cancelled"' | wc -l)
  # Read from those jobs, not the run's own conclusion: GitHub cancels a report job that waits behind another (they
  # share one concurrency group), which would mark a run whose tests passed as cancelled.
  if [ "${status}" != "completed" ] && { [ "${pending}" -gt 0 ] || [ "${report_started}" -eq 0 ]; }; then
    state="running"
  elif [ "${failed}" -gt 0 ]; then
    state="failure"
  elif [ "${cancelled}" -gt 0 ]; then
    state="cancelled"
  else
    state="success"
  fi
  states+=("${state}")
  # The jobs that failed, with the step they failed at, so the comment says where to look. A summary job
  # ("summary_jobs" in the config) is listed only when it failed on its own: otherwise it repeats its matrix.
  run_failures=()
  summary_failures=()
  while IFS=$'\t' read -r _ job_conclusion job_name job_url job_step; do
    case "${job_conclusion}" in
      failure | timed_out) ;;
      *) continue ;;
    esac
    if [ "${job_step}" = "-" ]; then
      line="[${job_name}](${job_url}) (${workflow%.*}): ${job_conclusion/_/ }"
    else
      line="[${job_name}](${job_url}) (${workflow%.*}): failed at \"${job_step}\""
    fi
    if printf '%s\n' "${summary_jobs}" | grep -qxF -- "${job_name##* / }"; then
      summary_failures+=("${line}")
    else
      run_failures+=("${line}")
    fi
  done <<<"${jobs}"
  if [ "${#run_failures[@]}" -gt 0 ]; then
    failures+=("${run_failures[@]}")
  elif [ "${#summary_failures[@]}" -gt 0 ]; then
    failures+=("${summary_failures[@]}")
  fi
  footer+=("[${workflow%.*}](${url}) (${state})")
  found=0
  while IFS=$'\t' read -r artifact name; do
    [ -z "${artifact}" ] && continue
    # The part's name comes from its artifact name, which pr-report-part checked; check it again here.
    part=${name#pr-report-}
    [[ "${part}" =~ ^[A-Za-z0-9]+-[A-Za-z0-9.-]+$ ]] || continue
    gh api "repos/${repo}/actions/artifacts/${artifact}/zip" >"${work}/part.zip"
    rm -rf "${work}/unzip"
    mkdir "${work}/unzip"
    unzip -qq -o "${work}/part.zip" -d "${work}/unzip"
    file=$(find "${work}/unzip" -type f -name '*.md' | head -n 1)
    [ -z "${file}" ] && continue
    cut_markdown "${max_part}" <"${file}" >"${work}/parts/${part}.md"
    found=1
  done < <(gh api --paginate "repos/${repo}/actions/runs/${id}/artifacts" \
    --jq '.artifacts[] | select(.expired | not) | select(.name | startswith("pr-report-")) | [.id, .name] | @tsv')
  if [ "${state}" = "running" ]; then
    waiting+=("${workflow%.*}")
  elif [ "${found}" = 0 ]; then
    silent+=("${workflow%.*}")
  fi
done < <(jq -r '.workflows[]' "${CONFIG}")

# One headline status for all the runs: a failure first, then anything still running, then a cancelled run.
all=" ${states[*]-} "
if [[ "${all}" =~ \ (failure|timed_out|startup_failure)\  ]]; then
  headline="❌ ${title}: failed"
elif [[ "${all}" =~ \ running\  ]]; then
  headline="⏳ ${title}: running"
elif [[ "${all}" =~ \ cancelled\  ]]; then
  headline="⏹️ ${title}: cancelled"
else
  headline="✅ ${title}: passed"
fi

{
  echo "## ${headline} · \`${HEAD_SHA:0:7}\`"
  echo
  echo "_Each workflow rewrites this comment when it finishes._"
  while IFS=$'\t' read -r key section; do
    echo
    echo "### ${section}"
    echo
    shopt -s nullglob
    parts=("${work}/parts/${key}-"*.md)
    shopt -u nullglob
    if [ "${#parts[@]}" = 0 ]; then
      echo "_Nothing reported yet._"
      continue
    fi
    for part in $(printf '%s\n' "${parts[@]}" | sort); do
      cat "${part}"
      echo
    done
  done < <(jq -r '.sections[] | [.key, .title] | @tsv' "${CONFIG}")
  echo
  echo "---"
  if [ "${#waiting[@]}" -gt 0 ]; then
    echo "⏳ Still running: $(printf '%s, ' "${waiting[@]}" | sed 's/, $//')."
    echo
  fi
  if [ "${#notstarted[@]}" -gt 0 ]; then
    echo "Not started for this commit: $(printf '%s, ' "${notstarted[@]}" | sed 's/, $//')."
    echo
  fi
  if [ "${#silent[@]}" -gt 0 ]; then
    echo "Finished without a report (see the run): $(printf '%s, ' "${silent[@]}" | sed 's/, $//')."
    echo
  fi
  if [ "${#failures[@]}" -gt 0 ]; then
    echo "<details open>"
    echo "<summary><b>Failed jobs (${#failures[@]})</b>: each with the step it failed at</summary>"
    echo
    printf -- '- %s\n' "${failures[@]}"
    echo
    echo "</details>"
    echo
  fi
  if [ "${#footer[@]}" -gt 0 ]; then
    echo "**Runs:** $(printf '%s · ' "${footer[@]}" | sed 's/ · $//')"
  fi
} >"${work}/comment.md"

if [ "$(wc -c <"${work}/comment.md")" -gt "${max_comment}" ]; then
  cut_markdown "${max_comment}" <"${work}/comment.md" >"${OUT}"
  printf '\n\n(Cut short: the full parts are in each job summary.)\n' >>"${OUT}"
else
  cp "${work}/comment.md" "${OUT}"
fi
echo "post=true" >>"${GITHUB_OUTPUT}"
