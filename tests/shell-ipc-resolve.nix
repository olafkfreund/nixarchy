{ pkgs, omarchy }:
# Real Quickshell IPC is essential: --newest cannot be combined with --pid.
pkgs.runCommand "nixarchy-shell-ipc-resolve"
  {
    nativeBuildInputs = [
      pkgs.bash
      pkgs.coreutils
      pkgs.jq
      omarchy.quickshell
    ];
  }
  ''
    export HOME=$TMPDIR/home XDG_RUNTIME_DIR=$TMPDIR/runtime
    export QT_QPA_PLATFORM=offscreen WAYLAND_DISPLAY=wayland-test
    mkdir -p "$HOME" "$XDG_RUNTIME_DIR"
    chmod 700 "$XDG_RUNTIME_DIR"
    bash ${./shell-ipc-resolve.sh} ${omarchy}/share/omarchy
    touch "$out"
  ''
