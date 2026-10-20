#!/usr/bin/env bash
# Builds .#omarchy and the generated checks, each separately (omarchy-edge.yml).
set -uo pipefail
# Keep a copy for the Failure digest step (#1384).
exec > >(tee -a "${RUNNER_TEMP:-/tmp}/build.log") 2>&1
failed=""
try() {
  local name=$1
  shift
  echo "::group::$name"
  if "$@"; then echo "::endgroup::"; else
    echo "::endgroup::"
    echo "::error::$name failed"
    failed="$failed $name"
  fi
}
try omarchy nix build .#omarchy --print-build-logs
# Not options: it peaks near 11.5 GB, and beside the quickshell build
# edge needs it lost a 16 GB hosted runner mid-run (#1278). It runs in
# verify, on p620, after the idle wait (CLAUDE.md section 6).
# The list is derived, not kept: capture first, because a failing
# command inside mapfile < <(...) is invisible (CLAUDE.md section 4).
out=$(.github/scripts/generated-checks.sh) || { echo "::error::generated-checks.sh failed"; exit 1; }
mapfile -t targets <<<"$out"
[ "${#targets[@]}" -ge 5 ] || { echo "::error::only ${#targets[@]} generated checks"; exit 1; }
# The same script build.yml's omarchy job uses: slices of 5 with
# --keep-going, cache-proven checks skipped, and it continues past a
# failed slice, so an eval error hides at most its own slice.
try generated-checks .github/scripts/build-unless-proven.sh "${targets[@]}"
echo "failed=${failed# }" >> "$GITHUB_OUTPUT"
[ -z "$failed" ] || { echo "::error::red:$failed"; exit 1; }
