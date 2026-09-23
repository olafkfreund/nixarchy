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

## Open questions — answered (2026-09-24)

The owner set the scope and asked for the other three to be investigated
before the spec. All four are now settled, and two of the answers change what
the spec has to say.

**1. Scope: (a).** Document the hazard, make our own tree safe, and report
upstream. No writer command, no local patch to the vendored shell.

**2. The `OMARCHY_PATH` mismatch is a red herring. The bug does not need it.**

Reproduced on razer under the *control* condition — the running shell and the
login environment on the same tree,
`wlbf63znxqwjyjhkv1mv9na2zyhx582z-nixarchy-omarchy-tree`, verified before
touching anything. Writing the file back byte for byte (both hashes
`b0adf5cc6221a0f0`) produced, within four seconds:

    omarchy.bar        Function not found.
    omarchy.clock      Target not found.
    omarchy.network    Target not found.

    WARN: QQmlVMEMetaObject: Internal error - attempted to evaluate a
          function in an invalid context
    WARN scene: @plugins/bar/Bar.qml[2008:-1]: TypeError: Property
          'pluginBarApiFor' … is not a function

61 `invalid context` errors in the following minute. `omarchy-restart-shell`
recovered it and `shell.json` was byte-identical to the backup throughout.

So the issue's "that may matter" is answered: **it does not**. The bug is
general, which makes it worse than the report implied — every user of the
settings UI is exposed, not only someone whose session predates a rebuild.

One thing did *not* reproduce: **the segfault.** The shell PID was unchanged
across the whole run, and nothing in the journal mentions a signal. Variant 1
(the bar breaking) is reliable; variant 2 (the crash in
`IpcHandler::updateRegistration`) needs some further condition we have not
identified. The spec should not claim otherwise.

**3. There is no version to upgrade to, and the obvious upstream fix is
already in.**

`v0.3.1` is the latest upstream tag — there is nothing newer to bump to, and
razer runs it. The one commit on master that looks like this bug,
`28771c7c74b4` *"ipc: ensure handler deregistration upon destruction"*
(2026-08-02), is **already an ancestor of the tag**: `v0.3.1` (2026-08-21) is
11 commits ahead of it and 0 behind.

That is the single most useful thing found here. The duplicate-registration
warnings look exactly like a deregistration bug, so the natural upstream
report is "this was fixed in 28771c7c, please release it" — and that report
would be wrong. The honest one is that 0.3.1 *contains* that fix and still
does this, which is a different and more valuable bug report.

**4. A VM can reach a running shell, so the expensive check is not
hypothetical.**

`checks.session` boots a real desktop and asserts on `pgrep -a quickshell`;
`checks.plugin` already waits for `shell.json` to be written *by a live shell*
(`tests/plugin.nix:656`) and reads it back. So "write the file under a running
shell and assert the bar survives" is reachable at a layer we already own —
better than the intent first guessed.

The cheap check is also worth having, and would guard a claim the tree already
makes in three places: `modules/home.nix:315` "nothing here writes
shell.json", `:673` "it never edits your shell.json", and `:1749` "the shell
rewrites that whole file from memory, so a second writer loses updates".
Nothing in our tree writes it today, so that check starts green — and per §1 it
is only worth adding if it can be made to fail, which for a grep-shaped
assertion means adding a writer and watching it go red.

Both, then: the static one because it is seconds and guards a stated
invariant, and the VM one because it is the only thing that can see the actual
defect.
