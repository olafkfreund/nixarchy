import QtQuick
import qs.Ui
import qs.Commons

// What the panel shows: the offer before anything is built, then the rebuild
// as it runs, then what it left behind.
//
// Apply asks here rather than switching on the click. Install > Apply has
// always offered a VM preview and then asked "Build and switch now?"; opening
// a panel must not quietly turn that into a one-click irreversible switch.
FocusScope {
  id: root

  property color foreground: Color.foreground
  property string fontFamily: Style.font.family
  readonly property color dim: Qt.darker(foreground, 1.5)
  readonly property Item keyTarget: root

  signal closeRequested()
  signal switchPanelRequested(int direction)

  implicitHeight: column.implicitHeight

  function elapsedText() {
    var s = RebuildState.elapsedSec
    if (s < 60) return s + "s"
    return Math.floor(s / 60) + "m " + (s % 60) + "s"
  }

  // The arithmetic is in nixarchy-rebuild-state, not here: nothing in this
  // suite drives QML, so logic left in a panel ships untested (#765 PR 5).
  // This only formats what that command already decided.
  function agoText(): string {
    var s = RebuildState.finishedAgoSec
    if (s < 0) return ""
    if (s < 90) return " · just now"
    if (s < 5400) return " · " + Math.round(s / 60) + " min ago"
    return " · " + Math.round(s / 3600) + " h ago"
  }

  Keys.onPressed: function (event) {
    if (event.key === Qt.Key_Escape) { root.closeRequested(); event.accepted = true }
    // No key starts a rebuild: the button is deliberately the only way in, and
    // a stray keypress over a panel must never switch the machine.
  }

  Column {
    id: column
    width: parent.width
    spacing: Style.spacing.md

    PanelSectionHeader {
      width: parent.width
      text: RebuildState.state === "running" ? "Rebuilding · " + root.elapsedText()
        : RebuildState.state === "failed" ? "The rebuild failed (exit " + RebuildState.exitCode + ")" + root.agoText()
        : RebuildState.state === "succeeded" ? "Rebuild finished" + root.agoText()
        : "Apply changes"
    }

    Text {
      width: parent.width
      wrapMode: Text.WordWrap
      color: root.dim
      font.family: root.fontFamily
      visible: RebuildState.state === "idle"
      text: "Copies the selection into your flake and rebuilds the machine. "
        + "You will be asked for your password once, in the usual dialog. "
        + "It keeps running if you close this."
    }

    // The last line the build printed. nh's progress view is drawn with escape
    // codes that mean nothing here, so this is a step in the honest sense:
    // the most recent thing it said.
    Text {
      width: parent.width
      elide: Text.ElideRight
      color: root.foreground
      font.family: root.fontFamily
      visible: RebuildState.active && text.length > 0
      text: RebuildState.lastLine
    }

    ListView {
      id: log
      width: parent.width
      height: Math.min(contentHeight, Style.space(300))
      visible: RebuildState.lines.length > 0
      clip: true
      model: RebuildState.lines
      // Follows the end. There is no scroll-to-stop-following here: the full
      // log in a terminal is the place to read back, and it is one button away.
      onCountChanged: positionViewAtEnd()

      delegate: Text {
        width: log.width
        elide: Text.ElideRight
        color: root.dim
        font.family: root.fontFamily
        text: modelData
      }
    }

    Row {
      spacing: Style.spacing.sm

      Button {
        text: "Rebuild now"
        bordered: true
        focusable: true
        visible: RebuildState.state === "idle" || RebuildState.state === "succeeded"
        onClicked: RebuildState.start()
      }
      Button {
        text: "Copy log"
        visible: RebuildState.state === "failed"
        onClicked: RebuildState.copyLog()
      }
      Button {
        text: "Open full log in terminal"
        visible: RebuildState.state === "failed" || RebuildState.active
        onClicked: RebuildState.openInTerminal()
      }
    }

    Text {
      width: parent.width
      wrapMode: Text.WordWrap
      color: root.dim
      font.family: root.fontFamily
      visible: RebuildState.active
      // Why there is no cancel button: stopping the unit sends SIGTERM to nh,
      // which can land mid-activation. That must not be one keypress away.
      text: "Closing this does not stop the rebuild. Once the log reaches "
        + "\"Activating\", do not stop it by hand -- let it finish and roll back after."
    }
  }
}
