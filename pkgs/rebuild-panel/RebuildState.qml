pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// Everything the panel knows about the rebuild. Nothing here draws.
//
// There is no state of our own: the nixarchy-rebuild user unit is the single
// source of truth, which is what lets the panel be closed, reopened, or opened
// on a rebuild somebody started from a terminal. Closing the panel detaches;
// it never stops anything.
Singleton {
  id: root

  // idle | running | succeeded | failed, straight from nixarchy-rebuild-state.
  // The mapping lives in that command, not here, so it can be tested without a
  // desktop (tests/apply-staging.nix).
  property string state: "idle"
  property int exitCode: 0
  readonly property bool active: root.state === "running"

  // How long ago the run this state describes finished, in seconds, straight
  // from nixarchy-rebuild-state (#919). The unit outlives the session -- #765
  // omits --collect -- so a settled result has to say WHICH run it describes,
  // or the bar claims a fresh success at every login. -1 is "cannot say":
  // never ran, still running, or it finished before this boot.
  property int finishedAgoSec: -1

  // A stable id for the run the state describes -- systemd's monotonic finish
  // timestamp. The bar keys "already seen" on this, NOT on finishedAgoSec,
  // which grows with every poll and would never compare equal.
  property double finishedUsec: 0

  property var lines: []
  property double startedAt: 0
  property int elapsedSec: 0

  // One viewer is the panel; the bar widget polls in the background so the
  // icon can appear without anyone having opened anything.
  property int viewers: 0

  readonly property string unit: "nixarchy-rebuild"

  // The last line the build printed, which is the closest thing to a step
  // nh gives us without parsing its progress view.
  readonly property string lastLine: lines.length > 0 ? lines[lines.length - 1] : ""

  function acquire() { root.viewers += 1; root.poll() }
  function release() { root.viewers = Math.max(0, root.viewers - 1) }

  function poll() {
    if (stateProcess.running) return
    stateProcess.running = true
  }

  function start() {
    if (root.active || startProcess.running) return
    root.lines = []
    root.exitCode = 0
    startProcess.running = true
  }

  // The whole log, for Copy log -- not the capped tail the panel shows.
  function copyLog() {
    if (copyProcess.running) return
    copyProcess.running = true
  }

  function openInTerminal() {
    terminalProcess.running = true
  }

  function appendLog(line) {
    var next = root.lines.slice()
    next.push(line)
    // Capped for the reason the distrobox panel caps its own log: a nix build
    // log is unbounded, and a model that grows with it takes the shell down
    // with it. The full log is one button away.
    if (next.length > 500) next = next.slice(next.length - 500)
    root.lines = next
  }

  onStateChanged: {
    if (root.state === "running") {
      if (root.startedAt === 0) root.startedAt = Date.now()
      if (!followProcess.running) followProcess.running = true
    } else {
      root.startedAt = 0
      root.elapsedSec = 0
    }
  }

  Process {
    id: stateProcess
    command: ["nixarchy-rebuild-state"]
    stdout: StdioCollector { id: stateOut; waitForEnd: true }
    onExited: function (code) {
      if (code !== 0) return
      try {
        var parsed = JSON.parse(stateOut.text)
        root.state = String(parsed.state)
        root.exitCode = Number(parsed.exit)
        root.finishedAgoSec = Number(parsed.finishedAgoSec)
        root.finishedUsec = Number(parsed.finishedUsec || 0)
      } catch (e) {
        // A malformed answer is not a state. Keep the last one we believed
        // rather than flicking the panel to idle under a running build.
        console.warn("nixarchy.rebuild: could not read the unit's state:", e)
      }
    }
  }

  // Started detached, so this process exits at once and the rebuild outlives
  // the panel. --yes because a unit has no stdin to answer a question with.
  Process {
    id: startProcess
    command: ["nixarchy-apply", "--detach", "--yes"]
    onExited: function () { root.poll() }
  }

  // -o cat: the journal's own prefixes are noise next to a build log, and the
  // identifier is already known. -n seeds the view on a rebuild that was
  // already running when the panel opened.
  Process {
    id: followProcess
    command: ["journalctl", "--user", "-u", root.unit, "-o", "cat", "-n", "500", "-f"]
    stdout: SplitParser { onRead: function (line) { root.appendLog(line) } }
    stderr: SplitParser { onRead: function (line) { root.appendLog(line) } }
  }

  Process {
    id: copyProcess
    command: ["sh", "-c", "journalctl --user -u " + root.unit + " -o cat | wl-copy"]
  }

  Process {
    id: terminalProcess
    command: ["omarchy-launch-floating-terminal-with-presentation",
              "journalctl", "--user", "-u", root.unit, "-o", "cat", "-f"]
  }

  // Polls while anything is looking, and keeps a slow beat otherwise so the
  // icon can appear for a rebuild this panel did not start.
  Timer {
    interval: root.viewers > 0 ? 1000 : 5000
    running: true
    repeat: true
    onTriggered: {
      root.poll()
      if (root.active && root.startedAt > 0)
        root.elapsedSec = Math.floor((Date.now() - root.startedAt) / 1000)
    }
  }
}
