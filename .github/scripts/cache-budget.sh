#!/usr/bin/env bash
# What one commit's allowlist costs in nixarchy.cachix.org, and a refusal when
# it outgrows its share of the free tier's 5 GB (#697).
#
#   cache-budget.sh [installable...]     default: every cache-allowlist.sh entry
#
# Cost is the UNION of the entries' closures, minus every path cache.nixos.org
# already serves -- `cachix push` skips those -- summed by NAR size. Only that
# one: hyprland.cachix.org's paths ARE pushed and stored, nine hyprwm builds
# and 75.3 MiB of the shipped Hyprland's closure on 2026-10-12 (#1250).
# A union, because the entries share most of their closures (both toplevels,
# all five KVM runners' QEMU) and adding them up per entry would count those
# several times over.
#
# 2.5 GB per commit, not 5: the cache must hold this commit and the one before.
# They share the box images, pinned by digest (508 MiB), so the worst case, a
# nixpkgs bump, costs 2 x 2560 - 508 = 4612 MiB of 5120. Pushes come from main
# and from the newest dated bump branches (minus commit-specific paths, #1461);
# the free tier evicts by last download, so an unmerged bump's paths go first.
# See spec/2026-10-10-1231-cache-budget-headroom.md.
set -uo pipefail

here=$(dirname "$0")
budget_mib=${CACHE_BUDGET_MIB:-2560}
upstreams=${UPSTREAM_CACHES:-https://cache.nixos.org}
jobs=${LOOKUP_JOBS:-16}

if [ $# -gt 0 ]; then
  entries=("$@")
else
  mapfile -t entries < <("$here/cache-allowlist.sh") || true
fi
[ "${#entries[@]}" -gt 0 ] || { echo "::error::no allowlist entries to measure" >&2; exit 2; }

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

# Realise every entry in ONE nix invocation: one evaluation shares the
# nixpkgs and flake loading that a build per entry repeats (#1461). `--json`
# lists the results in argument order. If the batch fails, or does not map one
# out path to each entry, fall back to one build per entry, so the error names
# the entry that broke.
# True when no argument is empty. A loop, not `printf | grep -q`: under
# pipefail that can read a match as a failure (tests/grep-q-pipefail).
all_set() { local o; for o in "$@"; do [ -n "$o" ] || return 1; done; }

outs=()
if batch=$(nix build --no-link --json "${entries[@]}" 2>"$work/batch.log") &&
  # Every output, space-joined: a multi-output package (jq) has no `out`.
  mapfile -t outs < <(jq -r '.[] | [.outputs[]] | join(" ")' <<<"$batch") &&
  [ "${#outs[@]}" -eq "${#entries[@]}" ] && all_set "${outs[@]}"; then
  :
else
  outs=()
  for e in "${entries[@]}"; do
    if ! nix build --no-link "$e" >"$work/build.log" 2>&1; then
      echo "::error::$e does not build, so its cost cannot be measured" >&2
      tail -5 "$work/build.log" >&2
      exit 2
    fi
    outs+=("$e")
  done
fi

# Collect each entry's closure, remembering which entries each path came from
# so a failure can name them. Reading from the out path means no re-evaluation.
: >"$work/paths.tsv"
for i in "${!entries[@]}"; do
  e=${entries[$i]}
  # pipefail is what makes the || below see a failed nix: jq exits 0 on empty input.
  # Word-split on purpose: one entry may name several outputs.
  set -f # no globbing of the split words
  # shellcheck disable=SC2086
  nix path-info -r --json ${outs[$i]} 2>/dev/null |
    jq -r --arg e "$e" 'to_entries[] | [.key, (.value.narSize | tostring), $e] | @tsv' \
      >>"$work/paths.tsv" ||
    { echo "::error::could not read the closure of $e, so its cost cannot be measured" >&2; exit 2; }
  set +f
done

# One lookup per distinct path, in parallel: the union of the allowlist is
# around 3,000 paths and nearly all of them are served upstream.
cut -f1 "$work/paths.tsv" | sort -u >"$work/unique"
lookup() {
  local p=$1 h u
  h=$(basename "$p" | cut -d- -f1)
  for u in ${CACHE_BUDGET_UPSTREAMS:?}; do
    [ "$(curl -s -o /dev/null -w '%{http_code}' "$u/$h.narinfo")" = 200 ] && return 0
  done
  printf '%s\n' "$p"
}
export -f lookup
# shellcheck disable=SC2016 # $1 is expanded by the inner bash, on purpose
CACHE_BUDGET_UPSTREAMS=$upstreams xargs -r -P "$jobs" -I{} bash -c 'lookup "$1"' _ {} <"$work/unique" |
  sort >"$work/ours"

total_paths=$(wc -l <"$work/unique")
[ "$total_paths" -gt 0 ] || { echo "::error::the allowlist closures came back empty" >&2; exit 2; }

# Our paths, with size and every entry that pulls each one in.
awk -F'\t' 'NR == FNR { ours[$1] = 1; next }
  ($1 in ours) { size[$1] = $2; by[$1] = (by[$1] == "" ? $3 : by[$1] ", " $3) }
  END { for (p in size) printf "%s\t%s\t%s\n", size[p], p, by[p] }' \
  "$work/ours" "$work/paths.tsv" | sort -rn >"$work/cost.tsv"

bytes=$(awk -F'\t' '{ s += $1 } END { printf "%d", s }' "$work/cost.tsv")
mib=$((bytes / 1048576))
ours_paths=$(wc -l <"$work/cost.tsv")

echo "allowlist: ${#entries[@]} entries, $total_paths paths in their closures"
echo "in nixarchy.cachix.org: $ours_paths paths, $mib MiB of a $budget_mib MiB budget"
echo "largest:"
head -10 "$work/cost.tsv" |
  awk -F'\t' '{ printf "  %8.1f MiB  %s\n             from %s\n", $1 / 1048576, $2, $3 }'

if [ "$bytes" -gt $((budget_mib * 1048576)) ]; then
  echo "::error::the allowlist costs $mib MiB, over its $budget_mib MiB budget." >&2
  echo "  The entries pulling in the most, above, are where it grew. Either take" >&2
  echo "  one off .github/scripts/cache-allowlist.sh, or raise CACHE_BUDGET_MIB in" >&2
  echo "  the same change and say why -- the free tier is 5 GB in total." >&2
  exit 1
fi
