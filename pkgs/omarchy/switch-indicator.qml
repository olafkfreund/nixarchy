import QtQuick
import Quickshell.Io
import qs.Ui

// A bar indicator that spins while the system is being switched.
//
// Upstream has no equivalent because on Arch a package install is over in
// seconds and prints to the terminal it was typed in. Here the Install menu's
// "Apply changes" runs `nh os switch`, which can take minutes, and until it
// finishes there is nothing on screen to say the machine is doing anything at
// all -- someone who picked an app from the menu is left with a desktop that
// looks idle and an app that has not appeared. This is that missing signal.
//
// Modelled on ScreenRecording.qml, which is the same shape: a transient
// indicator that polls for a process and shows itself while it is running.
BarIndicator {
  id: root

  property bool switching: false
  property int frame: 0

  // Material Design's circle slices, in Nerd Fonts' private use area, which is
  // the font the rest of the bar's glyphs already come from. Eight frames of a
  // filling pie: a spinner that is legibly a spinner at bar size, where a
  // rotating single glyph mostly reads as a smudge.
  readonly property var frames: ["󰪞", "󰪟", "󰪠", "󰪡", "󰪢", "󰪣", "󰪤", "󰪥"]

  active: switching
  activeText: frames[frame % frames.length]
  // The inactive glyph is never drawn -- BarIndicator hides an indicator that
  // is not active unless the bar is revealing them -- but it has to be a
  // constant, or the hidden slot changes width as the animation runs.
  inactiveText: "󰪥"
  activeTooltipText: "Rebuilding the system..."
  inactiveTooltipText: "System rebuild"

  // Whether anything is switching the system right now.
  //
  // Deliberately not a state file written by nixarchy-apply: a rebuild the
  // user typed themselves is exactly as worth showing as one the menu started,
  // and a file only knows about the second. pgrep knows about both.
  //
  // ponytail: a cmdline match, so an editor holding a file called
  // nixos-rebuild.md in its arguments will light this up. Cheap, and wrong in
  // the harmless direction -- it over-reports rather than staying dark while
  // the machine is busy, which is the failure that matters.
  function refresh() {
    if (!root.bar || statusProc.running) return;
    statusProc.command = ["pgrep", "-f",
      "nixos-rebuild|nixarchy-apply|switch-to-configuration|(^|/)nh( |$)"];
    statusProc.running = true;
  }

  onBarChanged: refresh()
  Component.onCompleted: refresh()

  Connections {
    target: root.indicatorHost
    ignoreUnknownSignals: true
    function onRefreshRequested() {
      root.refresh();
    }
  }

  Process {
    id: statusProc
    onExited: function (exitCode) {
      root.switching = exitCode === 0;
    }
  }

  // Two rates, because they answer different questions. The slow one asks
  // whether a rebuild has started, and runs forever; polling for that faster
  // would spawn a pgrep every second for the whole life of the session to
  // catch something that happens a few times a day. The fast one only runs
  // while a rebuild is in flight and only turns the animation.
  Timer {
    interval: 3000
    repeat: true
    running: true
    onTriggered: root.refresh()
  }

  Timer {
    interval: 125
    repeat: true
    running: root.switching
    onTriggered: root.frame = root.frame + 1
  }

  // Clicking it shows what is happening, rather than offering to stop it: a
  // half-applied switch is a worse place to be than a slow one, and nothing
  // here can safely interrupt an activation.
  onPressed: function () {
    if (root.bar)
      root.bar.run("omarchy-launch-floating-terminal-with-presentation journalctl -f -u nix-daemon.service");
  }
}
