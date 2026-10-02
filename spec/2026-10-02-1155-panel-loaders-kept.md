---
status: draft
issue: 1155
intent: intent/2026-10-02-1155-panel-loaders-kept.md
---

# Spec: a plugin change rebuilds only the panels it changed

## The intent's two open questions, answered by this spec

- **Checks: both.** A cheap static check on the patched `shell.qml`, which
  proves the code is there and can be shown failing deterministically. Plus a
  `checks.session` assertion on the symptom, which counts, but whose red on
  the old code may not be deterministic in a one-monitor VM. D3 says how
  that is measured and reported, not assumed.
- **#958: note the link only.** #958 was closed *not planned* on 2026-09-24:
  the crash is in Quickshell 0.3.1 (`IpcHandler::updateRegistration`, a
  `dynamic_cast` on a handler gone after a reload), and the owner does not file
  Quickshell reports. This change makes re-registration much rarer, which can
  only reduce that crash's chances, but it cannot show the crash is gone. The
  PR says so, and #958 stays closed.

## What was measured before writing this

- **Upstream's change is one file.** omacom/omarchy@0066ea216b (#13439)
  changes `shell/shell.qml` (+47/−11) and adds
  `test/shell.d/panel-entries-test.sh`.
- **Its `shell.qml` diff applies cleanly in both places:**
  - to v4.0.4 alone;
  - to v4.0.4 plus #1153's backport (the `backport` branch in
    `/mnt/data/vmtest/owe/omarchy`).

  So it does not depend on #1153's order, and either may merge first.
- **Which nixarchy edits it collides with.** Part B of the #901 patch
  (`pkgs/omarchy/default.nix`, the `panelOld`/`panelNew` substitution at about
  `:1954-1962`) targets the exact `onPluginsChanged` line this replaces. Applied
  after the upstream change, part B's `--replace-fail` fails the build. That is
  the intended guard: B has to go.
- **Which edits it leaves alone:**
  - Part A of the #901 patch, the `cfgOld`/`cfgNew` substitution in
    `onShellConfigChanged`, is untouched by upstream's diff and stays.
  - The `helpersAnchor` (`  function computePanelEntries() {`) still exists
    after the change, because upstream keeps `computePanelEntries` and
    inserts above it.
- **The symptom on p620:**
  - 16,356 `another handler is registered` warnings over seven days;
  - 62 after one shell restart, with `nixarchy.podman`, `.microvm` and
    `.devenv` `Panel.qml` five times each.

## Design

### D1. Carry upstream's commit as a patch, applied before nixarchy's edits

- **The patch.** `pkgs/omarchy/1155-panel-loaders-kept.patch` is the
  `shell/shell.qml` part of `git show 0066ea216b`, with a header that:
  - names the upstream commit and PR;
  - says CARRIED;
  - says the `quattro` bump deletes it (`quattro` already has it).

  The upstream test file is not carried; the `test/` directory is removed from
  the package (`default.nix:424`).
- **Where it applies.** `patch -d "$out/share/omarchy" -p1 --forward --fuzz=0`,
  placed right after the tree copy (`default.nix:422-424`) and **before** every
  `substituteInPlace`, for the reason #1153 gives: nixarchy's edits must target
  the patched text.
  - If #1153 has landed, this line goes directly after its `patch` line.
  - If not, it goes in the same position, and #1153's rebase puts its own line
    beside it. The two patches touch different hunks of `shell.qml` (measured
    above).

### D2. Shrink the #901 patch to part A

- **Delete part B:** the `panelOld`/`panelNew` substitution, and the
  `samePanelEntries` helper from `helpersNew`.
- **Keep part A** and its helper, `enabledPluginSignature`. Upstream does not
  fix "a layout-only save fans out `pluginsChanged()`", and part A is what
  stops that.
- **`pkgs/AGENTS.md`'s #901 section** ("Two causes, one per patch below") is
  rewritten to say that part B was retired by carrying upstream's fix (#1155),
  and that part A remains, with the same drop condition. A new short section
  for the 1155 patch sits beside it.
- **Ledger:** `shell.qml` is not a `bin/` script, so `data/bin-ledger.nix`
  needs no row. Step 3 of the plan confirms this with `checks.bin-ledger`
  rather than assuming it.
- **Budget:** this frees about 900 bytes of `installPhase`. #1153 left it
  3,100 bytes under `checks.install-phase-budget`.

