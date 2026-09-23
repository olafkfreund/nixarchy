---
status: draft
issue: 901
spec: spec/2026-09-23-901-shell-json-no-full-rebuild.md
---

# Plan: a bar layout change must not rebuild every plugin

## Approved decisions (from the spec)

- **Two carried patches to upstream `shell/shell.qml`**, in
  `pkgs/omarchy/default.nix` directly after the #893 block (after line 2005,
  `substituteInPlace "$shellQml" --replace-fail "$rescanOld" "$rescanNew"`, before
  `# Wear the snowflake.`). Same style: `printf '%s\n'` strings,
  `--replace-fail` on whole blocks, and a `CARRIED, and meant to be dropped
  (#901)` comment.
- **Patch A: `onShellConfigChanged`.** Keep `failedBarId` reset and
  `registryRevision++`. Then compute `shell.enabledPluginSignature()`. If it
  differs from `shell._enabledPluginSignature`, store it and
  `pluginRegistry.pluginsChanged()`; otherwise call `shell.syncPluginApis()` so
  keep-loaded plugins still get the new `barConfig`.
- **Patch B: the line-1322 listener.** Return early while `pluginReloading`;
  otherwise compute the next list and assign `shell.panelEntries` only if
  `!shell.samePanelEntries(shell.panelEntries, next)`.
- **Helpers**, inserted before `function computePanelEntries() {`:
  - `enabledPluginSignature()`: sorted ids in
    `pluginRegistry.installedPlugins` with `pluginRegistry.isEnabled(id)`, joined
    with `,`, plus `|` and the selected bar id (`shellConfig.bar.id`, or `""`);
  - `samePanelEntries(a, b)`: both arrays, same length, and per index the same
    `id`, `kind`, `keepLoaded`, and `manifest ===`.
- **`property string _enabledPluginSignature: ""`** is inserted before
  `onShellConfigChanged: {`.
- **Anchors, each checked unique (count 1) in tree `3k5vcr1h…`:**
  - `onShellConfigChanged: {` plus its 4 body lines (the whole 5-line block is
    the needle);
  - `function onPluginsChanged() { if (!shell.pluginReloading) shell.panelEntries = shell.computePanelEntries() }`;
  - `function computePanelEntries() {`.
