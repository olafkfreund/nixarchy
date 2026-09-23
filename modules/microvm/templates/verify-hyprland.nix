# THROWAWAY verification wrapper for #821 plan step 2. Imports the real
# template unchanged and adds a console probe, so the thing under test is the
# file that ships. Reverted before the PR.
{ pkgs, ... }:
{
  imports = [ ./hyprland.nix ];
  environment.systemPackages = [ pkgs.mesa-demos ];

  programs.bash.loginShellInit = ''
    if [ "$(tty)" = /dev/ttyS0 ] && [ -z "''${VERIFY_RAN:-}" ]; then
      :
      export VERIFY_RAN=1
      echo "=== VERIFY BEGIN ==="

      # The compositor was found in D state in p9_client_rpc at 30s: blocked
      # reading the store over 9p, not hung. Poll instead of assuming a
      # timeout -- and report how long it actually took, because that number
      # belongs in the template's note.
      t=0
      while [ $t -lt 180 ]; do
        if [ -e "$XDG_RUNTIME_DIR"/hypr/*/.socket.sock ] 2>/dev/null; then break; fi
        sleep 5
        t=$((t + 5))
      done
      echo "command socket appeared after ~''${t}s (0 = already there)"

      echo "--- the unit ---"
      systemctl --user is-active hyprland || true
      systemctl --user show hyprland -p ActiveState -p SubState -p Result 2>&1 || true

      export HYPRLAND_INSTANCE_SIGNATURE=$(basename "$(ls -td "$XDG_RUNTIME_DIR"/hypr/*/ 2>/dev/null | head -1)")
      export WAYLAND_DISPLAY=$(basename "$(ls -t "$XDG_RUNTIME_DIR"/wayland-* 2>/dev/null | grep -v '\.lock$' | head -1)")
      echo "HIS=''${HYPRLAND_INSTANCE_SIGNATURE:-UNSET} WAYLAND_DISPLAY=''${WAYLAND_DISPLAY:-UNSET}"

      echo "--- runtime dir ---"
      ls -la "$XDG_RUNTIME_DIR" 2>&1 | head -20

      echo "--- the compositor log (journal) ---"
      journalctl --user -u hyprland --no-pager 2>&1 | tail -6

      # With enable_stdout_logs off the detail lives in the runtime file, not
      # the journal. Reading the journal instead measured nothing -- the
      # instrument changed with the variable.
      echo "--- the compositor log (runtime file: where the detail actually is) ---"
      find "$XDG_RUNTIME_DIR/hypr" -name hyprland.log -exec tail -25 {} + 2>&1 || echo "NO LOG"

      echo "--- is it alive or spinning? ---"
      pid=$(systemctl --user show hyprland -p MainPID --value)
      echo "MainPID=$pid"
      cat /proc/$pid/status 2>/dev/null | grep -E "^State|^Threads"
      cat /proc/$pid/wchan 2>/dev/null; echo
      ls -l /proc/$pid/fd 2>/dev/null | tail -8

      echo "--- monitors ---"
      hyprctl monitors 2>&1 | head -10

      echo "--- grim ---"
      if grim -t ppm /tmp/s.ppm 2>&1; then head -2 /tmp/s.ppm | tr '\n' ' '; echo; else echo "GRIM FAILED"; fi

      echo "--- a window ---"
      foot >/dev/null 2>&1 &
      sleep 6
      hyprctl -j clients 2>&1 | grep -E '"class"|"title"' || echo "NO CLIENTS"

      echo "--- event socket ---"
      ls "$XDG_RUNTIME_DIR"/hypr/*/.socket2.sock 2>&1 || echo "NO EVENT SOCKET"

      echo "=== VERIFY END ==="
      sleep 2
      poweroff
    fi
  '';
}
