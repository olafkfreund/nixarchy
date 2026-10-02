---
status: approved
issue: 1155
author: olafkfreund
---

# Intent: a plugin change rebuilds only the panels it changed

## Problem

The shell rebuilds **every** plugin panel, menu and overlay whenever the set
of plugins changes, even when only one plugin changed.

`shell/shell.qml` in v4.0.4 hands the panel `Instantiator` a new JS array on
each change (`shell.panelEntries = shell.computePanelEntries()`, in
`onPluginsChanged` and after a reload). QML cannot compare two arrays, so it
destroys every delegate and creates it again.

nixarchy already carries a partial fix, part B of the #901 patch
(`pkgs/omarchy/default.nix:1887-1961`, reasoning in `pkgs/AGENTS.md:705-718`).
It skips the reassignment when the new list is identical, which cured the
28–75 s bar freeze on a layout-only save. Any *real* change still rebuilds
everything:

- **at startup,** plugins register one after another, so the list changes
  several times in the first second and each change rebuilds every panel
  again;
- **on every rescan,** because the patch compares manifests by object
  identity and a rescan always produces new objects.

While a keep-loaded panel from the previous rebuild is still loading, the next
rebuild starts another copy. Both register the same IPC handler.

**Seen on p620, 2026-10-02:**

- 16,356 `another handler is registered` warnings in the user journal over
  seven days;
- 62 more after a single shell restart at 08:20, including the
  `nixarchy.podman`, `nixarchy.microvm` and `nixarchy.devenv` `Panel.qml`
  five times each.

Upstream found the same thing from the OSD side and fixed it on `quattro` in
omacom/omarchy@0066ea216b (#13439, 2026-09-27). It reported a duplicate OSD in
1 of 5 busy-machine runs before the fix and 0 of 10 after. That commit is not
in v4.0.4.

## Proposed outcome

- **Startup:** each panel is created once. The journal after a shell restart
  shows no `another handler is registered` line for any `Panel.qml`, or for
  any other keep-loaded entry point that only one plugin registers.
- **Enabling, disabling or adding one plugin** creates or destroys that
  plugin's panel only. Every other panel keeps its loader and its state.
- **A full plugin reload** (`rescanPlugins`, a local plugin edit) still
  rebuilds every panel from fresh code, as it does today.
- **Layout-only saves** stay as cheap as #901 made them.

## Affected users and systems

- Every nixarchy desktop: the vendored `shell/shell.qml`, through
  `pkgs/omarchy/default.nix`.
- `pkgs/AGENTS.md`'s #901 section, whose part B this replaces.
- `checks.session` and any check that reads `shell.qml`'s patched text, such
  as the #901 checks, if they exist.

## Constraints

- **Carry upstream's change, do not write a third version.** The `quattro`
  bump should delete our copy, not conflict with it. Keep part A of #901 (the
  enabled-set signature in `onShellConfigChanged`), which upstream's commit
  does not cover.
- **`--replace-fail` or `--fuzz=0`,** so a v4.0.x bump that rewords the
  anchor fails the build (`pkgs/AGENTS.md`, "Patching upstream").
- **No posting upstream:** it is already fixed there.
- **Under AGENTS.md §2, the duplicate registration must be visible to a
  check,** not only to a human reading the journal.
- **It must not collide with #1153** (the owe backport), which patches
  `shell.qml` too (+4 lines for the service registry). Whichever lands second
  rebases, and its anchors must still hold.

## Open questions

1. **Which check sees it?** The candidates are a `checks.session` assertion
   that a shell restart logs no duplicate handler for a panel, and a cheap
   static check on the patched `shell.qml`, like upstream's
   `panel-entries-test.sh`. The first sees the symptom and the second only the
   text. The proposal is both, with the session assertion as the one that
   counts.
2. **#958, the IpcHandler segfault.** It crashed in the same registration
   path. Should this task also try to reproduce #958 and show whether it is
   gone, or leave #958 closed as it is and only note the link?

## Owner's approval (2026-10-02)

Approved without answers to the two open questions. The spec proposes one
for each, and the spec approval settles them.
