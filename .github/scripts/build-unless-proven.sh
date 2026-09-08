#!/usr/bin/env bash
# Build these checks, unless the cache already says they passed.
#
# A drop-in for `nix build .#checks.x86_64-linux.<name> --print-build-logs`,
# which is what every one of these steps used to run directly. The difference
# is one narinfo lookup first: if this exact derivation's output is already in
# the cache, it built and passed, and `nix build` would only DOWNLOAD it.
#
# Downloading is not free and has already cost a day: on 2026-09-04 four
# runners died at their timeout, three blocked on the identical obs-studio
# path from a stalled cache.nixos.org, with every build green. The `system`
# job's timeout comment records it. Nothing here needs the bytes -- the job
# asserts that the check passes, not that this machine holds its output.
#
# See already-proven.sh for why cache presence, and not a derivation-hash
# diff against the base commit, is the sound signal.
set -euo pipefail

here=$(dirname "$0")

# stdout is the list that still needs building; stderr is the narration, and
# it is passed through so the log says which checks were skipped and why.
mapfile -t todo < <("$here/already-proven.sh" "$@")

if [ "${#todo[@]}" -eq 0 ]; then
  echo "every requested check is already proven in the cache; nothing to build"
  exit 0
fi

echo "building: ${todo[*]}"

# --keep-going, because this replaced a step that had it and said why: report
# every failure in one run rather than stopping at the first. That is what a
# job matrix would have been bought for, and losing it silently while moving
# the command into a script is exactly the kind of regression a wrapper makes
# easy. Harmless for the single-check callers.
#
# --no-link for the reason build.yml already records: the generated step runs
# in the same job that builds .#omarchy into `result`, and later steps read
# result/share/omarchy/bin. Without it `nix build` repoints `result` at the
# first check and the shebang check inspects a different tree -- which is how
# it failed once already. Nothing here wants an out-link; the build IS the
# assertion.
nix build --keep-going --no-link --print-build-logs \
  "${todo[@]/#/.#checks.x86_64-linux.}"
