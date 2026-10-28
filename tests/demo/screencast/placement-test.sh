#!/usr/bin/env bash
# #1479: placement.jq records where each hidden widget sat, and replaying those records
# onto the hidden layout gives the original back, once or twice.
# usage: placement-test.sh <placement.jq> <p620-shell.json>
set -euo pipefail
jqf=$1 fixture=$2

# The 12 ids p620's prep hid on 2026-10-28 (disabled.json), bar-kind ones excluded by prep.
ids='["io.github.n1c01a5.accent-hold","io.github.qempexe.altscape","io.github.arikisonfire.bar-folder","promaa.clock","shavanced.notification-center","yogeshojha.omafob","omamail","io.github.jondkinney.omapop","io.github.cempack.omaspotify","omateams","vimarchy","rmacy.voxtype-osd"]'

fail() { echo "FAIL: $*" >&2; exit 1; }

out=$(jq -c -f "$jqf" --argjson ids "$ids" "$fixture")

# Only nine of the twelve have a widget on the bar; accent-hold, vimarchy and voxtype-osd do not.
got=$(jq -r '.placement[] | "\(.section)/\(.index) \(.id)"' <<<"$out" | sort)
want=$(printf '%s\n' \
  'center/3 promaa.clock' \
  'center/5 io.github.cempack.omaspotify' \
  'centerEnd/0 omateams' \
  'left/2 io.github.qempexe.altscape' \
  'left/3 yogeshojha.omafob' \
  'right/1 io.github.arikisonfire.bar-folder' \
  'right/12 shavanced.notification-center' \
  'right/13 io.github.jondkinney.omapop' \
  'right/4 omamail' | sort)
[ "$got" = "$want" ] || fail "records differ:
$got"
jq -e '.duplicates == []' <<<"$out" >/dev/null || fail "unexpected duplicates"
jq -e '.placement[] | select(.id == "yogeshojha.omafob") | .widget.showRing == true' <<<"$out" >/dev/null ||
  fail "omafob lost showRing"

# A second instance of a hidden id is reported.
dup=$(jq '.bar.layout.tray = [{id: "omamail"}]' "$fixture" |
  jq -c -f "$jqf" --argjson ids '["omamail"]')
jq -e '.duplicates == ["omamail"]' <<<"$dup" >/dev/null || fail "duplicate not reported: $dup"

# Model of restore: putBarWidget inserts at index unless the id is already on the bar,
# setBarWidget sets each key. Records are applied in [section, index] order.
replay='
  def onbar($id): [.[][] | .id] | index($id) != null;
  . as $start
  | reduce ($rec.placement | sort_by([.section, .index])[]) as $r ($start;
      if onbar($r.id) then .
      else .[$r.section] = (.[$r.section] | .[0:$r.index] + [{id: $r.id}] + .[$r.index:])
           | .[$r.section] |= map(if .id == $r.id then . + $r.widget else . end)
      end)'
hidden=$(jq -c --argjson ids "$ids" '.bar.layout | map_values(map(select(.id as $i | $ids | index($i) | not)))' "$fixture")
orig=$(jq -cS '.bar.layout' "$fixture")
once=$(jq -c --argjson rec "$out" "$replay" <<<"$hidden")
twice=$(jq -c --argjson rec "$out" "$replay" <<<"$once")
[ "$(jq -cS . <<<"$once")" = "$orig" ] || fail "replay does not give the original layout"
[ "$(jq -cS . <<<"$twice")" = "$orig" ] || fail "a second replay changed the layout"

# A manifest from before #1479 has no placement key: restore takes the legacy path.
jq -e 'has("placement") | not' <<<'{"disabled":[],"theme":"x"}' >/dev/null || fail "legacy not detected"
jq -e 'has("placement")' <<<'{"disabled":[],"placement":[],"theme":"x"}' >/dev/null || fail "placement not detected"
echo "placement-test: ok"
