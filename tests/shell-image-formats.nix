{ inputs, pkgs }:
# #1284: quattro's default wallpaper is a .webp, and the shell drew black
# because nixpkgs' quickshell carries no qtimageformats -- the WebP decoder is
# a Qt plugin, not part of qtbase. session passed only because its own
# backgrounds are JPEGs, so nothing could see the gap.
#
# This loads a WebP through a QML Image with the QT_PLUGIN_PATH that
# quickshell's own wrapper sets, so it varies exactly the thing that broke: the
# plugin directories the shell is launched with. The qml binary is the same
# Qt's, but the plugin path is the shell's, not ours.
let
  system = pkgs.stdenv.hostPlatform.system;
  deps = inputs.self.packages.${system}.omarchy.passthru.runtimeDeps;
  quickshell = pkgs.lib.findFirst (d: (d.pname or "") == "quickshell") null deps;
in
assert pkgs.lib.assertMsg (
  quickshell != null
) "shell-image-formats: no quickshell in omarchy.passthru.runtimeDeps; nothing to check";
pkgs.runCommand "nixarchy-shell-image-formats"
  {
    nativeBuildInputs = [
      pkgs.imagemagick
      pkgs.libwebp
      pkgs.qt6.qtdeclarative
    ];
  }
  ''
    set -o pipefail
    export HOME=$TMPDIR/home XDG_RUNTIME_DIR=$TMPDIR/runtime QT_QPA_PLATFORM=offscreen
    export QT_FORCE_STDERR_LOGGING=1
    export QML_IMPORT_PATH=${pkgs.qt6.qtdeclarative}/${pkgs.qt6.qtbase.qtQmlPrefix}
    export FONTCONFIG_FILE=${pkgs.makeFontsConf { fontDirectories = [ ]; }}
    mkdir -p "$HOME" "$XDG_RUNTIME_DIR"
    chmod 700 "$XDG_RUNTIME_DIR"

    # The wrapper is a compiled makeCWrapper; its source is embedded as text,
    # one `--prefix 'QT_PLUGIN_PATH' ':' '<dir>'` per plugin directory.
    plugins=$(grep -ao "prefix 'QT_PLUGIN_PATH' ':' '[^']*'" ${quickshell}/bin/quickshell \
      | sed "s/.*':' '//; s/'$//" | paste -sd:) || true
    if [ -z "$plugins" ]; then
      echo "REFUSED: no QT_PLUGIN_PATH could be read out of ${quickshell}/bin/quickshell."
      echo "         The wrapper format may have changed; this check cannot run, so it does not pass."
      exit 1
    fi
    echo "QT_PLUGIN_PATH=$plugins"
    export QT_PLUGIN_PATH=$plugins

    magick -size 64x64 xc:'#2E8B57' bg.png
    cwebp -quiet bg.png -o bg.webp
    file_type=$(head -c 12 bg.webp | tail -c 4)
    [ "$file_type" = WEBP ] || { echo "REFUSED: bg.webp is not a WebP"; exit 1; }

    printf '%s\n' \
      'import QtQuick' \
      'Item {' \
      '  Image {' \
      '    source: "bg.webp"' \
      '    function check() {' \
      '      if (status === Image.Ready) { console.log("ready " + width + "x" + height); Qt.quit() }' \
      '      else if (status === Image.Error) { console.log("error status=" + status + " (decode error is logged above)"); Qt.exit(1) }' \
      '    }' \
      '    onStatusChanged: check()' \
      '    Component.onCompleted: check()' \
      '  }' \
      '  Timer { interval: 10000; running: true; onTriggered: { console.log("timeout"); Qt.exit(1) } }' \
      '}' > probe.qml

    rc=0
    qml probe.qml > result 2>&1 || rc=$?
    echo "== qml exit $rc"; cat result
    if ! grep -qE 'ready [1-9][0-9]*x[1-9][0-9]*' result; then
      echo "FAIL: the shell's plugin path cannot decode a WebP (#1284)."
      exit 1
    fi
    touch $out
  ''
