#!/usr/bin/env bash
# What one commit's allowlist costs in nixarchy.cachix.org, and a refusal when
# it outgrows its share of the free tier's 5 GB (#697).
#
#   cache-budget.sh [installable...]     default: every cache-allowlist.sh entry
#
# Cost is the UNION of the entries' closures, minus every path an upstream
# cache already serves -- Cachix does not store those -- summed by NAR size.
# A union, because the entries share most of their closures (both toplevels,
# all five KVM runners' QEMU) and adding them up per entry would count those
# several times over.
#
# 2 GB per commit, not 5: omarchy alone is a new 124 MiB path on every commit
# (it depends on the flake's rev, #212), so the cache always holds a few
# commits at once until the older ones age out. See spec/ for the arithmetic.
set -uo pipefail

here=$(dirname "$0")
budget_mib=${CACHE_BUDGET_MIB:-2048}
upstreams=${UPSTREAM_CACHES:-https://cache.nixos.org https://hyprland.cachix.org}
jobs=${LOOKUP_JOBS:-16}

if [ $# -gt 0 ]; then
  entries=("$@")
else
  mapfile -t entries < <("$here/cache-allowlist.sh") || true
fi
[ "${#entries[@]}" -gt 0 ] || { echo "::error::no allowlist entries to measure" >&2; exit 2; }

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

# Realise each entry (a substitution on a warm store) and collect its closure,
# remembering which entries each path came from so a failure can name them.
: >"$work/paths.tsv"
for e in "${entries[@]}"; do
  if ! nix build --no-link "$e" >"$work/build.log" 2>&1; then
    echo "::error::$e does not build, so its cost cannot be measured" >&2
    tail -5 "$work/build.log" >&2
    exit 2
  fi
  nix path-info -r --json "$e" 2>/dev/null |
    jq -r --arg e "$e" 'to_entries[] | [.key, (.value.narSize | tostring), $e] | @tsv' \
      >>"$work/paths.tsv"
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
