#!/bin/bash
# Builds packages for the main sets of choices and runs the gate's fast mode on each.
K="$(cd "$(dirname "$0")/.." && pwd)"; OUT="${1:-$(mktemp -d)}"; MODE="${2:-fast}"; fails=0
run() { name=$1; shift
  rm -rf "$OUT/$name"
  Rscript "$K/cli/launchr.R" new "$name" --yes --title "Sample Tools For Tables" --author "Asha Rao" \
    --email asha@example.com --year 2026 --no-git --path "$OUT/$name" "$@" > /dev/null || { echo "BUILD FAIL $name"; fails=$((fails+1)); return; }
  (cd "$OUT/$name" && Rscript "$K/cli/launchr.R" gate "$MODE" > "$OUT/$name.log" 2>&1); code=$?
  echo "$name ($*): exit $code; $(grep -E '^(PASS|FAIL|SKIP) ' "$OUT/$name.log" | cut -d' ' -f1 | sort | uniq -c | tr -s ' ' | tr '\n' ' ')"
  grep -E '^FAIL' "$OUT/$name.log" || true
  [ "$code" = 0 ] || fails=$((fails+1))
}
run allprivate --owner sample-org
run allpublic --owner sample-org --public
run publicstarter --owner sample-org --public --preset starter
run internalpkg --owner sample-org --internal
run starterpkg --owner sample-org --preset starter
# Every badge, so the spelling check sees each badge's words.
run allbadges --owner sample-org --public --badges check,lifecycle,codecov,cran,downloads,universe,launchr
exit $fails
