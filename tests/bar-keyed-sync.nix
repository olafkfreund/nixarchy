{
  pkgs,
  omarchy,
}:
# Bar.qml handed each ModuleList Repeater a fresh JS array on every layout
# change, and QML does not diff a JS array: one icon moved, dragged into a Bar
# Folder, put or removed rebuilt every widget in that region on every monitor --
# 28-75 s of frozen bar per save on p620 (#901). The carried patch keeps a keyed
# ListModel per ModuleList, synced by BarModel.syncEntries.
#
# This runs the BUILT BarModel.js against a real ListModel and counts the model's
# own signals -- rowsInserted / rowsRemoved / rowsMoved / dataChanged -- so "only
# the affected slot changed" is measured, not assumed. Results come back through
# Qt.exit(10 + bits); an exit below 10 is the tool failing, never a result.
#
# It carries its own negative control (AGENTS.md section 4): the same probe is
# first run against a naive clear-and-append syncEntries -- what handing the
# Repeater a new array amounts to -- and MUST fail. If it passes, this probe can
# no longer tell the fix from the bug, and the check goes red for that.
pkgs.runCommand "nixarchy-bar-keyed-sync"
  {
    nativeBuildInputs = [ pkgs.qt6.qtdeclarative ];
  }
  ''
    export HOME=$TMPDIR XDG_RUNTIME_DIR=$TMPDIR QT_QPA_PLATFORM=offscreen
    export QML_IMPORT_PATH=${pkgs.qt6.qtdeclarative}/${pkgs.qt6.qtbase.qtQmlPrefix}
    export FONTCONFIG_FILE=${pkgs.makeFontsConf { fontDirectories = [ ]; }}

    # Bits: 1 identical list caused ops; 2 a move was not exactly one move;
    # 4 a removal was not exactly one remove; 8 an insertion was not exactly one
    # insert; 16 a settings change was not exactly one data change; 32 a
    # duplicate-id reorder was not exactly one move; 64 a final order was wrong.
    cat > probe.qml <<'QML'
    import QtQuick
    import "BarModel.js" as BarModel
    Item {
      id: root
      property int ins: 0
      property int rem: 0
      property int mov: 0
      property int dat: 0
      ListModel { id: lm }
      Connections {
        target: lm
        function onRowsInserted(p, first, last) { root.ins += last - first + 1 }
        function onRowsRemoved(p, first, last) { root.rem += last - first + 1 }
        function onRowsMoved(p, start, end, dest, row) { root.mov += end - start + 1 }
        function onDataChanged(tl, br, roles) { root.dat += 1 }
      }
      function reset(list) {
        lm.clear()
        BarModel.syncEntries(lm, list)
        ins = 0; rem = 0; mov = 0; dat = 0
      }
      function sameAs(list) {
        if (lm.count !== list.length) return false
        for (var i = 0; i < list.length; i++)
          if (lm.get(i).entryJson !== JSON.stringify(list[i])) return false
        return true
      }
      function ops(i, r, m, d) { return ins === i && rem === r && mov === m && dat === d }
      Component.onCompleted: {
        var bits = 0
        var base = ["a", { id: "b", x: 1 }, "c", "d"]
        reset(base); BarModel.syncEntries(lm, base)
        if (!ops(0, 0, 0, 0)) bits |= 1
        if (!sameAs(base)) bits |= 64
        var moved = ["c", "a", { id: "b", x: 1 }, "d"]
        reset(base); BarModel.syncEntries(lm, moved)
        if (!ops(0, 0, 1, 0)) bits |= 2
        if (!sameAs(moved)) bits |= 64
        var removed = ["a", "c", "d"]
        reset(base); BarModel.syncEntries(lm, removed)
        if (!ops(0, 1, 0, 0)) bits |= 4
        if (!sameAs(removed)) bits |= 64
        var inserted = ["a", "e", { id: "b", x: 1 }, "c", "d"]
        reset(base); BarModel.syncEntries(lm, inserted)
        if (!ops(1, 0, 0, 0)) bits |= 8
        if (!sameAs(inserted)) bits |= 64
        var setting = ["a", { id: "b", x: 2 }, "c", "d"]
        reset(base); BarModel.syncEntries(lm, setting)
        if (!ops(0, 0, 0, 1)) bits |= 16
        if (!sameAs(setting)) bits |= 64
        var dup = ["a", "x", "a"]
        var dupNext = ["x", "a", "a"]
        reset(dup); BarModel.syncEntries(lm, dupNext)
        if (!ops(0, 0, 1, 0)) bits |= 32
        if (!sameAs(dupNext)) bits |= 64
        Qt.exit(10 + bits)
      }
    }
    QML

    probe() {
      cp "$1" BarModel.js
      timeout 60 qml probe.qml > qml.log 2>&1 && code=0 || code=$?
      if [ "$code" -lt 10 ] || [ "$code" -gt 137 ]; then
        echo "FAIL: the probe did not run (qml exit $code) for $1:"
        cat qml.log
        exit 1
      fi
      bits=$((code - 10))
    }

    # The control: a naive clear-and-append sync must fail, on the identical-list
    # case at least -- replacing everything is exactly the bug.
    {
      echo 'function entryId(entry) { return typeof entry === "string" ? entry : String(entry.id) }'
      echo 'function syncEntries(model, entries) {'
      echo '  model.clear()'
      echo '  for (var i = 0; i < entries.length; i++)'
      echo '    model.append({ slotKey: entryId(entries[i]), entryJson: JSON.stringify(entries[i]) })'
      echo '}'
    } > naive.js
    probe naive.js
    if [ $((bits & 1)) -eq 0 ]; then
      echo "FAIL: the probe no longer catches a clear-and-append sync (bits $bits)"
      exit 1
    fi
    echo "control: a clear-and-append sync touches an identical list, as it should (bits $bits)"

    # The real check: what ships.
    probe ${omarchy}/share/omarchy/shell/plugins/bar/BarModel.js
    rc=$bits
    if [ "$rc" -ne 0 ]; then
      echo "FAIL: the built syncEntries is wrong (bits $rc):"
      [ $((rc & 1)) -ne 0 ] && echo "  an identical list caused model operations (every widget would be touched)"
      [ $((rc & 2)) -ne 0 ] && echo "  a reorder was not exactly one move"
      [ $((rc & 4)) -ne 0 ] && echo "  a removal was not exactly one remove"
      [ $((rc & 8)) -ne 0 ] && echo "  an insertion was not exactly one insert"
      [ $((rc & 16)) -ne 0 ] && echo "  a settings change was not exactly one data change"
      [ $((rc & 32)) -ne 0 ] && echo "  a duplicate-id reorder was not exactly one move"
      [ $((rc & 64)) -ne 0 ] && echo "  a final order did not match the target"
      exit 1
    fi
    echo "syncEntries: all six cases produce exactly the expected operations"
    touch $out
  ''
