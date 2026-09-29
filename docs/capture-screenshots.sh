#!/usr/bin/env bash
# Captures nixarchy-menu's palette, and every Omarchy menu through it, from a
# running nixarchy VM, for the README.
# Run it ON the VM: ssh -p 2222 omarchy@localhost 'bash -s' < this
#
# The VM must have a real display backend:
#   QEMU_OPTS="-device virtio-vga-gl -display gtk,gl=on" nix run .#vm
# With -display none nothing consumes the compositor's frames, page flips
# never complete, and grim blocks forever.
set -euo pipefail

out="${1:-$HOME/nixarchy-screenshots}"
mkdir -p "$out"

pid=$(pgrep -f "quickshell -n" | head -1) || {
  echo "the Omarchy shell is not running" >&2
  exit 1
}
# Driving the menu needs the session's handles, which an ssh login lacks.
eval "$(tr '\0' '\n' <"/proc/$pid/environ" |
  grep -E '^(WAYLAND_DISPLAY|XDG_RUNTIME_DIR|HYPRLAND_INSTANCE_SIGNATURE)=' |
  sed 's/^/export /')"

menu_open() { [[ $(hyprctl layers 2>/dev/null) == *'namespace: omarchy-menu'* ]]; }
toggle() { omarchy-shell shell toggle omarchy.menu "$@" >/dev/null 2>&1 || true; sleep 1.2; }
close() {
  wtype -k Escape
  for _ in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15; do
    menu_open || return 0
    sleep 0.2
  done
}

shot() { # shot <file-name> [menu-id]; no menu-id captures the desktop
  local name=$1 menu=${2:-}
  # The only menu IPC is `toggle`, so state is observed rather than assumed --
  # an earlier version assumed, and every second shot came out with the menu
  # in the wrong state.
  # `&&` alone returns non-zero when the menu is already shut, and set -e
  # then bails out of this function before the screenshot is taken.
  menu_open && close || true
  if [ -n "$menu" ]; then
    toggle "{\"menu\":\"$menu\"}"
    menu_open || toggle "{\"menu\":\"$menu\"}"
    menu_open || { echo "  $name.png SKIPPED (menu would not open)" >&2; return; }
  fi
  grim "$out/$name.png" && echo "  $name.png"
}

echo "capturing to $out"
shot 00-desktop
# Explicit names: the README links to these, and an incrementing counter got
# them all wrong anyway -- $((++i)) inside $( ) increments in a subshell.
shot 01-menu-root root
shot 02-install install
shot 03-install-service install.service
shot 04-install-editor install.editor
shot 05-install-terminal install.terminal
shot 06-install-browser install.browser
shot 07-install-gaming install.gaming
shot 08-install-ai install.ai
shot 09-remove remove
shot 10-update update
shot 11-learn learn
shot 12-style style
shot 13-setup setup
shot 14-system system
# The rows this port adds. `trigger.ask` is hidden until a default agent is
# chosen -- shot() reports a menu that will not open rather than capturing the
# wrong screen, so an empty 20-ask.png means no agent was set on the VM.
shot 19-trigger trigger
shot 20-ask trigger.ask
shot 21-setup-agent setup.default.agent
menu_open && close || true

echo
echo "copy them in with:"
echo "  scp -P 2222 'omarchy@localhost:$out/*.png' docs/screenshots/"
