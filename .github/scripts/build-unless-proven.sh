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

# Check NAMES, never store paths. #742 widened already-proven.sh's output to
# `<name><TAB><drvPath><TAB><outPath>`, and nightly.yml expanded that whole
# row unquoted into this script's arguments -- so one check became three, and
# nix was asked for `checks.x86_64-linux./nix/store/...-nixi.drv`. The error
# it prints for that names three attribute paths and not the caller, which is
# why it read as a flake problem rather than a wrong argument.
for a in "$@"; do
  case $a in
    /nix/store/*)
      echo "::error::$a is a store path, not a check name. A caller has passed" \
        "already-proven.sh's whole row (<name><TAB><drvPath><TAB><outPath>)" \
        "instead of its first field." >&2
      exit 2
      ;;
  esac
done

# stdout is the list that still needs building; stderr is the narration, and
# it is passed through so the log says which checks were skipped and why.
#
# Captured, not piped straight into mapfile: a process substitution hides the
# exit status, so an already-proven.sh that DIED produced an empty list, which
# this script then reported as "every requested check is already proven;
# nothing to build" and exited 0 -- a green run over zero checks. Found by
# tests/proof-push.nix, in a sandbox with no /usr/bin/env. AGENTS.md section 4:
# a check that cannot RUN reads as one that passes.
proven=$("$here/already-proven.sh" "$@") || {
  echo "::error::could not work out which checks are already proven; refusing" \
    "to report a pass having built nothing" >&2
  exit 2
}
# already-proven.sh emits `<name><TAB><drvPath><TAB><outPath>`, so keep all
# three: the names are what the log and cachix-push.sh talk about, the drvPaths
# are what makes the build skip a second evaluation, and the outPaths are what
# lets the push skip a third.
names=()
drvs=()
outs=()
while IFS=$'\t' read -r name drv out; do
  [ -n "$name" ] || continue
  names+=("$name")
  drvs+=("$drv")
  outs+=("$out")
done < <(printf '%s\n' "$proven" | grep . || true)
todo=("${names[@]}")

if [ "${#todo[@]}" -eq 0 ]; then
  echo "every requested check is already proven in the cache; nothing to build"
  exit 0
fi

echo "building: ${todo[*]}"

# In SLICES, so a job that is killed still leaves progress behind (#727).
#
# This used to be one `nix build` over everything followed by one push. A
# partial FAILURE was handled -- --keep-going builds the rest, and the push
# below runs anyway. A partial KILL was not: the script never reaches the push
# at all. On 2026-09-16 three jobs died mid-build (14 min, 17 min, and 45m00s
# at the timeout), every one of them having built checks successfully, and all
# three pushed zero proofs. So each run began exactly where the last began, and
# an eviction that should have been a bad night became a day-long outage that
# took a maintainer rebuilding 40 checks by hand to end.
#
# Slicing makes the step a ratchet: whatever a run proves stays proved.
#
# The cost used to be evaluation: one `nix build` evaluates once, eight evaluate
# eight times. That is gone -- the slices build by drvPath now, which skips
# evaluation entirely (measured 2026-09-17: building checks.options by attribute
# 3m05s, by drvPath 1.3s, both already built). 5 remains the compromise for the
# ratchet itself (a kill loses at most 4 proofs), and PROOF_BATCH still moves it
# from a workflow without another PR.
batch=${PROOF_BATCH:-5}

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
rc=0
for ((i = 0; i < ${#todo[@]}; i += batch)); do
  slice=("${names[@]:i:batch}")
  # By derivation, not by attribute: already-proven.sh has evaluated these
  # already and `nix eval` instantiates, so the drv is in the store and this
  # costs no evaluation. A check whose drvPath is empty -- the refusal path, or
  # one that would not evaluate -- falls back to its attribute, which is the
  # safe direction: it builds rather than silently skipping.
  targets=()
  for j in "${!slice[@]}"; do
    d=${drvs[i + j]}
    if [ -n "$d" ]; then targets+=("$d^*"); else targets+=(".#checks.x86_64-linux.${slice[j]}"); fi
  done
  nix build --keep-going --no-link --print-build-logs "${targets[@]}" || rc=$?

  # The proof, so the next run -- this pull request's re-run, or main after it
  # merges -- skips what just passed (#697). Only checks whose result exists
  # are pushed: under --keep-going a failed check has no output, and
  # cachix-push.sh counts that as skipped rather than failed. Never the
  # verdict: the exit status is the build's.
  # name=outPath, so the push does not evaluate a third time. A slice member
  # with no known outPath is passed as a bare name and evaluated there.
  proofs=()
  for j in "${!slice[@]}"; do
    o=${outs[i + j]}
    if [ -n "$o" ]; then proofs+=("${slice[j]}=$o"); else proofs+=("${slice[j]}"); fi
  done
  "$here/cachix-push.sh" --proof "${proofs[@]}" || true
done
exit "$rc"
