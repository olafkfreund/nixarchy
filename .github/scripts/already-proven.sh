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
# already green. See build.yml's `system` timeout comment.
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

for spec in "$@"; do
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
    echo "  $c: does not evaluate here; leaving it to the build" >&2
    # No drvPath to offer, so the build falls back to the attribute.
    printf '%s\t\t\n' "$c"
    needed=$((needed + 1))
    continue
  fi
  read -r out drv <<<"$pair"

  if nix path-info --store "$CACHE" "$out" >/dev/null 2>&1; then
    echo "  $c: already proven ($(basename "$out"))" >&2
    proven=$((proven + 1))
  else
    printf '%s\t%s\t%s\n' "$c" "$drv" "$out"
    needed=$((needed + 1))
  fi
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
