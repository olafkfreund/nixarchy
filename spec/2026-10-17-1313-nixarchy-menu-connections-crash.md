---
status: approved
issue: 1313
intent: intent/2026-10-17-1313-nixarchy-menu-connections-crash.md
---

# Spec: Enabling nixarchy-menu must not crash the shell

## Design

### D1. keepLoaded panels load synchronously (intent option c)

The crash is a `Connections` in nixarchy-menu being retargeted while the
plugin's panel is still being incubated asynchronously. `shell/shell.qml`'s
per-plugin `panelLoader` has `asynchronous: true` (line 1405 on 4.0.4).
nixarchy-menu is a `keepLoaded` panel, so it is created the moment it is
enabled, in the same `syncPanelEntries` pass that tears down the stock menu.

One substitution in `pkgs/omarchy/default.nix`, beside the other carried
shell edits:

```
asynchronous: true  →  asynchronous: !panelEntry.keepLoaded
```

`--replace-fail`, and anchored on the indented line inside `panelLoader` so it
cannot match line 266's unrelated `asynchronous: true`. That gives one
occurrence; the plan checks it. A keepLoaded panel is
then created in one step, outside any incubation, so no signal handler can
retarget its `Connections` halfway through. Panels opened on demand stay
asynchronous, which is what #901's stall concern was about.

Why here, not in nixarchy-menu (option a) or a postPatch on it (option b):

- It is the only fix measured to work. Gating the `Connections` target on
  `ready` and deferring the fallback Loader with `Qt.callLater` (fix (a),
  inside nixarchy-menu) still crashed one run in three. The intent lists two
  routes into the retarget, and fix (a) closed only one of them.
- It closes the window for every keepLoaded plugin, not only this one: the
  stock menu, lock, polkit, clipboard, emojis, image-picker and reminders are
  all keepLoaded, and any of them can carry a `Connections` on a property set
  in `onLoaded`.
- It needs no change in another repository.

A short note at the substitution names #1313 and points to
`pkgs/AGENTS.md#keeploaded-panels-load-synchronously-1313`, which carries
the backtrace, the two routes, the measurements and the drop condition. It
drops when Omarchy's loader stops creating keepLoaded panels asynchronously,
or when the crash is shown to be gone in Qt.

nixarchy-menu's own `Connections` is also fragile, and that is filed as a
follow-up in its repository rather than fixed here (§11: the owner's repo, a
separate change). Fix (a)'s diff goes into that issue as evidence.

### D2. The session check fails on any Quickshell crash

`tests/session.nix`, the #1283 menu-switch probe. Right after
`click("setup.default.menu.nixarchy")` and `menus()`, and once more at the
end of the test script:

- `coredumpctl --no-pager list` filtered to the Quickshell executable
  (`quickshell-wra`, as in the logged SEGV) must list nothing;
- `~/.cache/quickshell/crashes` must be empty or absent.

Either one present fails with `#1313: Quickshell crashed during the session`,
followed by the crash report's first lines and the coredump's signal. Both
sources are checked because Quickshell's own handler writes the report while
systemd-coredump keeps the core. Measured: the diagnostic run logged both for
the same SEGV, and checking both means neither handler is a single point of
failure.

This answers the intent's question 3: **the whole session, checked twice.**
The crash directory and the coredump list are cumulative. Checking at the
switch points at the menu switch when that is where it crashed. Checking at
the end catches a crash anywhere else. Two runs of fix (b) passed the whole
session, and main passed three CI runs, so no known crash sits elsewhere. If
one turns up, it is a real crash and gets its own issue, not an allowlist
entry.

The probe's existing assertion, that the switch leaves `nixarchy.menu=True
omarchy.menu=False`, stays exactly as it is. Its 60 s retry also stays. That
retry is what let a crashed-and-restarted shell pass. The new assertion makes
the retry harmless, so the retry does not need to change (owner's decision:
strengthen, never loosen).

### D3. Timing is printed, not asserted

The probe prints `#1313 timing: row Xs, plugin-list answered Ys after it`.
That is the measurement the stall question needs, and it keeps landing in
every CI log. It is not an assertion: a hosted runner's speed varies too much
for a bound that never flakes, and §10 forbids retrying until green.

