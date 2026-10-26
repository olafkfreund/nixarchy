#!/usr/bin/env bash
# Which of these checks still need building, and which are already proven?
#
# A nixosTest's output exists ONLY if the test passed -- a failing driver
# fails the derivation and produces nothing. So the presence of a check's
# output in the binary cache is proof that this exact derivation, with these
# exact inputs, built and passed. Not "is unchanged": passed.
#
# That distinction is why this queries the cache rather than diffing
# derivation hashes between two commits. An unchanged drvPath only says the
# inputs are identical, which on a red main would skip a still-failing check
# forever. It is also why nothing here evaluates the base commit: there is no
# base to evaluate, only a question about this one.
#
# `nix path-info --store <cache>` is a narinfo lookup: one HTTP metadata
# round-trip, ~1s, no NAR download. That is the point. `nix build` on an
# already-substitutable path DOWNLOADS it, and on 2026-09-04 that behaviour
# killed four runners at their timeout -- three of them blocked on the
# identical obs-studio path from a stalled cache.nixos.org, every build
# already green. See build.yml's `system-build` timeout comment.
#
# Prints the checks that still need building on stdout, one per line, as
#
#     <name><TAB><drvPath><TAB><outPath>
#
# The drvPath is the point. This script has to evaluate every check to learn
# its output path, and `nix eval` INSTANTIATES -- the derivation is in the store
# by the time the cache lookup happens. Throwing it away meant `nix build` and
# `cachix-push.sh --proof` each evaluated the same attribute again: three full
# evaluations per check, and on checks.options that is three minutes apiece
# (measured 2026-09-17: `nix build .#checks...options` 3m05s against
# `nix build "$drv^*"` 1.3s, both already built). Passing it on makes it one.
#
# A consumer that only wants the name takes the first field; build.yml's
# coverage gate greps the WORKFLOWS for check names, not this output, so the
# second field is invisible to it.
set -uo pipefail

CACHE="${NIXARCHY_CACHE:-https://nixarchy.cachix.org}"
SYSTEM="${NIXARCHY_SYSTEM:-x86_64-linux}"

[ "$#" -gt 0 ] || { echo "usage: already-proven.sh <check>..." >&2; exit 2; }

proven=0
needed=0

# Keep requested evaluator statistics on stderr, separate from the proof rows.
if [ "${NIX_SHOW_STATS:-0}" = 1 ]; then exec 3>&2; else exec 3>/dev/null; fi

