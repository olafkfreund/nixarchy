#!/usr/bin/env bash
# Every shipped plugin is in the shot list (#930, plan step 9).
#
# The shot list claims to show all twelve. That claim was already miscounted
# once -- a reviewer read only the montage line and concluded nine -- so it is
# asserted rather than written down.
#
# Same shape as build.yml's "every default plugin has a row in the manual",
# and the same reason: a list naming things that exist elsewhere wants a
# comparison, not discipline (AGENTS.md section 4). The difference is the
# direction that matters here. A plugin ADDED to nixarchy and not to the shot
# list means the next video silently stops being a tour of everything, and
# nothing would say so.
set -euo pipefail

root=${1:-$(cd "$(dirname "$0")/../../.." && pwd)}
home="$root/modules/home.nix"
shots="$root/tests/demo/screencast/shots.nix"

[ -f "$home" ] || { echo "shot-coverage: no modules/home.nix under $root" >&2; exit 1; }
[ -f "$shots" ] || { echo "shot-coverage: no shots.nix under $root" >&2; exit 1; }

# The ids nixarchy actually installs, read the way build.yml reads them so the
# two cannot disagree about what "a default plugin" is.
ids=$(awk '/^      defaultPluginSet = \{/{f=1} f; f && /^      \};/{exit}' "$home" |
  grep -oE 'id = "[^"]+"' | sed 's/id = "//;s/"$//' | sort -u || true)

n=$(printf '%s\n' "$ids" | grep -c . || true)
# A refusal, not a pass. If the awk stops matching -- the block moves, is
# renamed, gains different indentation -- it extracts nothing, and every
# comparison below then succeeds against an empty set. That is the failure
# mode this whole file exists to prevent, so it must not be its own blind spot.
if [ "$n" -lt 5 ]; then
  echo "shot-coverage: found $n plugin ids under 'defaultPluginSet = {' -- the block moved; refusing" >&2
  exit 1
fi

fails=0
for id in $ids; do
  if grep -qF "\"$id\"" "$shots"; then
    echo "  ok      $id"
  else
    echo "  MISSING $id is a shipped plugin and the shot list never names it" >&2
    fails=$((fails + 1))
  fi
done

# And the other direction: a shot naming a plugin nixarchy no longer ships
# would record a beat that opens nothing.
while read -r cited; do
  [ -n "$cited" ] || continue
  printf '%s\n' "$ids" | grep -qxF "$cited" || {
    echo "  STALE   $cited is in the shot list and is not a shipped plugin" >&2
    fails=$((fails + 1))
  }
done < <(grep -oE 'id = "[^"]+"' "$shots" | sed 's/id = "//;s/"$//' | sort -u)

if [ "$fails" -gt 0 ]; then
  echo "shot-coverage: $fails plugin(s) out of step between modules/home.nix and the shot list" >&2
  exit 1
fi
echo "shot-coverage: all $n shipped plugins appear in the shot list"
