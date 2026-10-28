#!/usr/bin/env bash
# #1479: placement.jq records where each hidden widget sat, and restore_plugins (the code
# screencast-restore runs) puts the whole shell.json back against a stub of the shell's IPC.
# usage: placement-test.sh <placement.jq> <p620-shell.json> <restore-plugins.sh>
set -euo pipefail
jqf=$1 fixture=$2 restore_sh=$3

# What p620's prep hid on 2026-10-28 (disabled.json): three have no bar widget.
disabled='[
 {"id":"io.github.n1c01a5.accent-hold","kinds":["service"]},
 {"id":"io.github.qempexe.altscape","kinds":["service","overlay","bar-widget"]},
 {"id":"io.github.arikisonfire.bar-folder","kinds":["service","bar-widget"]},
 {"id":"promaa.clock","kinds":["bar-widget"]},
 {"id":"shavanced.notification-center","kinds":["bar-widget"]},
 {"id":"yogeshojha.omafob","kinds":["bar-widget"]},
 {"id":"omamail","kinds":["service","bar-widget","panel"]},
 {"id":"io.github.jondkinney.omapop","kinds":["service","bar-widget"]},
 {"id":"io.github.cempack.omaspotify","kinds":["bar-widget"]},
 {"id":"omateams","kinds":["service","bar-widget"]},
 {"id":"vimarchy","kinds":["overlay"]},
 {"id":"rmacy.voxtype-osd","kinds":["panel"]}]'
ids=$(jq -c 'map(.id)' <<<"$disabled")

fail() { echo "FAIL: $*" >&2; exit 1; }
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

# --- placement.jq ------------------------------------------------------------
out=$(jq -c -f "$jqf" --argjson ids "$ids" "$fixture")
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
dup=$(jq '.bar.layout.tray = [{id: "omamail"}]' "$fixture" |
  jq -c -f "$jqf" --argjson ids '["omamail"]')
jq -e '.duplicates == ["omamail"]' <<<"$dup" >/dev/null || fail "duplicate not reported: $dup"

# --- stub of the shell: just enough of putBarWidget, setBarWidget, plugin enable ----
mkdir "$tmp/bin"
cat >"$tmp/bin/omarchy-shell" <<'STUB'
#!/bin/sh
# omarchy-shell shell <fn> <args…>; the state is $STATE
[ "$1" = shell ] && shift
fn=$1 && shift
case "$fn" in
  putBarWidget) # no-op when the id is on the bar already (PluginRegistry.qml:339)
    [ "${FAIL_PUT:-}" = "$1" ] && { echo '"error"'; exit 0; }
    jq --arg id "$1" --argjson p "$2" '
      if [.bar.layout[][] | .id] | index($id) then .
      else .bar.layout[$p.section] |= (.[0:$p.index] + [{id: $id}] + .[$p.index:]) end' "$STATE" >"$STATE.n"
    mv "$STATE.n" "$STATE"; echo '"ok"' ;;
  setBarWidget) # id key json-value {"section":S}
    jq --arg id "$1" --arg k "$2" --argjson v "$3" --argjson p "$4" '
      .bar.layout[$p.section] |= map(if .id == $id then .[$k] = $v else . end)' "$STATE" >"$STATE.n"
    mv "$STATE.n" "$STATE"; echo '"ok"' ;;
  *) echo '"unknown"' ;;
esac
STUB
cat >"$tmp/bin/omarchy" <<'STUB'
#!/bin/sh
# omarchy plugin enable <id> [right]: with a section it moves/appends a fresh widget (setEnabled);
# without, it appends to plugins[].
shift 2
if [ "${2:-}" = right ]; then
  jq --arg id "$1" '.bar.layout.right = ([.bar.layout.right[] | select(.id != $id)] + [{id: $id}])' "$STATE" >"$STATE.n"
else
  jq --arg id "$1" 'if (.plugins | map(.id) | index($id)) then . else .plugins += [{id: $id}] end' "$STATE" >"$STATE.n"
fi
mv "$STATE.n" "$STATE"
STUB
# no /usr/bin/env in the build sandbox
sed -i "1s|.*|#!$BASH|" "$tmp/bin/"*
chmod +x "$tmp/bin/"*
export PATH="$tmp/bin:$PATH" STATE="$tmp/shell.json"
# shellcheck source=/dev/null
source "$restore_sh"

# The shell after prep: the hidden ids gone from the bar and from plugins[].
hide() {
  jq --argjson ids "$ids" '
    .bar.layout |= map_values(map(select(.id as $i | $ids | index($i) | not)))
    | .plugins |= map(select(.id as $i | $ids | index($i) | not))' "$fixture" >"$STATE"
}
# The whole file, with plugins[] sorted by id: the same rule screencast-restore verifies by.
norm='if (.plugins | type) == "array" then .plugins |= sort_by(.id) else . end'
same() { [ "$(jq -S "$norm" "$STATE")" = "$(jq -S "$norm" "$fixture")" ]; }
manifest=$tmp/manifest.json
jq -n --argjson d "$disabled" --argjson p "$out" '{disabled: $d, placement: $p.placement, theme: "x"}' >"$manifest"

# --- restore puts the whole file back, and a second run changes nothing -------------
hide
same && fail "the stub's hidden state equals the snapshot; the check proves nothing"
restore_plugins "$manifest" >"$tmp/log" 2>&1
same || fail "restore_plugins did not give the snapshot back: $(cat "$tmp/log") $(diff <(jq -S "$norm" "$fixture") <(jq -S "$norm" "$STATE"))"
before=$(jq -S . "$STATE")
restore_plugins "$manifest" >/dev/null 2>&1
[ "$(jq -S . "$STATE")" = "$before" ] || fail "a second restore changed the file"

# --- negative control: the old behaviour (enable <id> right for everything) fails -----
hide
jq 'del(.placement)' "$manifest" >"$tmp/legacy.json"
restore_plugins "$tmp/legacy.json" >/dev/null 2>&1
same && fail "the legacy path matched the snapshot; the check cannot tell the old behaviour apart"

# --- a failed putBarWidget leaves the rest of its section for a re-run ----------------
hide
FAIL_PUT=io.github.qempexe.altscape restore_plugins "$manifest" >"$tmp/log" 2>&1
grep -q 'skipped yogeshojha.omafob' "$tmp/log" || fail "later widget in the failed section was not skipped"
same && fail "a failed restore matched the snapshot"
restore_plugins "$manifest" >/dev/null 2>&1
same || fail "a re-run after the failure did not complete the restore"

echo "placement-test: ok"
