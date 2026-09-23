---
status: approved
issue: 901
intent: intent/2026-09-23-901-shell-json-no-full-rebuild.md
---

# Spec: a bar layout change must not rebuild every plugin

## Design

Two carried build-time patches to upstream `shell/shell.qml` in
`pkgs/omarchy/default.nix`, next to the #877 (`manifestHasKind`) and #893
(`rescanPlugins`) blocks and in the same style: `substituteInPlace --replace-fail`
with whole-block needles, strings built with `printf '%s\n'`, and a
`CARRIED, and meant to be dropped` comment naming #901.

### What a `shell.json` save does today (the code this changes)

- `onShellConfigChanged` (shell.qml:67) runs `registryRevision++` and
  `pluginRegistry.pluginsChanged()` for **every** save.
- `pluginsChanged` has three listeners:
  - **1057:** `syncPluginApis()`, then `_syncServices()`. `syncPluginApis` is
    how plugin APIs receive settings: `shellApi.barConfig = publicBarConfig()`
    (line 882), a pushed copy. `_syncServices` is already incremental: existing
    instances are kept and only get the fresh manifest.
  - **1322:** `shell.panelEntries = shell.computePanelEntries()`, a new JS array
    for the `model` of the panel `Instantiator` (1325). QML does not diff it, so
    every panel, menu and overlay plugin is destroyed and recreated.
  - **1379:** `syncPluginWidgets()`, already incremental: it re-registers
    unchanged URLs in place.
- The registry's own `moveBarWidget` (PluginRegistry.qml:314) and
  `setBarWidget` (382) **also** emit `pluginsChanged()` before writing
  `shell.json`, so `omarchy bar set/move` pays the fan-out twice.
- **Enabled is layout-dependent.** For third-party plugins, `isEnabled()` is
  "appears in the bar layout or `plugins[]`". A Bar Folder drag of a third-party
  icon therefore **does** change the enabled set: the shell drops it and Bar
  Folder hosts it.

### Patch A: `onShellConfigChanged` fans out only when the enabled set changed

The block becomes (with a new property `_enabledPluginSignature: ""`):

```qml
  onShellConfigChanged: {
    if (failedBarId !== "") failedBarId = ""
    pluginRegistry.registryRevision++
    // nixarchy CARRIED patch (#901): a layout/settings-only save must not
    // rebuild every plugin. Fan out only when the enabled set changed; otherwise
    // just push the new barConfig into the plugin APIs.
    var signature = shell.enabledPluginSignature()
    if (signature !== shell._enabledPluginSignature) {
      shell._enabledPluginSignature = signature
      pluginRegistry.pluginsChanged()
    } else {
      shell.syncPluginApis()
    }
  }
```

- `enabledPluginSignature()`: the sorted ids in `installedPlugins` for which
  `pluginRegistry.isEnabled(id)` is true, joined, plus the selected bar id.
  The same predicate every consumer uses, so "changed" means exactly what they
  would see change.
- `registryRevision++` is kept unconditionally. It only drives cheap bindings
  (`selectedBarAvailable`, `activeBarManifest`), and dropping it could leave a
  bar switch unnoticed.
