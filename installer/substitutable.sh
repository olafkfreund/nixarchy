#!/usr/bin/env bash
# What a network install would have to BUILD, answered before anything is
# formatted.
#
# The network image (#483) is ~1.5 GB instead of 6-10 because it fetches the
# closure instead of carrying it. That is only honest for a closure the caches
# actually hold, and a user's is not the reference's:
#
#   - cache.nixos.org does not build UNFREE packages at all. vscode, zoom,
#     cursor, discord and every IDE with a licence are absent from it by
#     policy, not by accident.
#   - nixarchy.cachix.org holds this project's closure, not a user's app
#     selection beyond what nixpkgs already covers.
#   - anything built on the machine -- an overlay, a patched package, a local
#     flake -- is in no cache anywhere by definition.
#
# Discovering that after the disk is wiped is the failure this exists to
# prevent: an installer that has partitioned a disk and then cannot fill it.
#
# ---------------------------------------------------------------------------
# Why this asks the local store rather than the caches
#
# The obvious implementation is to ask each cache whether it has each path. It
# does not work, and both reasons are worth writing down.
#
# `nix path-info --store https://cache.nixos.org a b c` returns NOTHING when
# any one of the paths is missing -- measured, not assumed. So the batch form
# cannot report which are absent, which is the only question being asked.
#
# One HTTP request per path degrades gracefully and is unusable: a desktop
# closure here is 5,463 paths.
#
# The local store already knows. A path substituted from a cache carries that
# cache's SIGNATURE; a path built here has none and is marked `ultimate`. So
# "no cache can supply this" is a local query over the closure -- 5,463 paths
# in 0.6 seconds, no network, and correct while offline.
#
# ---------------------------------------------------------------------------
# Three classes, because "unsigned" alone would cry wolf
#
# Of 1,186 unsigned paths in a real desktop closure, most are text: unit files,
# udev rules, /etc fragments. NixOS assembles those locally on every machine
# and they cost seconds. Reporting them as "must build" would bury the six
# entries that matter under a thousand that do not.
#
#   fixed-output   has `ca`, so its hash is known: re-downloadable from
#                  upstream. Costs bandwidth, not a compiler.
#   small          under the size floor: text derivations, assembled locally
#                  on any machine in seconds.
#   must build     everything else. This is the answer.
#
# On the machine this was written on: 145 paths over 1 MB, 6 of them
# fixed-output, leaving 139 paths and 19.1 GB that a target would have to
# compile -- lmstudio, vscode, zoom, cursor. Every one of them unfree.

set -euo pipefail

# 1 MB. Chosen because it is the gap in the measured distribution rather than a
# round number that felt right: unit files and /etc fragments are kilobytes,
# real packages are tens of megabytes and up. A path between the two is rare
# and cheap either way.
# Exported, not just assigned: the python below reads it from the environment,
# and a plain shell variable is invisible there -- it would raise KeyError
# rather than fall back. shellcheck caught this as "FLOOR appears unused".
export FLOOR=${NIXARCHY_SUBSTITUTABLE_FLOOR:-1000000}

usage() {
  echo "Usage: nixarchy-substitutable <store-path>"
  echo "  Reports what a machine without this store would have to build."
  echo
  echo "  Exit 0: everything can be fetched."
  echo "  Exit 1: something would have to be built -- listed, largest first."
  echo "  Exit 2: the question could not be answered."
}

case "${1:-}" in
  "" | -h | --help) usage; [ -z "${1:-}" ] && exit 2 || exit 0 ;;
esac

target=$1

# The tolerance rule: a probe that cannot read must not invent a verdict.
# Refusing to answer is exit 2, which the caller shows as "unknown" -- never as
# "nothing to build", which is the answer that gets a disk wiped.
if ! info=$(nix path-info --json --recursive "$target" 2>/dev/null); then
  echo "nixarchy-substitutable: cannot read the closure of $target" >&2
  echo "  Nothing was concluded. Do not read this as 'it can all be fetched'." >&2
  exit 2
fi

printf '%s' "$info" | python3 -c '
import json, sys, os

floor = int(os.environ["FLOOR"])
raw = json.load(sys.stdin)
# nix has printed both shapes across versions: an object keyed by path, and a
# list of records carrying "path". Accept either rather than pinning a version.
items = raw.items() if isinstance(raw, dict) else [(r["path"], r) for r in raw]

total = 0
build = []
for path, meta in items:
    total += 1
    if meta.get("signatures"):
        continue                      # some cache vouched for it
    if meta.get("ca"):
        continue                      # fixed output: re-downloadable
    size = meta.get("narSize") or 0
    if size < floor:
        continue                      # assembled locally on any machine
    build.append((size, path))

# A closure this small is not a desktop, and answering "nothing to build" from
# it would be answering a question that was never asked.
if total < 100:
    print(f"only {total} paths in that closure, which cannot be a system.", file=sys.stderr)
    print("Refusing rather than reporting on it.", file=sys.stderr)
    sys.exit(2)

build.sort(reverse=True)
gb = sum(s for s, _ in build) / 1e9
print(f"{total} paths in the closure")

if not build:
    print("every one of them can be fetched from a cache")
    sys.exit(0)

print()
print(f"{len(build)} would have to be BUILT on the target ({gb:.1f} GB):")
for size, path in build[:12]:
    print(f"  {size/1e6:8.0f} MB  {path.split("-", 1)[-1]}")
if len(build) > 12:
    print(f"  ... and {len(build) - 12} more")
sys.exit(1)
'
