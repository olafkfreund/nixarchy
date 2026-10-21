#!/usr/bin/env bash
# The end of a failed build job: which derivation failed, and its real error.
# Usage: failure-digest.sh [logfile]   (default: $RUNNER_TEMP/build.log)
#
# `nix build --keep-going` buries the root failure under hundreds of lines of
# proofs and cascades, so a reader of the last 25 lines of the log saw
# neither the check's name nor its error (#1384). A root is an
# `error: Cannot build '<drv>'` whose Reason is not "N dependenc(y|ies)
# failed"; the others are cascades and are only counted.
#
# Never changes a job's status: it always exits 0.
set -Eeuo pipefail
trap 'echo "failure-digest.sh: could not build the digest (line $LINENO)"; exit 0' ERR

log=${1:-${RUNNER_TEMP:-/tmp}/build.log}
here=$(dirname "$0")
out=$(mktemp)
digest=""

if [ -r "$log" ]; then
  # Captured, then split: a process substitution hides a failing awk (§4).
  rows=$(awk '
    /^error: Cannot build / { drv = $4; gsub(/\x27|\.$/, "", drv); want = 1; next }
    # once per drv: the edge prepare step and build-unless-proven.sh both tee
    # into the same log, so every line can appear twice
    want && /Reason:/ { if (!seen[drv]++) print ($0 ~ /dependenc(y|ies) failed/ ? "C" : "R") "\t" drv; want = 0 }
  ' "$log")
else
  rows=""
fi

roots=()
cascades=0
while IFS=$'\t' read -r kind drv; do
  case $kind in
    R) roots+=("$drv") ;;
    C) cascades=$((cascades + 1)) ;;
  esac
done <<<"$rows"

{
  echo "=== failure digest ==="
  if [ "${#roots[@]}" -eq 0 ]; then
    echo "no failed derivation found in $log"
  fi
  names=()
  for drv in "${roots[@]}"; do
    b=${drv##*/}; b=${b#*-}; name=${b%.drv}
    names+=("$name")
    echo "✗ $name"
    # The cause is at the END of a log (the assertion, the last `error:`), and
    # early noise would fill a first-40 cut, so keep the last 40 matched lines.
    # `|| true`: a drv nix no longer has a log for must not end the digest.
    excerpt=$(nix log "$drv" 2>/dev/null | MAX=100000 "$here/failure-excerpt.sh" | tail -n 40 || true)
    if [ -n "$excerpt" ]; then
      printf '%s\n' "$excerpt" | sed 's/^/    /'
    else
      # A check that prints its own words (no `error`/`FAIL`) still names its cause in the last lines.
      echo "    (no error lines; last lines of the log)"
      { nix log "$drv" 2>/dev/null | tail -n 10 || true; } | sed 's/^/    /'
    fi
  done
  if [ "$cascades" -gt 0 ] && [ "${#roots[@]}" -gt 0 ]; then
    echo "$cascades checks failed only because ${names[*]} failed"
  fi
  digest=${names[*]:-}
  echo "$digest" >"$out.digest"
} >"$out"

cat "$out"
cat "$out" >>"${GITHUB_STEP_SUMMARY:-/dev/null}"
echo "digest=$(tr ' ' ',' <"$out.digest")" >>"${GITHUB_OUTPUT:-/dev/null}"
rm -f "$out" "$out.digest"
exit 0
