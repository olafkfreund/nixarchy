#!/usr/bin/env bash
# Print {"attr": "version", ...} for every nixpkgs package the catalogue
# installs, resolved against the nixpkgs revision flake.lock currently pins.
#
# Run before and after a `nix flake update nixpkgs` and diff the two, and you
# have the only summary of that bump a human actually wants: which apps moved
# and to what. A flake.lock diff says one hash became another hash, which tells
# a reviewer nothing about whether the bump was worth taking.
#
# The attribute list is DERIVED from data/apps.nix rather than written out
# here. A hand-kept list would drift the first time an app was added, and it
# would drift silently -- the report would stop mentioning the new app, which
# reads exactly like "that app did not change".
#
# Resolution goes through the pinned REVISION (github:NixOS/nixpkgs/<rev>)
# rather than through builtins.getFlake on this directory. During the bump the
# working tree has a modified flake.lock, and evaluating a dirty flake is both
# noisier and less predictable than naming the revision the lock already
# records. The rev is the thing being compared, so read it directly.
#
# Packages that fail to evaluate are skipped, not fatal: an app can vanish from
# nixpkgs or move behind a broken flag, and that must not take down the nightly
# bump. Skips go to stderr, counted, so they are visible without corrupting the
# JSON on stdout.
set -euo pipefail

cd "$(dirname "$0")/../.."

# Through root.inputs, NOT through the node literally named "nixpkgs". This
# lock has two nixpkgs nodes: root's is "nixpkgs_2", and the one actually named
# "nixpkgs" belongs to a dependency. Reading the latter is not a crash -- it
# returns a perfectly good revision that simply is not ours, and it does not
# move when `nix flake update nixpkgs` moves the real pin. Written the naive
# way, this script reported the identical version set before and after a
# thirteen-day bump, and the workflow's summary said "No package version
# changed" -- which reads exactly like a correct answer.
node=$(jq -r '.nodes.root.inputs.nixpkgs' flake.lock)
rev=$(jq -r --arg n "$node" '.nodes[$n].locked.rev' flake.lock)
if [ -z "$rev" ] || [ "$rev" = "null" ] || [ "$node" = "null" ]; then
  echo "flake.lock: cannot resolve root's nixpkgs revision (node=$node)" >&2
  exit 1
fi
echo "resolving against nixpkgs ${rev:0:12}" >&2

attrs=$(nix eval --impure --raw --expr '
  let apps = import ./data/apps.nix; in
  builtins.concatStringsSep "\n" (
    builtins.filter (x: x != null)
      (map (n: apps.${n}.attr or null) (builtins.attrNames apps)))')

skipped=0
total=0
{
  echo "{"
  first=1
  while IFS= read -r attr; do
    [ -n "$attr" ] || continue
    total=$((total + 1))
    # --impure so NIXPKGS_ALLOW_UNFREE from the caller is honoured; several
    # catalogue entries are unfree and would otherwise all be "skipped".
    if v=$(nix eval --impure --raw "github:NixOS/nixpkgs/${rev}#${attr}.version" 2>/dev/null); then
      [ "$first" = 1 ] || echo ","
      first=0
      printf '  "%s": "%s"' "$attr" "$v"
    else
      skipped=$((skipped + 1))
      echo "skipped: $attr (does not evaluate)" >&2
    fi
  done <<<"$attrs"
  echo
  echo "}"
}

echo "resolved $((total - skipped)) of $total attrs" >&2
