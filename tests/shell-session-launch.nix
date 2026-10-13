{ pkgs, omarchy }:
pkgs.runCommand "nixarchy-shell-session-launch"
  {
    nativeBuildInputs = [
      pkgs.bash
      pkgs.coreutils
      pkgs.gnugrep
      omarchy.quickshell
    ];
  }
  ''
    export HOME=$TMPDIR/home XDG_RUNTIME_DIR=$TMPDIR/runtime
    export QT_QPA_PLATFORM=offscreen WAYLAND_DISPLAY=wayland-test
    mkdir -p "$HOME" "$XDG_RUNTIME_DIR"
    chmod 700 "$XDG_RUNTIME_DIR"
    export TEST_BASH=${pkgs.bash}/bin/bash
    bash ${./shell-session-launch.sh} ${omarchy}/share/omarchy
    touch "$out"
  ''
