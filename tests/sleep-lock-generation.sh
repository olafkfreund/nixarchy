#!/usr/bin/env bash
set -euo pipefail

package_tree=$(readlink -f "$1")
mkdir -p old/shell old/bin new/shell new/bin stub
old_tree=$PWD/old
new_tree=$PWD/new
for tree in "$old_tree" "$new_tree"; do
  ln -s "$package_tree/bin/omarchy-system-sleep-lock" "$tree/bin/omarchy-system-sleep-lock"
  cat > "$tree/shell/shell.qml" <<'QML'
import Quickshell
import Quickshell.Io

ShellRoot {
    IpcHandler {
        target: "lock"
        property bool secured: false
        function lock(): string { secured = true; return "ok"; }
        function reset(): void { secured = false; }
        function status(): string {
            return JSON.stringify({secure: secured, requested: secured});
        }
    }
}
QML
done

# Keep the real monitor, lock helper, omarchy-shell and qs. Only external
# effects are stubbed: the logind budget, monitor reconciliation and toast.
printf '#!%s\necho "t 3000000"\n' "$TEST_BASH" > stub/busctl
printf '#!%s\nexit 0\n' "$TEST_BASH" > stub/omarchy-hyprland-monitor-clamshell
# shellcheck disable=SC2016 # HOME is read when the notification stub runs.
printf '#!%s\necho notified >> "$HOME/notifications"\n' "$TEST_BASH" > stub/omarchy-notification-send
chmod +x stub/*
export PATH=$PWD/stub:$package_tree/bin:$PATH

shell_pid=
monitor_pid=
cleanup() {
  if [[ -n $monitor_pid ]]; then kill "$monitor_pid" 2>/dev/null || true; wait "$monitor_pid" 2>/dev/null || true; fi
  if [[ -n $shell_pid ]]; then kill "$shell_pid" 2>/dev/null || true; wait "$shell_pid" 2>/dev/null || true; fi
}
trap cleanup EXIT
fail() {
  echo "FAIL: $*" >&2
  cat shell.log monitor.log 2>/dev/null || true
  exit 1
}
start_shell() {
  running_tree=$1
  qs -p "$running_tree/shell" > shell.log 2>&1 &
  shell_pid=$!
  for ((attempt = 0; attempt < 100; attempt++)); do
    if LC_ALL=C.UTF-8 timeout 1s qs ipc -p "$running_tree/shell" call lock status > status.json 2>/dev/null; then
      if jq -e '.secure == false' status.json >/dev/null; then return; fi
    fi
    kill -0 "$shell_pid" 2>/dev/null || fail "fixture exited during startup"
    sleep 0.1
  done
  fail "fixture did not become ready"
}
assert_locked() {
  LC_ALL=C.UTF-8 timeout 2s qs ipc -p "$running_tree/shell" call lock status > status.json
  jq -e '.secure == true' status.json >/dev/null || fail "$1: the running shell received no lock request"
  [[ ! -e $HOME/notifications ]] || fail "$1: the helper failed to acknowledge the secure lock"
  echo "PASS: $1"
}
consume() {
  printf 'boolean true\n' | OMARCHY_PATH="$1" timeout 5s \
    "$package_tree/bin/omarchy-system-sleep-monitor" --consume > monitor.log 2>&1
  # The monitor exits zero even when its helper fails: inspect the lock state
  # AND absence of a failure notification, never just the monitor's status.
  assert_locked "$2"
}

start_shell "$old_tree"
consume "$old_tree" "matching generation"
qs ipc -p "$running_tree/shell" call lock reset
consume "$new_tree" "new service tree with the old shell still running"
consume "$new_tree" "already-secure shell with a different service tree"
qs ipc -p "$running_tree/shell" call lock reset
consume /collected-tree "collected caller tree"

# Hold a real monitor process across a shell replacement, without changing its
# environment. Its next event must find the new shell, not its startup tree.
mkfifo events
exec 3<> events
OMARCHY_PATH="$old_tree" timeout 10s "$package_tree/bin/omarchy-system-sleep-monitor" --consume <&3 > monitor.log 2>&1 &
monitor_pid=$!
kill "$shell_pid"
wait "$shell_pid" || true
shell_pid=
start_shell "$new_tree"
printf 'boolean true\n' >&3
wait "$monitor_pid" || fail "monitor did not finish after the event"
monitor_pid=
exec 3>&-
assert_locked "old monitor tree after the shell restarts on the new tree"
