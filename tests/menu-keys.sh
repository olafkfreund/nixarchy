#!/usr/bin/env bash
# shellcheck disable=SC2015 # pass and fail always succeed, so A && B || C is if-else here
# #1305: the real Menu.qml in a headless Quickshell. Right must not run a row,
# and a request displaced by the next one must release its caller.
# #1339: the card is as wide as its widest label, up to a cap, and a filter
# does not shrink it.
# Usage: menu-keys.sh <built share/omarchy> <harness shell.qml>
# Needs on PATH: qs, bash, sh, perl, sed, coreutils. TEST_BASH is the stubs' shebang.
set -uo pipefail

tree=$1
work=$PWD
shell_dir=$work/shell
marks=$work/marks
mkdir -p "$marks" "$work/fake/default/omarchy" "$work/stub" "$work/home"
export HOME=$work/home

die() { echo "menu-keys: $*" >&2; cat "$work/qs.log" 2>/dev/null >&2; exit 2; }
for tool in qs bash sh perl sed touch mktemp; do command -v "$tool" >/dev/null || die "$tool is not on PATH"; done
[[ -x $tree/bin/omarchy-menu-select && -x $tree/bin/omarchy-menu-input ]] || die "the built menu scripts are missing under $tree/bin"

# Replace text that must occur exactly once, or stop: a harness edit that
# silently matched nothing would test the shipped window, not this one.
replace_once() {
  local file=$1 anchor=$2 replacement=$3 text rest
  text=$(<"$file")
  rest=${text#*"$anchor"}
  [[ $rest != "$text" && $rest != *"$anchor"* ]] || die "harness anchor not found exactly once in $file: ${anchor%%$'\n'*}"
  printf '%s\n' "${text%%"$anchor"*}$replacement$rest" > "$file"
}

# The menu's own window is a Wayland layer surface, and offscreen Quickshell
# has "No PanelWindow backend loaded". A plain window runs the same handler.
cp -rL "$tree/shell" "$shell_dir"
chmod -R u+w "$shell_dir"
replace_once "$shell_dir/plugins/menu/Menu.qml" '  PanelWindow {
    id: panel
    visible: root.opened && root.rowsLoaded
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "omarchy-menu"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    exclusionMode: ExclusionMode.Ignore' '  FloatingWindow {
    id: panel
    implicitWidth: 1920
    implicitHeight: 1080
    visible: root.opened && root.rowsLoaded
    color: "transparent"'
cp "$2" "$shell_dir/shell.qml"

long_label='the quick brown fox jumps over the lazy dog while the five boxing wizards jump quickly and pack my box with five dozen liquor jugs so that this label is far wider than any card the menu would draw by default'
# The fixture menu. Its actions only touch markers: never load the shipped
# menu here, whose rows lock, suspend and power off (tests/AGENTS.md).
printf '%s\n' '{' \
  '  "probe": {"label": "Probe"},' \
  "  \"probe.act\": {\"label\": \"Act\", \"action\": \"touch $marks/act\"}," \
  '  "probe.link": {"label": "Link", "target": "probe.sub"},' \
  '  "probe.sub": {"label": "Sub"},' \
  "  \"probe.sub.x\": {\"label\": \"X\", \"action\": \"touch $marks/x\"}," \
  "  \"probe.d\": {\"label\": \"D\", \"action\": \"touch $marks/d\"}," \
  '  "wide": {"label": "Wide"},' \
  "  \"wide.long\": {\"label\": \"$long_label\", \"action\": \"touch $marks/long\"}" \
  '}' > "$work/fake/default/omarchy/omarchy-menu.jsonc"

# The menu scripts summon through omarchy-shell; forward that to the probe.
# shellcheck disable=SC2016 # the stub expands its own arguments when it runs
printf '%s\n' "#!$TEST_BASH" \
  '[ "$1 $2 $3" = "shell summon omarchy.menu" ] || { echo "stub omarchy-shell: $*" >&2; exit 2; }' \
  "exec qs ipc -p '$shell_dir' call probe open \"\$4\"" > "$work/stub/omarchy-shell"
chmod +x "$work/stub/omarchy-shell"
export PATH=$work/stub:$tree/bin:$PATH OMARCHY_PATH=$work/fake

ipc() { timeout 3 qs ipc -p "$shell_dir" call probe "$@"; }
qs -p "$shell_dir" > "$work/qs.log" 2>&1 &
shell_pid=$!
callers=()
# shellcheck disable=SC2329 # run by the EXIT trap
cleanup() {
  for p in "${callers[@]}"; do kill "$p" 2>/dev/null; done
  kill "$shell_pid" 2>/dev/null; wait "$shell_pid" 2>/dev/null
}
trap cleanup EXIT

ready=
for ((i = 0; i < 100; i++)); do
  if out=$(ipc state 2>/dev/null) && [[ $out == *'"rows":'* && $out != *'"rows":0'* ]]; then ready=1; break; fi
  kill -0 "$shell_pid" 2>/dev/null || die "the shell exited during startup"
  sleep 0.1
done
[[ -n $ready ]] || die "the menu never loaded its fixture rows (last state: ${out:-none})"

K_RIGHT=$((0x01000014)) K_RETURN=$((0x01000004)) K_ESCAPE=$((0x01000000)) K_Z=$((0x5a))
failed=0
pass() { echo "PASS $1"; }
fail() { echo "FAIL $1"; failed=1; }
summon() { ipc open "{\"menu\":\"$1\"}" >/dev/null; sleep 0.3; }
field() { ipc state | sed -n "s/.*\"$1\":\"\\{0,1\\}\\([^\",}]*\\).*/\\1/p"; }
active() { ipc state | sed -n 's/.*"active":"\([^"]*\)".*/\1/p'; }
fresh() { rm -f "$marks"/*; }
alive_after() { sleep "$2"; kill -0 "$1" 2>/dev/null; }
exited_within() { # pid seconds -> sets rc; 0 if it exited in time
  local i
  for ((i = 0; i < $2 * 5; i++)); do kill -0 "$1" 2>/dev/null || { wait "$1"; rc=$?; return 0; }; sleep 0.2; done
  return 1
}

# 1a-1d, 1f: rows in `probe` are act(0) link(1) sub(2) d(3).
fresh; summon probe; ipc sel 0 >/dev/null; ipc key $K_RIGHT >/dev/null; sleep 0.8
[[ -e $marks/act ]] && fail "1a Right on an action row ran it" || pass "1a Right on an action row does nothing"
summon probe; ipc sel 1 >/dev/null; ipc key $K_RIGHT >/dev/null; sleep 0.3
[[ $(active) == probe.sub ]] && pass "1b Right on a link row follows it" || fail "1b Right on a link row: active is $(active), want probe.sub"
summon probe; ipc sel 2 >/dev/null; ipc key $K_RIGHT >/dev/null; sleep 0.3
[[ $(active) == probe.sub ]] && pass "1c Right on a submenu row opens it" || fail "1c Right on a submenu row: active is $(active), want probe.sub"
fresh; summon probe; ipc nocursor >/dev/null; ipc key $K_RIGHT >/dev/null; sleep 0.8
[[ -e $marks/act ]] && fail "1d Right with no cursor ran a row" || pass "1d Right with no cursor does nothing"

# 1e, 1g: Right in a prompt must not answer for the caller.
omarchy-menu-input Name > "$work/input.out" 2>&1 & p=$!; callers+=("$p"); sleep 1
ipc key $K_RIGHT >/dev/null
if alive_after "$p" 1; then pass "1e Right in omarchy-menu-input does not submit"; ipc key $K_ESCAPE >/dev/null; exited_within "$p" 5 || kill "$p"
else wait "$p"; fail "1e Right in omarchy-menu-input submitted (caller exited $?, printed '$(cat "$work/input.out")')"; fi
omarchy-menu-select Pick a b > "$work/select.out" 2>&1 & p=$!; callers+=("$p"); sleep 1
ipc key $K_RIGHT >/dev/null
if alive_after "$p" 1; then pass "1g Right in omarchy-menu-select does not pick"; ipc key $K_ESCAPE >/dev/null; exited_within "$p" 5 || kill "$p"
else wait "$p"; fail "1g Right in omarchy-menu-select picked (caller exited $?, printed '$(cat "$work/select.out")')"; fi

# 1f: the positive control. If Enter does nothing, no key arrived and 1a proves nothing.
fresh; summon probe; ipc sel 0 >/dev/null; ipc key $K_RETURN >/dev/null; sleep 0.8
[[ -e $marks/act ]] && pass "1f Enter on an action row runs it (keys arrive)" || fail "1f Enter on an action row did nothing: no key reached the menu"

# 2a, 2b: a displaced request releases its caller, which exits 1 as for Escape.
omarchy-menu-select Pick a b > /dev/null 2>&1 & p=$!; callers+=("$p"); sleep 1
summon probe
if exited_within "$p" 5; then [[ $rc == 1 ]] && pass "2a a select displaced by an open exits 1" || fail "2a displaced select exited $rc, want 1"
else fail "2a a select displaced by an open is still waiting after 5 s"; kill "$p"; fi
omarchy-menu-select First a > /dev/null 2>&1 & p=$!; callers+=("$p"); sleep 1
omarchy-menu-select Second b > /dev/null 2>&1 & p2=$!; callers+=("$p2")
if exited_within "$p" 5; then [[ $rc == 1 ]] && pass "2b a select displaced by a select exits 1" || fail "2b displaced select exited $rc, want 1"
else fail "2b a select displaced by a select is still waiting after 5 s"; kill "$p"; fi
ipc key $K_ESCAPE >/dev/null; exited_within "$p2" 5 || kill "$p2"

# 3a-3d (#1339): the card fits its widest label, up to a cap, and a filter
# does not shrink it. Rows in `wide` are long(0); `probe` labels are short.
summon probe
[[ $(field width) == "$(field base)" ]] && pass "3a a menu of short labels keeps the base width" || fail "3a short labels: width $(field width), want base $(field base)"
summon wide
[[ $(field width) == "$(field cap)" ]] && pass "3b a very long label widens the card to the cap" || fail "3b long label: width $(field width), want cap $(field cap)"
ipc key $K_Z >/dev/null; ipc key $K_Z >/dev/null; ipc key $K_Z >/dev/null; sleep 0.5
[[ $(field filter) == zzz ]] && pass "3c typing reaches the filter (keys arrive)" || fail "3c filter is '$(field filter)', want zzz: no key reached the menu"
[[ $(field width) == "$(field cap)" ]] && pass "3c a filter does not shrink the card" || fail "3c filtered: width $(field width), want cap $(field cap)"
summon probe
[[ $(field width) == "$(field base)" ]] && pass "3d the next menu starts from the base width again" || fail "3d after leaving wide: width $(field width), want base $(field base)"

exit $failed