- **Out of scope:** the `Bar.qml` widget rebuild on layout moves. It is measured,
  and becomes a follow-up issue if still seconds long. Also out of scope: the
  install/remove full reload (#710's rest).
- **Merge:** urgent. Once the local build, checks and nested proof pass, merge
  with `--admin` on the owner's instruction, without waiting for the hour-long
  install checks.

## Steps

1. **`pkgs/omarchy/default.nix`:** insert the #901 block after line 2005.
   Three `substituteInPlace --replace-fail` calls:
   1. the 5-line `onShellConfigChanged` block → the property line plus the
      patched block;
   2. the one-line listener → the multi-line patched listener;
   3. `function computePanelEntries() {` → the two helpers followed by that
      same line.

   Write all needles and replacements with `printf '%s\n'`, with QML
   indentation exactly as in the upstream file. Verify by `nix-instantiate
   --parse`, then `nixfmt` (this repo's formatter: `nix fmt`), then
   `git diff --stat` shows only this file.

2. **Build:** `nix build .#omarchy -o result-901`. In
   `result-901/share/omarchy/shell/shell.qml`:
   - `grep -c "CARRIED patch (#901)"` = 2 (A and B);
   - `enabledPluginSignature`, `samePanelEntries` and `_enabledPluginSignature`
     are present;
   - the old one-line listener is gone.

3. **QML sanity:** `qmllint` is not usable on the whole shell (it has
   unresolvable imports), so this is proven at runtime in step 6.
   `checks.qml` (step 5) parses the shell.

4. **Negative test** (not committed): change one character of the listener
   needle. The build must fail on `--replace-fail`. Revert, and confirm with
   `git diff`.

5. **Checks:** commit locally first, because `checks.free-space` refuses a
   dirty tree (the #893 lesson). Then:
   - every `checks.x86_64-linux.*` `drvPath` evaluates;
   - `manifest-has-kind`, `plugin` and `qml` build.

6. **Nested proof, with a baseline.** Run the **unpatched** tree
   (`3k5vcr1h…`) first, then the patched `result-901`, under identical
   conditions:
   - an isolated nested Hyprland (the #1973 method: its own runtime, config,
     state and data dirs, `AQ_DRM_DEVICES=/dev/null`), plus
     `quickshell -p <tree>/shell` inside it with `XDG_CONFIG_HOME` pointing at a
     **copy** of `~/.config/omarchy` (plugins + `shell.json`);
   - in that copy, add the plugins with outside side effects (`olafkfreund.govee`,
     `io.github.grichard99.omaproton-vpn`, `omamail`, `voice.indicator`) to
     `disabledPlugins`, so nothing touches real lights, VPN, mail or audio.

   For each tree, measure three actions against the copied `shell.json` through
   the nested shell's own `omarchy bar` CLI (its `OMARCHY_PATH`):
   - (a) `bar set` of a widget setting;
   - (b) a pure layout move of one first-party icon;
   - (c) enable, then disable, a panel plugin.

   Record for each: IpcHandler re-registrations, `destroyed during incubation`
   lines, and seconds until nested IPC `ping` answers again.

   **Pass:**
   - (a) and (b) show **0** panel re-registrations on the patched tree, and
     fewer seconds than baseline;
   - (a) delivers the new setting (visible in `listPlugins`/bar config through
     IPC);
   - (c) still loads and unloads the plugin;
   - `configerrors` empty.

   Tear down by the **Hyprland PID**, not the `setsid` wrapper. No nested
   process may be left, and the temp dirs are removed.

7. **Commit** `fix(omarchy): a shell.json save no longer rebuilds every plugin (#901)`
   and push. Open the PR linking the intent, spec, plan and #901/#847/#710, with
   the step 2, 4, 5 and 6 evidence (baseline against patched numbers).

8. **Merge:** once steps 1–6 pass, `gh pr merge --squash --admin` on the
   owner's standing instruction, if the long install checks are still running.
   Then verify with `git show origin/main:pkgs/omarchy/default.nix`, not the
   badge. If step 6 shows layout moves still take seconds (the bar-widget
   rebuild), open the follow-up issue for keyed bar models, linked from #901.

9. **Rollout** (not in this repo): the owner's next `nhs` picks up the nixarchy
   bump, and the fix takes effect at each host's **next re-login**. Live check
   on p620 after re-login: one icon move and one `bar set`, then the journal
   shows no panel handler flood and the `at-spi` unresponsive marks are gone or
   reduced to the measured bar-widget cost. Post on the bus.

## Tests

| Check | Expected |
| --- | --- |
| `nix build .#omarchy` | Succeeds; 2 × `CARRIED patch (#901)` in the built `shell.qml` |
| Broken needle | Build fails on `--replace-fail` |
| All `checks.*` evaluate; `manifest-has-kind`, `plugin`, `qml` build | Green |
| Nested (a) `bar set` | Patched: 0 panel re-registrations, setting delivered, faster than baseline |
| Nested (b) layout move | Patched: 0 panel re-registrations; remaining bar-widget time recorded |
| Nested (c) enable/disable a panel plugin | Loads and unloads as on baseline |
| Live on p620 after re-login | No panel handler flood on a move or `bar set` |

## Rollback

- **Before merge:** delete the branch. Nothing is deployed from it.
- **After merge:** `git revert` the squash commit. The patch is one
  self-contained block in `default.nix`. Hosts pick up the revert at the next
  flake bump and re-login.
- **If it misbehaves live** (a panel not appearing after enabling a plugin):
  `omarchy-restart-shell` recovers the session. The revert follows.
