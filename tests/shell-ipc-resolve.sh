#!/usr/bin/env bash
set -euo pipefail
package=$1
mkdir -p active/shell active/bin
ln -s "$package/bin/omarchy-system-sleep-lock" active/bin/omarchy-system-sleep-lock
cat > active/shell/shell.qml <<'QML'
import Quickshell
import Quickshell.Io
ShellRoot {
    IpcHandler {
        target: "shell"
        function ping(): string { return "live"; }
    }
}
QML
qs -p "$PWD/active/shell" > shell.log 2>&1 &
pid=$!
trap 'kill "$pid" 2>/dev/null || true; wait "$pid" 2>/dev/null || true' EXIT
for ((i=0; i<100; i++)); do
  if qs ipc --pid "$pid" call shell ping >/dev/null 2>&1; then break; fi
  sleep 0.1
done
# Simulate a new caller, an already-collected caller, and no inherited tree.
for caller in "$PWD/active" /does-not-exist ''; do
  reply=$(OMARCHY_PATH="$caller" "$package/bin/omarchy-shell" shell ping)
  [[ $reply == live ]] || { echo "FAIL: caller $caller returned $reply"; exit 1; }
done
if WAYLAND_DISPLAY=another-display "$package/bin/omarchy-shell" shell ping; then
  echo 'FAIL: IPC crossed displays'; exit 1
fi
kill "$pid"
wait "$pid" || true
if "$package/bin/omarchy-shell" shell ping; then
  echo 'FAIL: missing shell reported success'; exit 1
fi
echo 'PASS: real IPC survives missing/stale trees and refuses another display'
