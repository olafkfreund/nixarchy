---
status: approved
issue: 1313
author: olafkfreund
---

# Intent: Enabling nixarchy-menu must not crash the shell

## Problem

Choosing Setup › Defaults › Menu › Nixarchy can segfault Quickshell, the
process that runs the whole Omarchy shell (bar, menu, notifications). The
shell restarts itself, so a user sees the desktop flicker and lose state,
and on the session check the restarted shell has not reloaded its plugins
yet.

It is not hypothetical:

- `checks.session` crashed on three PR heads today (#1305's `5a69fb95`,
  #1302's `193c7d13` and #1304 part 2's `d9f8719c`), on GitHub-hosted
  runners, each with its own VM. Every run that crashed logs a `preload`
  binding loop on nixarchy-menu's two `FileView`s first, and no passing run
  does.
- `main` passed three times and #1303 passed, so which trees crash depends
  on content. Nothing in any of the three diffs is shared. #1305's tree
  changes nothing nixarchy-menu reads; it changes only the stock menu plugin
  that nixarchy-menu replaces.
- A diagnostic VM run on #1307's head captured Quickshell's own crash
  report: SIGSEGV in `QQmlConnections::connectSignalsToMethods` ←
  `QQmlConnections::setTarget`, reached from a signal handler that runs
  **during** the asynchronous incubation of nixarchy-menu's own panel
  (`QsIncubationController::incubate`). The `Connections` whose target moves
  is nixarchy-menu's `providers/Applications.qml:32`,
  `Connections { target: root.library }`.

Two routes into that retarget have been seen:
1. `core/ApplicationLibrary.qml`'s fallback Loader creating Omarchy's
   `AppLibrary.qml` mid-incubation;
2. the scoped shell API arriving mid-incubation.

Deferring only route 1 passed once and crashed on the next run. The defect
is a `Connections` being retargeted before its component has finished
incubating, which Qt 6.11 does not survive. Plugin-registry timing decides
whether `library` changes inside that window, and the stock menu plugin's
unload in the same `syncPanelEntries` pass shifts that timing. That is why
unrelated PRs flip it.

**What lets it ship.** The #1283 probe that found it reads
`omarchy-plugin-list` and retries for 60 s. When Quickshell restarts fast
enough, the probe reads the restarted shell and passes over the crash. One
diagnostic run did exactly that: the SEGV was logged and the probe passed,
and the run failed later for an unrelated reason. So the check can wave a
segfault through. It caught today's crashes only because the restart was
slow.

Not the cause (ruled out with evidence): nixarchy-menu's input (it imports
the raw upstream `MenuModel.js` through its own flake), p620's load (the
check runs on hosted runners), #847's `IpcHandler` path (nixarchy-menu has no
`IpcHandler`), and Quickshell's `FileView` (the binding loop is a sibling
symptom of the same nested incubation).

## Proposed outcome

- Enabling, and disabling, nixarchy-menu never crashes the shell, whatever
  the menu data or the stock menu plugin's code is.
- `checks.session` fails whenever Quickshell dumps core during the session,
  not only when a plugin list looks wrong afterwards. A shell that crashed
  and recovered is a failure.
- #1307, #1311 and #1312 can merge on a green check that means something.

## Affected users and systems

- Anyone who turns nixarchy-menu on. It is installed and off by default
  (#1283), so users who never choose it are unaffected.
- `tests/session.nix`, the probe.
- The nixarchy-menu plugin: either its repository
  (`github:olafkfreund/nixarchy-menu`, pinned in `flake.nix`) or the
  `applyPatches` postPatch this repo already applies to it in
  `modules/home.nix`.
- Possibly `shell/shell.qml`'s plugin panel Loader, if the fix is made
  there instead.

## Constraints

- **The probe is strengthened, never loosened** (owner's decision). It must
  not pass by waiting for a crashed shell to come back.
- **Proof needs repetition (§1, §3).** The crash is input- and
  timing-sensitive: one pass proves nothing. The fix is shown with several
  VM runs per arm, patched and unpatched, with segfault counts rather than
  the probe's verdict. VM runs happen only when CI is idle (§6).
- **Upstream routing (§11).** The defect is in nixarchy-menu's QML, which is
  the owner's own repository. A Quickshell or Qt patch is out unless the
  evidence points there, and #847 recorded the owner's decision not to report
  to Quickshell.
- **Do not change #1302, #1304 or #1305's content to dodge it.** The crash
  is latent; those changes only move the timing.
- Mode A is untouched: nothing changes for a user who has not chosen
  nixarchy-menu.

## Open questions

1. **Where does the fix live?** (a) In the nixarchy-menu repository, plus a
   pin bump here: the real home of the bug, but a change in another repo.
   (b) As a carried patch through `modules/home.nix`'s existing
   `applyPatches` on the plugin: no outside change, and it unblocks the PRs
   sooner, then drops when the repo is fixed. (c) Make the shell's plugin
   panel Loaders synchronous (`shell.qml`, a carried Omarchy patch): it
   closes the window for every plugin, but may stall the shell while each
   plugin loads (#901).
2. **How many runs per arm are enough?** The unpatched crash rate is not yet
   measured. A 3+3 loop is running now, and its result decides the number.
3. **Should the core-dump probe cover the whole session or only the menu
   switch?** A session-wide "no Quickshell core" assertion would also catch
   crashes elsewhere, which is wider but may surface unrelated, pre-existing
   crashes.
