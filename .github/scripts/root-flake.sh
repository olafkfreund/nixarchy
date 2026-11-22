#!/usr/bin/env bash
# Roots this flake's source and every input for the rest of a self-hosted job,
# so the host's auto-GC (min-free) cannot collect them mid-build (#1909).
#
#   root-flake.sh <dir>     roots under <dir>; run it from the checkout
#
# Why: CLAUDE.md section 4, "A path in the cache is not a path that stays there".
set -euo pipefail

dir=${1:?usage: root-flake.sh <dir>}
die() { echo "root-flake: $*" >&2; exit 1; }
mkdir -p "$dir"

attempt() {
  local out list n=0 p bad=() roots
  out=$(nix flake archive --json .) || die "nix flake archive failed"
  jq -e '.path | strings' <<<"$out" >/dev/null || die "the archive names no source path"
  # Only input nodes are walked, so an input *named* path is not read as one.
  list=$(jq -r '[recurse(.inputs[]?) | .path? | strings | select(startswith("/nix/store/"))] | unique | .[]' <<<"$out") ||
    die "could not read the archive's paths"
  local -a paths
  mapfile -t paths <<<"$list"
  [ -n "$list" ] || paths=()
  [ "${#paths[@]}" -ge 2 ] || die "the archive names ${#paths[@]} path(s); a flake with inputs names more"

  rm -rf "${dir:?}"/* 2>/dev/null || true
  for p in "${paths[@]}"; do
    n=$((n + 1))
    nix-store --add-root "$dir/$n" --realise "$p" >/dev/null
  done

  # A GC already running can take a path between the archive and its root, and
  # the root then dangles with status 0, so check what the daemon sees.
  roots=$(nix-store --gc --print-roots) || die "nix-store --gc --print-roots failed"
  n=0
  for p in "${paths[@]}"; do
    n=$((n + 1))
    if ! nix-store --check-validity "$p" 2>/dev/null; then
      bad+=("$p (no longer valid)")
    elif ! grep -qxF -- "\"$dir/$n\" -> $p" <<<"$roots"; then
      bad+=("$p (not rooted at $dir/$n)")
    fi
  done
  if [ "${#bad[@]}" -gt 0 ]; then
    printf '%s\n' "${bad[@]}" >"$dir.bad"
    return 1
  fi
  echo "root-flake: rooted ${#paths[@]} paths under $dir"
}

for try in 1 2 3; do
  if attempt; then
    rm -f "$dir.bad"
    exit 0
  fi
  echo "root-flake: attempt $try left $(wc -l <"$dir.bad") path(s) unrooted, first:" >&2
  head -n 5 "$dir.bad" | sed 's/^/  /' >&2
done
die "gave up after 3 attempts; $(wc -l <"$dir.bad") path(s) unrooted, first: $(head -n 1 "$dir.bad")"
