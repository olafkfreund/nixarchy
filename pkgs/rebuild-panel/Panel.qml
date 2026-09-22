import QtQuick
import Quickshell
import Quickshell.Io
import qs.Ui
import qs.Commons

// The bar widget, and the panel under it.
//
// The widget draws nothing unless a rebuild is running (or the panel is open):
// a permanent icon for something that happens a few times a week is clutter,
// and the bar already has SystemSwitch for "something is rebuilding". It still
// has to be IN the bar, because that is the only thing `omarchy-shell shell
// toggle` can summon -- Bar.qml's summonBarWidget resolves the id against the
// instantiated widgets. nixarchy.distrobox's hideWhenEmpty does the same.
Panel {
  id: root

  moduleName: "nixarchy.rebuild"
  ipcTarget: "nixarchy.rebuild.bar"
  manageIpc: false

  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  Component.onCompleted: RebuildState.acquire()
  Component.onDestruction: RebuildState.release()

  IpcHandler {
    target: root.ipcTarget

    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.toggle() }
    function status(): string {
      return JSON.stringify({ state: RebuildState.state, exit: RebuildState.exitCode })
    }
  }

  // ------------------------------------------------------------------- bar

  implicitWidth: button.visible ? button.implicitWidth : 0
  implicitHeight: button.implicitHeight

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: ""
    visible: RebuildState.active || root.opened || RebuildState.state === "failed"
    active: RebuildState.active
    useActiveColor: true
    activeColor: RebuildState.state === "failed" ? Color.urgent : Color.accent
    tooltipText: "Rebuild · " + RebuildState.state
    // The signal carries which button; the panel treats them all alike.
    onPressed: function (b) { root.toggle() }
  }

  // ----------------------------------------------------------------- panel

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: view.keyTarget
    contentWidth: panel.fittedContentWidth(Style.space(520))
    contentHeight: panel.fittedContentHeight(view.implicitHeight)

    RebuildView {
      id: view
      anchors.fill: parent
      foreground: root.foreground
      fontFamily: root.fontFamily
      onCloseRequested: root.close()
      onSwitchPanelRequested: function (direction) { root.switchPanel(direction) }
    }
  }
}