### D3. Checks

- **`checks.panel-loaders` (new, cheap): a `runCommand` over the built
  `shell.qml`.** It ports upstream's three assertions:
  1. the panel `Instantiator`'s `model:` is `panelEntryModel`, and the string
     `panelEntries` does not occur;
  2. `syncPanelEntries` keeps an entry whose kind, `keepLoaded` and
     `sourceUrl` are unchanged (`delete wanted[row.pluginId]` under that
     condition);
  3. `unloadPanels()` still clears the model, so a full reload rebuilds from
     fresh code.

  It also asserts that part A's `enabledPluginSignature` is still present, so
  D2 cannot delete too much.
  - **Matching method:** `grep -Pzo` or a small `python3` (the file is
    multi-line), never a pipe into `grep -q` (`tests/AGENTS.md`).
  - **Wiring:** it is a new `checks.*` entry, so CI runs it with no workflow
    edit (AGENTS.md §4).
  - **§1:** red is shown by building it against the unpatched package
    (drop the `patch` line). The red output goes in the PR.
- **`checks.session` (symptom):** after login settles, and again after an
  `omarchy-restart-shell`, the user journal since that point has **no**
  `another handler is registered` line whose QML path ends in `/Panel.qml`,
  `/Menu.qml` or an overlay entry point.
  - **Scope:** bar widgets are excluded, because one copy per monitor is a
    separate, legitimate source on multi-monitor machines (seen on p620 for
    `omarchroma/BarWidget.qml`). The VM has one monitor, so they are not the
    signal.
  - **§1 and §3:** the break is the same package with the 1155 `patch` line
    removed. If that run shows the duplicates, the check is proven. If it does
    not (upstream saw 1 in 5 runs on a busy machine), the PR says so plainly.
    The deterministic proof is then `checks.panel-loaders`, and the session
    assertion is kept as a regression tripwire, described as such, not as a
    proven detector.
- **On p620 after merge, by hand:** restart the shell and count the
  `Panel.qml` duplicates in the journal. That is 62 before (2026-10-02 08:20),
  and 0 is expected after. The number goes in the PR.

## Alternatives rejected

- **Extend #901 part B to diff per entry.** That would be a third version of
  upstream's fix. The constraint is to carry upstream's, so the `quattro` bump
  deletes it cleanly.
- **Keep part B as well.** Its `--replace-fail` cannot match after upstream's
  change, and its job (skip an identical list) is a subset of what upstream's
  sync does.
- **`--replace-fail` blocks instead of a `.patch`.** Upstream's change is a
  47-line, multi-hunk rewrite. 901/902 set the precedent for a `--fuzz=0`
  patch file at that size, and the install phase has about 3 KB of headroom
  left.
- **Reproduce #958.** It is closed, upstream's, and intermittent. A
  non-reproduction would prove nothing.

## Risks

- **A panel that should be rebuilt and is not.** Upstream keeps a loader when
  kind, `keepLoaded` and `sourceUrl` are unchanged. A plugin whose *code*
  changes under the same URL (a local plugin edit) still reloads, because that
  path goes through `reloadPlugins()`, which clears the model in
  `unloadPanels()`. `checks.panel-loaders` assertion 3 holds that in place.
- **The manifest is read live** (`shell.pluginRegistry.installedPlugins[pluginId]`)
  instead of captured. That is upstream's choice; a rescan that replaces the
  manifest is seen without rebuilding the panel.
- **Overlap with #1153.** Both patch `shell.qml`. They apply cleanly in either
  order, as measured, but the second to merge must rebuild `.#omarchy` after
  rebasing (AGENTS.md §9).
- **A session check that cannot fail.** Covered in D3: if the break run stays
  green, that is reported, and the static check carries the proof.

## Verification

1. `nix build .#omarchy` applies the patch with `--fuzz=0`. Part A's
   substitutions still match, and part B's are gone.
2. `checks.panel-loaders`: green on the patched build, red on the unpatched one
   (output in the PR).
3. `checks.install-phase-budget`, `checks.bin-ledger` and `checks.patched-files`
   are green.
4. `checks.session` (CI): green. The result of the break run is reported either
   way.
5. The p620 hand count, before (62) and after.
6. `nix fmt -- --ci`, statix and deadnix are clean.
