{ pkgs, omarchy }:
# Real qs argument parsing and IPC, with a headless lock-state fixture.
# This checks delivery/acknowledgement, not the compositor's session lock.
pkgs.runCommand "nixarchy-sleep-lock-generation"
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
    export TEST_BASH=${pkgs.bash}/bin/bash
    bash ${./sleep-lock-generation.sh} ${omarchy}/share/omarchy
    mkdir -p "$out"
  ''
