{ pkgs, omarchy, omarchySrc }:
# Omarchy's manifestHasKind tested `Array.isArray(manifest.kinds)`. A manifest
# read through a QML property carries `kinds` as a Qt sequence -- it has a
# length and entries, but Array.isArray says false. So a keep-loaded plugin's
# scoped shell API was recorded as `no-menu`, re-checked as `menu` at the first
# shell.json change, revoked for the mismatch, and the plugin was left holding a
# destroyed object: `shell.barConfig` read null until the shell restarted
# (#877; confirmed on razer with log lines in a copy of shell.qml).
#
# This runs the function, it does not grep for it. The function is cut out of
# the BUILT shell.qml -- what ships, patch included -- and called in a real QML
# engine against a real Qt sequence: a `property list<string>` read back, for
# which Array.isArray is false (qtdeclarative 6.11.2).
#
# Three things about how:
#
# 1. **The function is declared inside the handler, as plain JavaScript.**
#    Declared as a member of the probe Item, every call is marshalled through
#    QVariant, which turns the Qt sequence INTO a JS array (and a plain array
#    into something that is not one). That probe tested Qt's argument
#    conversion, not the bug -- its first run failed the control for exactly
#    that reason.
#
# 2. **It reports through the exit code.** The `qml` tool does not print a
#    script's console output here, so the probe calls Qt.exit(10 + bits), one
#    bit per failed assertion. The offset keeps the probe's answer apart from
#    the tool's own error exits, which are small numbers: an exit below 10 is a
#    harness failure and is reported as one, never read as a result.
#
# 3. **It carries its own negative control** (AGENTS.md section 4). The same
#    probe is first run against upstream's unpatched function, from the source
#    before any patch, and MUST fail on the sequence case. If it passes, this
#    probe can no longer tell the bug from the fix, and the check goes red for
#    that instead.
pkgs.runCommand "nixarchy-manifest-has-kind"
{
  nativeBuildInputs = [
    pkgs.qt6.qtdeclarative
    pkgs.gawk
  ];
}
  ''
    export HOME=$TMPDIR XDG_RUNTIME_DIR=$TMPDIR QT_QPA_PLATFORM=offscreen
    # The sandbox has no QML import path of its own, so `import QtQuick` would
    # not resolve and qml exits "Did not load any objects".
    export QML_IMPORT_PATH=${pkgs.qt6.qtdeclarative}/${pkgs.qt6.qtbase.qtQmlPrefix}
    export FONTCONFIG_FILE=${pkgs.makeFontsConf { fontDirectories = [ ]; }}

    # From the function's signature to its closing brace at two spaces, which is
    # how shell.qml indents a top-level function.
    extract() {
      awk '/function manifestHasKind\(/ { on = 1 } on { print } on && /^  }$/ { exit }' "$1"
    }

    # Bits: 1 = a sequence missed "menu" (the bug), 2 = a plain array missed
    # "menu", 4 = a sequence matched "bar", 8 = a null manifest matched.
    probe() {
      fn=$(extract "$1")
      printf '%s\n' "$fn" | grep -q 'function manifestHasKind' || {
        echo "FAIL: manifestHasKind not found in $1; upstream moved or renamed it"
        exit 1
      }
      {
        echo 'import QtQuick'
        echo 'Item {'
        echo '  id: root'
        echo '  property list<string> kindsList: ["menu", "bar-widget"]'
        echo '  Component.onCompleted: {'
        printf '%s\n' "$fn"
        echo '    var bits = 0'
        echo '    if (!manifestHasKind({ kinds: root.kindsList }, "menu")) bits += 1'
        echo '    if (!manifestHasKind({ kinds: ["menu", "bar-widget"] }, "menu")) bits += 2'
        echo '    if (manifestHasKind({ kinds: root.kindsList }, "bar")) bits += 4'
        echo '    if (manifestHasKind(null, "menu")) bits += 8'
        echo '    Qt.exit(10 + bits)'
        echo '  }'
        echo '}'
      } > probe.qml
      timeout 60 qml probe.qml > qml.log 2>&1 && code=0 || code=$?
      # Below 10 is the tool, not the probe: a load error, a crash, a timeout.
      if [ "$code" -lt 10 ] || [ "$code" -gt 25 ]; then
        echo "FAIL: the probe did not run (qml exit $code) for $1:"
        cat qml.log
        exit 1
      fi
      bits=$((code - 10))
    }

    # The control: upstream's function must fail, and on the sequence case.
    probe ${omarchySrc}/shell/shell.qml
    if [ $((bits & 1)) -eq 0 ]; then
      echo "FAIL: the probe no longer catches the bug in upstream's function (bits $bits)"
      exit 1
    fi
    echo "control: upstream's manifestHasKind misses \"menu\" in a Qt sequence, as it should (bits $bits)"

    # The real check: what ships.
    probe ${omarchy}/share/omarchy/shell/shell.qml
    rc=$bits
    if [ "$rc" -ne 0 ]; then
      echo "FAIL: the built manifestHasKind is wrong (bits $rc):"
      [ $((rc & 1)) -ne 0 ] && echo "  a Qt sequence of kinds does not match \"menu\"; keep-loaded plugins lose their shell API (#877)"
      [ $((rc & 2)) -ne 0 ] && echo "  a plain array of kinds does not match \"menu\""
      [ $((rc & 4)) -ne 0 ] && echo "  a Qt sequence matches \"bar\", which it does not contain"
      [ $((rc & 8)) -ne 0 ] && echo "  a null manifest matches"
      exit 1
    fi
    echo "manifestHasKind: all four cases correct"
    touch $out
  ''
