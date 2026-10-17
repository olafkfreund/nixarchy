{ pkgs, omarchy }:
# #1305: the real Menu.qml in a headless Quickshell. Right must not run a
# row, and a displaced request must release its caller. Why: tests/AGENTS.md.
pkgs.runCommand "nixarchy-menu-keys"
  {
    nativeBuildInputs = [
      pkgs.bash
      pkgs.coreutils
      pkgs.perl
      omarchy.quickshell
    ];
  }
  ''
    export XDG_RUNTIME_DIR=$TMPDIR/run QT_QPA_PLATFORM=offscreen WAYLAND_DISPLAY=wayland-test LC_ALL=C.UTF-8
    export QML_IMPORT_PATH=${pkgs.qt6.qtdeclarative}/${pkgs.qt6.qtbase.qtQmlPrefix}
    export TEST_BASH=${pkgs.bash}/bin/bash
    mkdir -m 700 "$XDG_RUNTIME_DIR"
    bash ${./menu-keys.sh} ${omarchy}/share/omarchy ${./menu-keys-shell.qml}
    touch $out
  ''
