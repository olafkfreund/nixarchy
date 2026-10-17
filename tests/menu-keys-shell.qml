// #1305 harness: loads the real menu plugin into a headless Quickshell, sends
// keys with QtTest, and answers over IPC. Only tests/menu-keys.sh uses it.
import Quickshell
import Quickshell.Io
import QtQuick
import QtTest
ShellRoot {
  id: r
  property var menu: null
  property string loadError: ""
  TestCase { id: tc; when: false; name: "menu-keys" }
  Component.onCompleted: {
    var c = Qt.createComponent("plugins/menu/Menu.qml")
    if (c.status !== Component.Ready) { loadError = c.errorString(); console.log("menu-keys: " + loadError); return }
    menu = c.createObject(r)
  }
  IpcHandler {
    target: "probe"
    function state(): string {
      if (!r.menu) return JSON.stringify({ error: r.loadError || "menu not created" })
      return JSON.stringify({ opened: r.menu.opened, active: r.menu.activeMenu, rows: Object.keys(r.menu.items || {}).length })
    }
    function open(payload: string): string { return String(r.menu.open(payload)) }
    function key(k: int): string { tc.keyClick(k); return "sent" }
    function sel(i: int): string { r.menu.cursorActive = true; r.menu.selectedIndex = i; return "ok" }
    function nocursor(): string { r.menu.cursorActive = false; return "ok" }
  }
}
