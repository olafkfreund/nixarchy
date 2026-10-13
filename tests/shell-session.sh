#!/usr/bin/env bash
# Black-box resolver tests: real /proc environments, stubbed external services.
# shellcheck disable=SC2016 # Stub variables expand in the child, not here.
set -euo pipefail
helper=$1
mkdir -p 'old tree/shell' 'new "tree/shell' 'new "tree/bin' stub
old=$PWD/'old tree'
new=$PWD/'new "tree'
touch "$old/shell/shell.qml" "$new/shell/shell.qml" "$new/bin/omarchy-system-sleep-lock"
export TEST_LIST=$PWD/instances.json TEST_CALLS=$PWD/calls.jsonl
printf '#!%s\ncat "$TEST_LIST"\n' "$TEST_BASH" > stub/qs
printf '#!%s\nprintf "%%s\\n" "${TEST_MANAGER_ENV:-}"\n' "$TEST_BASH" > stub/systemctl
printf '#!%s\njq -nc --args '\''$ARGS.positional'\'' -- "$@" >> "$TEST_CALLS"\necho "${TEST_HYPR_REPLY:-ok}"\n' "$TEST_BASH" > stub/hyprctl
printf '#!%s\njq -nc --args '\''$ARGS.positional'\'' -- "$@" >> "$TEST_CALLS"\n' "$TEST_BASH" > stub/dbus-update-activation-environment
chmod +x stub/*
export PATH=$PWD/stub:$PATH WAYLAND_DISPLAY=wayland-test OMARCHY_PATH=$old
# The child's executable is irrelevant; the resolver inspects a real process
# environment, rather than a test-only /proc override in the shipped helper.
env PATH="$old/bin:/user/bin:/profile/bin:/user/bin" WAYLAND_DISPLAY=wayland-test \
  HYPRLAND_INSTANCE_SIGNATURE='test-instance' "$TEST_BASH" -c \
  'printf ready > "$1"; exec "$2" 120' bash "$PWD/ready" "$TEST_SLEEP" &
pid=$!
trap 'kill "$pid" 2>/dev/null || true; wait "$pid" 2>/dev/null || true' EXIT
# Wait until the child has inherited the intended environment.
for ((i=0; i<100; i++)); do
  [[ ! -e ready ]] || break
  sleep 0.01
done
one=$(jq -nc --arg path "$new/shell/shell.qml" --argjson pid "$pid" '[{pid:$pid,config_path:$path}]')
printf '%s\n' "$one" > "$TEST_LIST"
[[ $(bash "$helper" tree) == "$new" ]]
[[ $(bash "$helper" pid) == "$pid" ]]
echo 'PASS: stale caller resolves the live tree and PID'
[[ $(WAYLAND_DISPLAY=other bash "$helper" tree --if-running) == '' ]]
echo 'PASS: other display is ignored'
[[ $(bash "$helper" tree --pid 99999999 --if-running) == '' ]]
echo 'PASS: launch waits for its own PID'
TEST_MANAGER_ENV=WAYLAND_DISPLAY=wayland-test env -u WAYLAND_DISPLAY bash "$helper" pid > resolved
[[ $(cat resolved) == "$pid" ]]
if env -u WAYLAND_DISPLAY bash "$helper" pid >result 2>error; then exit 1; fi
grep -q 'no Wayland session' error
echo 'PASS: SSH uses the manager only to locate the display'
jq '. + .' <<< "$one" > "$TEST_LIST"
if bash "$helper" pid >result 2>error; then exit 1; fi
grep -q 'refusing to guess' error
echo 'PASS: ambiguous instances are refused'
jq '.[0].config_path = "/unrelated/main.qml"' <<< "$one" > "$TEST_LIST"
[[ $(bash "$helper" tree --if-running) == '' ]]
jq '.[0].pid = 99999999' <<< "$one" > "$TEST_LIST"
[[ $(bash "$helper" tree --if-running) == '' ]]
echo 'PASS: unrelated configurations and exited processes are ignored'
printf 'No running instances.\n' > "$TEST_LIST"
[[ $(bash "$helper" tree --if-running) == '' ]]
printf 'malformed\n' > "$TEST_LIST"
if bash "$helper" tree --if-running >result 2>error; then exit 1; fi
grep -q 'cannot read Quickshell instance list' error
echo 'PASS: empty sentinel is accepted and malformed output is refused'
printf '%s\n' "$one" > "$TEST_LIST"
bash "$helper" sync
expected_path="$new/bin:/user/bin:/profile/bin"
jq -se --arg tree "$new" --arg path "$expected_path" '
  length == 3 and
  .[0] == ["-i", "test-instance", "eval", ("hl.env(\"OMARCHY_PATH\", " + ($tree|tojson) + "); hl.env(\"PATH\", " + ($path|tojson) + ")")] and
  .[1] == ["-i", "test-instance", "reload", "config-only"] and
  .[2] == ["--systemd", "OMARCHY_PATH=" + $tree, "PATH=" + $path]
' "$TEST_CALLS" >/dev/null || { echo 'FAIL: environment publication differs between consumers'; exit 1; }
echo 'PASS: quoted paths are published consistently and obsolete PATH entries removed'
: > "$TEST_CALLS"
if TEST_HYPR_REPLY='error: rejected' bash "$helper" sync >result 2>error; then exit 1; fi
jq -se 'length == 1' "$TEST_CALLS" >/dev/null
grep -q 'Hyprland refused' error
echo 'PASS: compositor rejection prevents activation-environment publication'
