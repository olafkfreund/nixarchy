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
export TEST_NOTICES=$PWD/notices.jsonl XDG_RUNTIME_DIR=$PWD/runtime NIX_STORE_DIR=$PWD
printf '#!%s\ncat "$TEST_LIST"\n' "$TEST_BASH" > stub/qs
printf '#!%s\nprintf "%%s\\n" "${TEST_MANAGER_ENV:-}"\n' "$TEST_BASH" > stub/systemctl
printf '#!%s\njq -nc --args '\''$ARGS.positional'\'' -- "$@" >> "$TEST_CALLS"\necho "${TEST_HYPR_REPLY:-ok}"\n' "$TEST_BASH" > stub/hyprctl
printf '#!%s\njq -nc --args '\''$ARGS.positional'\'' -- "$@" >> "$TEST_CALLS"\n' "$TEST_BASH" > stub/dbus-update-activation-environment
printf '#!%s\njq -nc --args '\''$ARGS.positional'\'' -- "$@" >> "$TEST_NOTICES"\n[[ -z ${TEST_NOTICE_FAIL:-} ]] || exit 1\nsleep "${TEST_NOTICE_DELAY:-0}"\necho 42\n' "$TEST_BASH" > stub/omarchy-notification-send
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
[[ ! -e $TEST_NOTICES ]] || { echo 'FAIL: a sync without --current sent a notice'; exit 1; }
echo 'PASS: the launcher-style sync never notifies'
: > "$TEST_CALLS"
if TEST_HYPR_REPLY='error: rejected' bash "$helper" sync >result 2>error; then exit 1; fi
jq -se 'length == 1' "$TEST_CALLS" >/dev/null
grep -q 'Hyprland refused' error
echo 'PASS: compositor rejection prevents activation-environment publication'
printf '%s\n' "$one" > "$TEST_LIST"
notice_file=$XDG_RUNTIME_DIR/nixarchy/restart-notice-id
notices() { jq -se "$@" "$TEST_NOTICES" >/dev/null; }
bash "$helper" sync --current "$new"
[[ ! -e $TEST_NOTICES ]] || { echo 'FAIL: equal trees sent a notice'; exit 1; }
echo 'PASS: a switch that keeps the live tree says nothing'
bash "$helper" sync --current "$old"
notices --arg exec "$old/bin/omarchy-restart-shell" '
  length == 1 and (.[0] | index("-r") != null and .[index("--exec") + 1] == $exec and .[index("-r") + 1] == "0")
' || { echo 'FAIL: a different tree did not offer a restart into it'; exit 1; }
echo 'PASS: a different tree offers one restart into the new tree'
bash "$helper" sync --current "$old"
notices 'length == 2 and (.[1] | index("-r") != null and .[index("-r") + 1] == "42")' \
  || { echo 'FAIL: a second switch stacked a notice instead of replacing it'; exit 1; }
echo 'PASS: a second switch replaces the notice'
printf '99999999 42\n' > "$notice_file"
bash "$helper" sync --current "$old"
notices 'length == 3 and (.[2] | index("-r") != null and .[index("-r") + 1] == "0")' \
  || { echo 'FAIL: an id saved by a previous shell was reused'; exit 1; }
echo 'PASS: an id from a restarted shell is not reused'
bash "$helper" sync --current "$new"
{ [[ ! -e $notice_file ]] && notices 'length == 3'; } \
  || { echo 'FAIL: equal trees left the saved id behind'; exit 1; }
echo 'PASS: catching up clears the saved id'
NIX_STORE_DIR=/nix/store bash "$helper" sync --current "$old"
notices 'length == 3' || { echo 'FAIL: a tree outside the store was offered a restart'; exit 1; }
echo 'PASS: a dev-linked tree is never offered a restart'
: > "$TEST_CALLS"
TEST_NOTICE_FAIL=1 bash "$helper" sync --current "$old" \
  || { echo 'FAIL: a failed notifier failed the sync'; exit 1; }
jq -se 'length == 3' "$TEST_CALLS" >/dev/null \
  || { echo 'FAIL: a failed notifier stopped publication'; exit 1; }
echo 'PASS: a failed notifier changes nothing else'
# A switch stalls the notification server for up to ~20s. The user manager delivers, the sync does not wait.
rm -f "$notice_file"
mkdir -p unit-stub
# Like systemd, it cannot pass a $ through untouched: refuse, rather than expand as the real one does.
printf '#!%s\nwhile [[ $1 != -- ]]; do shift; done; shift\nfor a; do [[ $a != *\$* ]] || exit 1; done\n"$@" &\n' "$TEST_BASH" > unit-stub/systemd-run
chmod +x unit-stub/systemd-run
start=$SECONDS
PATH=$PWD/unit-stub:$PATH TEST_NOTICE_DELAY=3 bash "$helper" sync --current "$old"
(( SECONDS - start < 2 )) || { echo 'FAIL: the sync waited for a stalled notifier'; exit 1; }
for ((i=0; i<100; i++)); do [[ -e $notice_file ]] && break; sleep 0.1; done
grep -q ' 42$' "$notice_file" || { echo 'FAIL: a notifier stalled for 3s, as one is during a switch, lost the notice'; exit 1; }
echo 'PASS: a stalled notifier neither holds the switch nor loses the notice'
