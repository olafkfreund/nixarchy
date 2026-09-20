{ pkgs, ... }:
# The QML this repo injects into upstream's Quickshell tree is copied, never
# compiled -- so a syntax error builds perfectly and ships. What the user sees
# is a bar element that silently is not there, and the highest layer that can
# currently see it is a human looking at their own bar (#810, §2).
#
# qmllint answers it at evaluation cost. Two things about how it is used here:
#
# 1. **The gate is syntax, not warnings.** In a sandbox there is no Quickshell
#    module path, so import resolution CANNOT succeed -- a correct file still
#    emits `Failed to import QtQuick ... [import]`. A check demanding clean
#    imports would fail on every valid file, which is §4's failure in the other
#    direction. Measured with qmllint 6.11.2: a good file is exit=0 with zero
#    `[syntax]` lines, the same file with one extra brace is exit=255 with one.
#
# 2. **It carries its own broken fixture.** The first thing it does is lint a
#    file that MUST be rejected. If that comes back clean the check fails
#    immediately and says so, because a linter that has stopped detecting
#    syntax errors is indistinguishable from a tree that has none -- and this
#    check's whole value is that it can go red. §1 in the check rather than in
#    a PR body somebody has to trust.
#
# 3. **One of the three is a FRAGMENT, not a document.** shell-state-ipc.qml is
#    inserted into shell.qml's `shell` IpcHandler by awk -- it is a run of
#    `function` declarations with no enclosing object, and linting it standalone
#    reports `Expected a qualified name id [syntax]` on a perfectly correct
#    file. That is a check failing for the wrong reason, so it is wrapped in a
#    minimal host object first, which still catches the unbalanced brace this
#    exists to find. If upstream ever makes it a whole file, move it to the
#    documents list and delete the wrapper.
let
  # One extra brace, which is the realistic typo.
  broken = builtins.toFile "Broken.qml" ''
    import QtQuick
    Item { property int n: 1; Text { text: "n=" + parent.n }} }
  '';
in
pkgs.runCommand "nixarchy-qml"
  {
    nativeBuildInputs = [ pkgs.qt6.qtdeclarative ];
    # Listed rather than globbed: a file that stops being injected should be a
    # readable diff here, the same argument pkgs/omarchy/default.nix makes for
    # its runtime list.
    src = ../pkgs/omarchy;
  }
  ''
    set -o pipefail

    # `--bare` so no project/qmldir discovery is attempted; there is none here.
    lint() { qmllint --bare "$1" 2>&1 || true; }

    echo "== self-test: the linter must reject a known-broken file"
    if ! lint ${broken} | grep -q '\[syntax\]'; then
      echo "FAIL: qmllint did not report [syntax] on a file with an extra brace."
      echo "      This check cannot fail, so it is not checking anything."
      lint ${broken}
      exit 1
    fi
    echo "   ok: broken fixture is rejected"

    rc=0

    # The fragment: wrapped, because it has no enclosing object of its own.
    mkdir -p wrapped
    { echo "import QtQuick"; echo "Item {"; cat "$src/shell-state-ipc.qml"; echo "}"; } \
      > wrapped/shell-state-ipc.qml

    for f in menu-bar-widget.qml switch-indicator.qml wrapped/shell-state-ipc.qml; do
      echo "== $f"
      case "$f" in
        wrapped/*) report=$(lint "$f") ;;
        *)         report=$(lint "$src/$f") ;;
      esac
      # NOT `out=` -- that is the builder's output path, and clobbering it
      # fails later with `touch: unrecognized option` far from the cause.
      if printf '%s' "$report" | grep -q '\[syntax\]'; then
        echo "FAIL: $f has a syntax error:"
        printf '%s\n' "$report" | grep -A2 '\[syntax\]'
        rc=1
      else
        echo "   ok"
      fi
    done

    [ "$rc" -eq 0 ] || exit 1
    echo "every injected QML file parses"
    touch $out
  ''