- The first load (signature `""` → real) fans out as today.
- `syncPluginApis()` on the else branch keeps settings reaching keep-loaded
  plugins (the #877 Podman `showStats` case). The bar itself already receives
  `barConfig` by binding and patches settings in place
  (`Bar.qml applyBarConfig` → `inlineSettingsDelta`).

### Patch B: never replace an identical panel list

The line-1322 listener becomes:

```qml
    function onPluginsChanged() {
      if (shell.pluginReloading) return
      // nixarchy CARRIED patch (#901): QML rebuilds every panel when the
      // Instantiator model is reassigned; skip identical lists.
      var next = shell.computePanelEntries()
      if (!shell.samePanelEntries(shell.panelEntries, next)) shell.panelEntries = next
    }
```

- `samePanelEntries(a, b)`: same length, and for each index the same `id`,
  `kind` and `keepLoaded`, and the **same manifest object** (`===`). A rescan
  produces new manifest objects, so a real plugin change still rebuilds, exactly
  as today. Order is `computePanelEntries`' own iteration order, which is stable
  between calls on the same `installedPlugins`.
- The explicit reload path (`onScanFinished`, line 1492) still assigns
  directly, so installs, removals and rescans behave exactly as today.
- B also covers the remaining `pluginsChanged()` callers: the registry's
  `moveBarWidget`/`setBarWidget`, and a Bar Folder drag that really changes the
  enabled set. The panel list stays identical unless the moved plugin has a
  panel, menu or overlay kind, and most bar icons don't.

### Helpers

`enabledPluginSignature()` and `samePanelEntries()` are inserted as functions
directly before `function computePanelEntries() {` (a single, unique anchor),
and `property string _enabledPluginSignature: ""` goes directly before
`onShellConfigChanged: {`.

### What this does not fix (measured, not assumed)

A layout **move** still makes `Bar.qml` reassign `layoutConfig`, which by
upstream's own comment rebuilds every bar widget on every monitor (three on
p620). A+B remove the panel rebuild and the double fan-out. The bar-widget
rebuild stays. Verification measures what remains. If a move still freezes the
bar for several seconds, that is a follow-up issue (keyed bar models), not a
reason to widen this patch.

## Alternatives rejected

- **Skip `pluginsChanged` entirely on settings-only saves.** Keep-loaded plugin
  APIs would keep a stale `barConfig`, which breaks the #877 case. Hence the
  `syncPluginApis()` else branch.
- **Diff `shell.json` for `plugins`/`disabledPlugins` keys only.** "Enabled"
  also depends on the bar layout for third-party plugins, so a key diff would
  miss Bar Folder drags. The signature uses `isEnabled()` itself.
- **Change the registry's `moveBarWidget`/`setBarWidget` emits.** Not needed
  once B makes a no-op fan-out cheap, and it would mean a second upstream file
  to carry.
- **Keyed `ListModel` for panels and bar widgets.** The thorough fix for all
  paths, but a refactor of the `Instantiator` and the `Bar.qml` Repeaters. Too
  large for an urgent carried patch; noted as the follow-up.
- **Throttle or debounce `shell.json` saves.** Reduces how often the rebuild
  happens but still pays the full rebuild.

## Risks

- **A missed enabled change:** if some path changes what a consumer sees without
  changing `isEnabled()` for any plugin, A would skip the fan-out. Mitigation:
  the signature uses the consumers' own predicate plus the bar id, and B
  already makes a fan-out cheap, so a follow-up could simply always fan out if
  that ever shows up.
- **`samePanelEntries` false negative** (lists identical but judged different)
  only costs a rebuild, today's behaviour. A **false positive** (judged same
  but different) would keep a stale panel. Mitigation: manifest identity is
  compared, so any rescan or manifest change counts as different.
- **An upstream rewrite** of any of the three anchors fails the build
  (`--replace-fail`). That is intended.
- **Hosts:** every host that builds nixarchy's omarchy (p620, razer, p510).
  It takes effect at each host's next re-login.

## Verification

1. **Build:** `nix build .#omarchy`. The patched `shell.qml` contains the #901
   blocks, and the three anchors each appear exactly once before patching.
2. **Checks:** every `checks.x86_64-linux.*` evaluates. `manifest-has-kind`,
   `plugin` and `qml` build, because they read the patched `shell.qml`.
3. **Negative test:** break one anchor and the build fails. Revert.
4. **Nested Hyprland** (isolated, the #1973 method) running the **patched tree**
   with a copy of p620's plugin set and `shell.json`:
   - `omarchy bar set <widget> <setting>` → **0** panel IpcHandler
     re-registrations, and the setting reaches a keep-loaded plugin's
     `shell.barConfig`;
   - a pure layout move → **0** panel re-registrations; time the bar-widget
     rebuild that remains;
   - enable, then disable, a panel plugin → it loads and unloads as today;
   - `configerrors` empty and no `destroyed during incubation`.
5. **Live on p620 after re-login:** repeat one icon move and one `bar set`. The
   `at-spi` "unresponsive" marks disappear or drop to the measured bar-widget
   cost, and the journal shows no panel handler flood.