## Alternatives rejected

- **(a) Fix nixarchy-menu's `Connections` in its repository, then bump the
  pin.** Measured insufficient: 1 crash in 3 runs. A complete fix there means
  finding every route by which `root.library` changes during incubation, in
  code this repo does not own. It is still worth doing, as the follow-up
  above.
- **(b) Carry fix (a) as a postPatch on the plugin.** The same fix as (a),
  measured the same, and it adds a patch to another project's tree.
- **Make every panel Loader synchronous.** On-demand panels are created on
  a keypress, and a synchronous load of a heavy one would freeze the shell on
  that keypress (#901). keepLoaded panels are created at startup or on enable,
  where nobody is waiting on one frame.
- **Lengthen or shorten the probe's retry.** Waiting less makes the check
  flakier and catches nothing new. Waiting more hides more restarts. A direct
  crash assertion is the property; the retry is only a proxy for it.
- **Count `Binding loop detected for property preload`.** It is a sibling
  symptom that appeared in every crashing run. Asserting on it would test a
  warning rather than the crash, and a warning can change wording.

## Risks

- **Startup stalls.** Seven keepLoaded panels now load on the shell's
  startup frame, not across several. Measured so far: a full session run
  takes 378 s and 357 s with fix (b), against 347 s and 356 s without it. The
  plan adds a measurement of the shell's own startup, from the
  `omarchy-shell` unit starting to its first IPC answer, patched and unpatched
  on the same tree. A slower startup that is still well inside the session
  check's own timeouts is accepted and recorded. Hosts: every machine running
  the Omarchy shell, since the change is in `shell.qml`.
- **A keepLoaded plugin that is slow to construct now blocks the UI thread
  while it loads.** Plugins nixarchy ships are measured above; a user's
  heavy third-party keepLoaded plugin would stall startup, not crash. That is
  the better failure, and the pkgs/AGENTS.md section says so.
- **Upstream changes the line.** `--replace-fail` turns any rewording into a
  build failure on the bump, which is the intended signal (as the other shell
  carries are).
- **Edge.** quattro's `shell.qml` may differ. The edge carry checks whether
  the line is present. If it is, the substitution applies as is; if it is
  reworded, edge gets its own anchor in a carry commit.
- **The new assertion finds a pre-existing crash elsewhere in the session.**
  Then `main` goes red, for a real defect. That is the purpose of the check.
- **Mode A.** Nothing changes for a user who does not use the Omarchy shell.
  For one who does, without nixarchy-menu, the stock keepLoaded panels load
  synchronously too: covered by the startup measurement.

## Coexistence (§14)

No NixOS or Home Manager option is set and nothing merges into a user's
environment. The change is inside the vendored `shell.qml`. No fixture
applies.

## Verification

All VM runs only with CI idle (§6), on the tree of #1307's head, where the
unpatched crash is deterministic (3 of 3).

1. **The fix:** 4 runs of `checks.session` with D1, each with `segv=0`, no
   binding loop, and the switch probe passing. Two are done (b-1, b-2), and
   two are waiting for CI to go idle.
2. **The probe fails (§1):** D2 on the unpatched tree must fail with
   `#1313: Quickshell crashed during the session` in at least 3 of 3 runs. At
   least one of those must be a run where the old switch assertion alone would
   have passed, i.e. the restarted shell answered in time. If no run shows
   that, the plan forces it: the run waits for the restarted shell before
   asserting, then checks that D2 still fails.
3. **D1 and D2 together:** green, with the timing line inside the no-crash
   baseline (plugin list answering 0.3–0.8 s after the row).
4. **Startup cost:** the measurement in Risks, patched against unpatched,
   recorded in the PR.
5. **Cheap checks:** `checks.install-phase-budget` (D1 adds two lines to the
   install phase), `omarchy` builds, `nix fmt -- --ci`, statix, deadnix.
6. **Then** #1307, #1311 and #1312 rebase onto it, and their own
   `checks.session` runs green without an override.
