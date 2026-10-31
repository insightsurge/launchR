#!/bin/bash
# Builds packages for the main sets of choices and runs the gate's fast mode on each.
K="$(cd "$(dirname "$0")/.." && pwd)"; OUT="${1:-$(mktemp -d)}"; MODE="${2:-fast}"; fails=0
run() { name=$1; shift
  rm -rf "$OUT/$name"
  Rscript "$K/cli/kit.R" new "$name" --recommended --title "Sample Tools For Tables" --author "Asha Rao" \
    --email asha@example.com --year 2026 --no-git --out "$OUT/$name" "$@" > /dev/null || { echo "BUILD FAIL $name"; fails=$((fails+1)); return; }
  (cd "$OUT/$name" && Rscript "$K/cli/kit.R" gate "$MODE" > "$OUT/$name.log" 2>&1); code=$?
  echo "$name ($*): exit $code; $(grep -E '^(PASS|FAIL|SKIP)' "$OUT/$name.log" | cut -d' ' -f1 | sort | uniq -c | tr -s ' ' | tr '\n' ' ')"
  grep -E '^FAIL' "$OUT/$name.log" || true
  [ "$code" = 0 ] || fails=$((fails+1))
}
run allprivate --owner sample-org
run allpublic --owner sample-org --public
run noowner
run internalpkg --owner sample-org --internal
run starterpkg --owner sample-org --preset starter
exit $fails
