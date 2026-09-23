---
status: draft
issue: 847
author: olafkfreund
---

# Intent: writing shell.json while the shell runs must not break the shell

## Problem

Saving `~/.config/omarchy/shell.json` while the shell is running breaks the
shell. Not "sometimes", and not only on a bad edit: the reported repro writes
the file back **byte for byte identical** and the bar still goes blank.

Two outcomes were seen, both on razer, both needing `omarchy-restart-shell` to
recover:

- the bar empties to a single chevron, every bar IPC target answers
  `Target not found`, and the log fills with
  `TypeError: Property 'pluginBarApiFor' … is not a function`;
- Quickshell segfaults, in `IpcHandler::updateRegistration()` called from
  `IpcHandler::onPostReload()`, leaving a crash-reporter window behind.

The log says what the mechanism is, before anything crashes. One warning per
IPC target, every time:

    Handler was registered but will not be used because another handler is
    registered for target omarchy.bar

That is `omarchy.bar`, `omarchy.audio`, and the agents, bluetooth, network,
monitor, power, weather and clock panels. **The reload registers every handler
a second time rather than replacing the first**, and the crash is in the code
that reconciles those registrations.

Three things make this worth an issue rather than a footnote.

**It is reachable from the UI.** Any widget-settings change from the shell's own
settings screen writes this file. So the shell can break itself through its own
settings, with no unusual tooling involved.

**This repository's own guidance currently recommends the thing that breaks
it.** `modules/AGENTS.md:1382` says, of `shell.json`:

> The shell watches the file and reloads it, so an atomic replace is picked up
> live, with no IPC.

That sentence is written as reassurance — *you do not need IPC, just write the
file* — and it describes the exact action in the repro. Anybody following it is
being sent into this bug by our own documentation.

**We have already paid for it once and worked around it silently.** The
screencast harness (#930) restores a borrowed desktop through the shell's IPC
and never by writing `shell.json`, with a comment saying the shell rewrites that
file from memory and watches it. That workaround was arrived at during
implementation and is correct, but it is one directory's local knowledge. The
tree still tells everyone else the opposite.

## Proposed outcome

When this is done:

- **Nothing nixarchy ships writes `shell.json` under a running shell**, and the
  supported way to change it is written down in one place and is the same way
  the harness already does it.
- **`modules/AGENTS.md:1382` no longer recommends the failing path.** Whatever
  replaces it says what actually happens and what to do instead.
- **The defect is reported where it can be fixed.** The stack is entirely inside
  Quickshell; the duplicate-registration warnings are a shell-level symptom.
  Neither is nixarchy's code, and per `CLAUDE.md` §11 a fix to how a dependency
  behaves belongs upstream rather than patched here, where a local patch is
  re-applied at every source bump.
- **Something can see it.** A bug found by hand is not fixed until a probe can
  catch it (§2). At minimum a check that nothing in our tree writes that file;
  at best one that a write under a running shell is survivable, if any layer we
  have can reach a running shell.

What is explicitly *not* claimed as an outcome: that nixarchy fixes the crash.
It may not be ours to fix.

## Affected users and systems

- **Anyone using the shell's own settings UI**, which is every user of the
  desktop, not a subset with unusual tooling.
- **razer**, where it was found, during live testing of
  `nixarchy.distrobox` (olafkfreund/nixarchy-distrobox#17).
- **Quickshell 0.3.1 / Qt 6.11.2** is where the segfault is. Whether newer
  versions still do it is unknown and is an open question below.
- **`tests/demo/screencast/`**, which already routes around this, and
  **`modules/AGENTS.md`**, which currently points at it.
- Related to #710 — the same watcher, and #710 fixed the *cost* of a reload
  (one per rebuild whether or not anything changed). This is about the reload
  being **unsafe**, which is a different claim about the same mechanism, and
  #919's measurement is the counterpart: a plugin reload naming each id is
  routine and survivable, and this one is not.

## Constraints

**Must:**

- Route the upstream half correctly. `pkgs/omarchy/skills/nixarchy/contributing.md`
  governs, and the routing needs to distinguish Quickshell from Omarchy: the
  crash is in Quickshell's IPC code, the double registration may be either.
- Leave the existing `omarchy-restart-shell` recovery working and documented;
  it is the only thing that recovers today.
- Prove any check fails before trusting it (§1), and say plainly which layer
  can and cannot reach a running shell (§3) rather than closing the hole on
  paper.

**Must not:**

- Carry a patch to Quickshell or to Omarchy's shell in this tree to paper over
  it, unless a human decides the exposure justifies the per-bump cost.
- File anything in anyone else's repository unprompted (§11).
- Change any user-visible default while investigating.

## Open questions

These are the approver's to decide, and the first two change the shape of
everything after them.

1. **Scope.** Is this issue (a) document the hazard and make our own tree
   safe, and report upstream; (b) that, plus a supported writer command in
   nixarchy that does the stop/write/relaunch dance; or (c) also attempt a
   local mitigation in the vendored shell? My recommendation is (a), with (b)
   only if something we ship actually needs to write the file — and right now
   I do not think anything does, which is worth confirming before building a
   command for it.

2. **Is the `OMARCHY_PATH` mismatch a cause or a coincidence?** The issue notes
   the owner's login environment held a *newer* `OMARCHY_PATH` than the running
   shell, because the shell had not been restarted after a rebuild, and says
   "that may matter". #930 hit the same mismatch from the other side and it was
   load-bearing there. If it is a precondition, the bug is narrower than it
   looks and the advice changes. Determining this needs one controlled repro
   on real hardware and should probably come **before** the spec rather than
   inside it.

3. **Does it still reproduce on current Quickshell?** The report is 0.3.1 /
   Qt 6.11.2. If a newer Quickshell has fixed it, the whole upstream half
   collapses into a version bump and the outcome above is mostly documentation.

4. **Is a whole-desktop VM check worth building for this?** `checks.session`
   boots a real desktop, so a write-under-a-running-shell test may be reachable
   there — but it is a ~10–20 minute check and nothing in CI currently builds
   anything in `tests/demo/`. Cheap answer: a static check that nothing in the
   tree writes `shell.json`. Expensive answer: the real thing. Worth deciding
   deliberately rather than defaulting to the cheap one because it is cheap.
