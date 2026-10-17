---
status: approved
issue: 1313
intent: intent/2026-10-17-1313-nixarchy-menu-connections-crash.md
---

# Spec: Enabling nixarchy-menu must not crash the shell

Revision 2. Revision 1 was approved and then reviewed by a fresh Opus agent.
That review found D1 broke the intent's Mode A constraint, and that D2's
coredump half had never worked. The owner chose to narrow D1 to nixarchy-menu.
Everything else changed here corrects a factual error the review found.

## Design

### D1. nixarchy-menu's panel loads synchronously (intent option c, narrowed)

The crash is a `Connections` in nixarchy-menu being retargeted while the
plugin's panel is still being incubated asynchronously. `shell/shell.qml`'s
per-plugin `panelLoader` has `asynchronous: true` (line 1405 on 4.0.4).
nixarchy-menu is a `keepLoaded` panel, so it is created the moment it is
enabled, in the same `syncPanelEntries` pass that tears down the stock menu.

One substitution in `pkgs/omarchy/default.nix`, beside the other carried
shell edits:

```
asynchronous: true  →  asynchronous: panelEntry.pluginId !== "nixarchy.menu"
```

The anchor is two lines: the loader's `active: … openPanelIds …` line and the
`asynchronous: true` under it. `--replace-fail` replaces every match without
complaint, so a single-line anchor would also rewrite a future
`asynchronous: true` elsewhere in the file. There it would bind `panelEntry`
out of scope. The two-line anchor matches once.

With the loader synchronous, nixarchy-menu is created in one step, outside any
incubation. Its inner loaders were already synchronous:
`core/ApplicationLibrary.qml:24`'s fallback, and `Registry.qml:133` with
`PreferSynchronous`. They ran nested only because the outer load was
asynchronous. `onLoaded` assigns `shell` after creation finishes, so the
retarget now happens after incubation.

`keepLoaded` and `pluginId` are required properties of the delegate, and
`syncPanelEntries` replaces a row rather than editing it. So `asynchronous`
cannot flip partway through a load.

Every other plugin keeps its asynchronous load. That covers the stock
keepLoaded panels (clipboard, emojis, image-picker, menu, osd and reminders)
and every on-demand panel. This keeps the intent's Mode A constraint: nothing
changes for a user who has not chosen nixarchy-menu. That is the owner's
decision of 2026-10-17. The cost is that a future keepLoaded plugin with the
same pattern is not protected. The pkgs/AGENTS.md section says so.

Why the shell's loader, not nixarchy-menu itself (options a and b): fix (a),
inside nixarchy-menu, gated the `Connections` target on `ready` and deferred
the fallback Loader with `Qt.callLater`. It still crashed one run in three
(`loop-results.txt`, patched-1). The intent lists two routes into the
retarget, and fix (a) closed one. Fix (b) took the shell route, for every
keepLoaded panel, and had two clean runs in two (`b-results.txt`). D1 is fix
(b) narrowed, so it gets its own runs (Verification 1).

A short note at the substitution names #1313 and points to
`pkgs/AGENTS.md#nixarchy-menu-loads-synchronously-1313`, which carries the
backtrace, the two routes, the measurements and the drop condition. It
drops when nixarchy-menu survives an asynchronous load: the follow-up below,
proven with the same runs.

