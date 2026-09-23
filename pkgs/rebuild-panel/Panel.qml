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

    // The three buttons, so a check can press what a person presses (#896).
    // They call the same RebuildState methods RebuildView's buttons call and
    // nothing else, so there is no second path to start a rebuild down.
    function rebuild(): void { RebuildState.start() }
    function copyLog(): void { RebuildState.copyLog() }
    function openLog(): void { RebuildState.openInTerminal() }
  }

  // ------------------------------------------------------------------- bar

  implicitWidth: button.visible ? button.implicitWidth : 0
  implicitHeight: button.implicitHeight

  // A settled result the user has not looked at yet. Applying from a panel
  // closes that panel -- the shell reloads every plugin when activation
  // rewrites a plugin link (#710, and modules/AGENTS.md) -- so the thing that
  // was going to print "applied" is gone before it can (#919). This is what is
  // left on screen afterwards, and it is why success has to linger: failure
  // already did, success did not, and success is what the user is waiting for.
  //
  // Acknowledged by OPENING it: no new verb, no dismiss button, and the
  // acknowledgement is keyed on the run rather than on the state, so a second
  // apply reporting the same "succeeded" still draws.
  property double acknowledgedRun: 0
  readonly property bool settled: RebuildState.state === "succeeded"
                                  || RebuildState.state === "failed"
  readonly property bool unreadResult:
    RebuildState.state === "succeeded" && RebuildState.finishedUsec > 0
    && RebuildState.finishedUsec !== root.acknowledgedRun

  onOpenedChanged: function () {
    if (root.opened && root.settled) root.acknowledgedRun = RebuildState.finishedUsec
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: ""
    // Failure keeps behaving exactly as it did: visible until the state
    // changes, never dismissed. A machine that did not rebuild should go on
    // saying so. Only SUCCESS is the acknowledgeable one, because it is the
    // one that had no indicator at all.
    visible: RebuildState.active || root.opened
             || RebuildState.state === "failed" || root.unreadResult
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
