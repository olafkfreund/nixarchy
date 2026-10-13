#!/usr/bin/env bash
set -euo pipefail
package=$1
mkdir -p active/shell active/bin stub
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
printf '#!%s\nshift 3\nsleep 0.3\nexec "$@"\n' "$TEST_BASH" > stub/systemd-cat
printf '#!%s\nprintf "%%s\\n" "$*" >> "$HOME/hypr-env"\necho ok\n' "$TEST_BASH" > stub/hyprctl
printf '#!%s\nprintf "%%s\\n" "$@" > "$HOME/dbus-env"\n' "$TEST_BASH" > stub/dbus-update-activation-environment
chmod +x stub/*
export OMARCHY_PATH=$PWD/active HYPRLAND_INSTANCE_SIGNATURE=test PATH=$PWD/stub:$PATH
"$package/bin/omarchy-launch-shell" > launch.log 2>&1 &
launcher=$!
trap 'kill "$launcher" 2>/dev/null || true; wait "$launcher" 2>/dev/null || true' EXIT
for ((i=0; i<100; i++)); do
  [[ ! -e $HOME/dbus-env ]] || break
  sleep 0.1
done
[[ -e $HOME/dbus-env ]] || { cat launch.log; echo 'FAIL: launcher did not synchronize'; exit 1; }
grep -Fq "OMARCHY_PATH=$OMARCHY_PATH" "$HOME/dbus-env"
grep -Fq "PATH=$OMARCHY_PATH/bin:" "$HOME/dbus-env"
grep -Fq "$OMARCHY_PATH" "$HOME/hypr-env"
echo 'PASS: launch publishes the live tree and PATH to compositor and activation environments'