# One check: evaluate it, ask the cache, and leave the verdict in $work/<i>.*
# for the loop below to read back IN ORDER. Run in parallel (#1460): a nixpkgs
# bump makes every evaluation cold, and one process per check, one after
# another, spent 18 of omarchy's 45 minutes before it built anything.
check_one() {
  local i=$1 spec=$2 c pair out drv
  # Both spellings, and the fully-qualified one is why: build.yml's coverage
  # gate greps the workflows for `checks.x86_64-linux.<name>` to prove every
  # check is run by something. Replacing `nix build .#checks.x86_64-linux.x`
  # with a script call taking a bare name deleted the text it greps for, and
  # the gate immediately reported four checks as running nowhere -- correctly.
  # So the workflow keeps the greppable form and this strips it.
  c=${spec#".#checks.$SYSTEM."}
  # A check whose outPath will not evaluate is a check that needs building --
  # and the build is where that error belongs, with its stack trace, not here
  # behind a `2>/dev/null`.
  # Both at once: `nix eval` on a derivation gives outPath, and drvPath comes
  # from the same evaluation, so asking for the pair costs nothing extra.
  # Captured, then split: `nix eval --raw` emits no trailing newline, so a
  # `read` fed straight from it returns non-zero having read the data perfectly
  # well -- which sent every check down the failure branch with an empty
  # drvPath, silently, while still printing the right names.
  if ! pair=$(nix eval --raw ".#checks.$SYSTEM.$c" \
    --apply 'd: d.outPath + " " + d.drvPath' 2>&3); then
    echo "  $c: does not evaluate here; leaving it to the build" >"$work/$i.msg"
    # No drvPath to offer, so the build falls back to the attribute.
    printf '%s\t\t\n' "$c" >"$work/$i.row"
    echo needed >"$work/$i.kind"
    return 0
  fi
  read -r out drv <<<"$pair"

  if nix path-info --store "$CACHE" "$out" >/dev/null 2>&1; then
    echo "  $c: already proven ($(basename "$out"))" >"$work/$i.msg"
    : >"$work/$i.row"
    echo proven >"$work/$i.kind"
  else
    : >"$work/$i.msg"
    printf '%s\t%s\t%s\n' "$c" "$drv" "$out" >"$work/$i.row"
    echo needed >"$work/$i.kind"
  fi
}

# The heavy ones alone and first, the rest four at a time (#1460). Measured cold on
# 2026-10-26, one check at a time: generate-config-surface peaks at 11.6 GB and
# config-warnings at 5.0 GB; the median of the other 155 is 0.16 GB and the
# worst four together are 12.8 GB. A hosted runner has 16 GB, and four at once
# beside the heavy ones measured 15 GB of anonymous memory. PROVEN_JOBS overrides
# the four; a worker also waits for PROVEN_MIN_FREE_KB of available memory, so a
# heavy check added later slows this down rather than running the runner out.
jobs=${PROVEN_JOBS:-4}
min_free=${PROVEN_MIN_FREE_KB:-4194304}
solo=" generate-config-surface config-warnings "
work=$(mktemp -d)
# A global, so the trap still names it at exit (AGENTS.md section 5).
trap 'rm -rf "$work"' EXIT
export CACHE SYSTEM work

avail_kb() { awk '/^MemAvailable:/ { print $2 }' /proc/meminfo 2>/dev/null || echo 0; }

i=0
heavy=()
light=()
for spec in "$@"; do
  c=${spec#".#checks.$SYSTEM."}
  if [[ $solo == *" $c "* ]]; then heavy+=("$i $spec"); else light+=("$i $spec"); fi
  i=$((i + 1))
done

# The heavy ones first, alone, one after another: beside them, any light
# check that is not tiny pushed anonymous memory to 15 GB, capped to one or not.
for job in "${heavy[@]}"; do
  check_one ${job}
done

running=0
for job in "${light[@]}"; do
  # Room for one more: fewer than $jobs running, and memory to spare -- or
  # nothing running at all, so a low reading can never stall the loop.
  while [ "$running" -gt 0 ] && { [ "$running" -ge "$jobs" ] || [ "$(avail_kb)" -lt "$min_free" ]; }; do
    wait -n || true
    running=$((running - 1))
  done
  check_one ${job} &
  running=$((running + 1))
done
wait

# Back in argument order, so the rows and messages read as they always did.
# A check whose worker left no verdict is counted as neither, and the floor
# below refuses.
for ((i = 0; i < $#; i++)); do
  [ -f "$work/$i.kind" ] || continue
  cat "$work/$i.msg" >&2
  cat "$work/$i.row"
  case $(cat "$work/$i.kind") in
    proven) proven=$((proven + 1)) ;;
    needed) needed=$((needed + 1)) ;;
  esac
done

echo "proven: $proven   to build: $needed" >&2

# A floor. Every path above increments one counter or the other, so a total
# that does not match the arguments means the loop stopped early -- and an
# empty stdout would then read as "everything is proven", which is the one
# wrong answer this script can give.
if [ "$((proven + needed))" -ne "$#" ]; then
  echo "ERROR: asked about $# checks, accounted for $((proven + needed))." >&2
  echo "Refusing to report anything as proven." >&2
  # Names with an EMPTY drvPath field: the refusal has no evaluation to offer,
  # and a consumer that falls back to the attribute here is doing the safe
  # thing -- building everything from scratch beats reporting a pass.
  for c in "$@"; do printf '%s\t\t\n' "${c#".#checks.$SYSTEM."}"; done
  exit 1
fi