**Follow-ups, neither of them done by this change:**
- nixarchy-menu's own `Connections` is fragile. It gets an issue in its
  repository (the owner's), with fix (a)'s diff and the backtrace as
  evidence.
- Whether to tell omacom/omarchy is the owner's call (§11). The defect is in
  nixarchy-menu, not upstream's code, and D1 carries no upstream fix. So the
  default is not to report, and the PR asks.

### D2. The session check fails on any Quickshell crash

`tests/session.nix`, in the #1283 menu-switch probe. Checked right after
`click("setup.default.menu.nixarchy")` and `menus()`, and again at the end of
the test script. Either of these fails the check, with the matching lines
and the crash report's first lines:

- **The boot journal.** `journalctl -b -o cat` has either a `systemd-coredump`
  line matching `(.quickshell-wra) … terminated abnormally` (note the leading
  dot), or an omarchy-shell `Quickshell has crashed` line. Both are written at
  the moment of the crash (`vm-run2.clean.log:3234`, `:3238`), so there is
  no race. A `journalctl` that errors fails the check; it never reads as "no
  crash" (§4).
- **The crash directory.** `/home/omarchy/.cache/quickshell/crashes` is
  empty or absent.

The failure message is `#1313: Quickshell crashed during the session`.

`coredumpctl` is not used. In the only crash it was run against, it printed
`No coredumps found` while systemd-coredump was still writing 798 MB. The
store then filled, and it ended `terminated abnormally without generating a
coredump` (`vm-run2.clean.log:3259-3284`). A stored core is not the
property; the crash is.

This answers the intent's question 3: **the whole session, checked twice.**
The journal and the crash directory are both cumulative for the boot. The
check at the switch points at the switch when that is where it crashed. The
check at the end catches a crash anywhere else, including on the switch back
(disabling nixarchy-menu). No passing run so far has any of these lines
(b-1, b-2, fix (a)'s passing runs). If one turns up later, it is a real crash
and gets its own issue, not an allowlist entry.

The probe's existing assertion, that the switch leaves `nixarchy.menu=True
omarchy.menu=False`, stays exactly as it is. Its 60 s retry also stays: that
retry is what let a crashed-and-restarted shell pass, and the new assertion
makes it harmless (owner's decision: strengthen, never loosen).

### D3. Timing is printed, not asserted

The probe prints `#1313 timing: row Xs, plugin-list answered Ys after it`.
That is the measurement the stall question needs, and it keeps landing in
every CI log. It is not an assertion and not a pass condition anywhere:
a hosted runner's speed varies too much for a bound that never flakes, and
§10 forbids retrying until green.

## Alternatives rejected

- **Every keepLoaded panel synchronous (fix (b) as measured).** It breaks
  the Mode A constraint: six stock panels would change how they load for
  every Omarchy-shell user. The owner chose the narrow version.
- **(a) Fix nixarchy-menu's `Connections` in its repository, then bump the
  pin.** Measured insufficient: 1 crash in 3 runs. It is still worth doing,
  as the follow-up above.
- **(b) Carry fix (a) as a postPatch on the plugin.** Same fix, same
  measurement, and a patch in another project's tree.
- **Every panel Loader synchronous.** On-demand panels are created on a
  keypress, and a synchronous load would freeze the shell on that keypress
  (#901).
- **Lengthen or shorten the probe's retry.** A direct crash assertion is the
  property; the retry is only a proxy for it.
- **Count `Binding loop detected for property preload`.** It is a sibling
  warning, and its wording can change.
- **`coredumpctl`.** See D2.

## Risks

- **A stall when nixarchy-menu is enabled.** Its panel is now built on the UI
  thread in one step, both at startup and at the moment it is enabled. Fix
  (b)'s runs are the closest measurement so far: the row returned in 0.75 and
  0.80 s, and the plugin list answered 0.42 and 0.33 s after it. In the
  crashing runs the answer came from a restarted shell, 1.8–5.5 s later. Those
  are n=2, from fix (b), so D1's own runs re-measure. The plan adds a startup
  measurement too: from the `omarchy-shell` unit starting to its first IPC
  answer, with nixarchy-menu on, D1 against unpatched on the same tree. A
  slower start that stays well inside the check's own timeouts is accepted
  and recorded. Hosts: only machines that enable nixarchy-menu.
- **Upstream changes the lines.** `--replace-fail` turns any rewording into
  a build failure on the bump, which is the intended signal.
- **Edge.** quattro's `shell.qml` may differ. The edge carry checks whether
  the anchor is present and gives edge its own anchor if it is reworded.
- **The new assertion finds a crash elsewhere in the session.** Then `main`
  goes red for a real defect, which is the purpose.
- **Mode A.** Kept: a user who does not enable nixarchy-menu gets the same
  `shell.qml` behaviour as before. The plan asserts it in the build: the
  substituted text names `nixarchy.menu` only.

## Coexistence (§14)

No NixOS or Home Manager option is set and nothing merges into a user's
environment. The change is inside the vendored `shell.qml`. No fixture
applies.

## Verification

All VM runs only with CI idle (§6), on the tree of #1307's head, where the
unpatched crash is deterministic (3 of 3, `loop-results.txt`).

1. **The fix:** 6 runs of `checks.session` with D1 (n-1 to n-6), each with no
   SEGV line, no crash directory, no binding loop, and the switch probe
   passing. Six, because fix (a) passed 2 of 3 on this tree: a non-fix that
   crashes 1 run in 3 would pass four runs about 20% of the time, and six
   about 9%. Any crash in the six rejects D1.
2. **The probe fails (§1):** D2 on the unpatched tree fails with `#1313:
   Quickshell crashed during the session` in 3 of 3 runs. The case where the
   old assertion alone would have passed is already on record:
   `loop-unpatched-1` has segv=1 with switch_ok=1. The plan names it, and
   D2 must fail on that same tree.
3. **D1 and D2 together:** green, including D2's end-of-session check, which
   has not yet run anywhere.
4. **Startup cost:** the measurement in Risks, recorded in the PR.
5. **Cheap checks:** `checks.install-phase-budget`, since D1 adds lines to
   the install phase; `omarchy` builds; `nix fmt -- --ci`, statix, deadnix.
6. **Then** #1307, #1311 and #1312 merge `main` and their own
   `checks.session` runs green without an override.
