---
status: approved
issue: 901
author: olafkfreund
---

# Intent: a bar layout change must not rebuild every plugin

## Problem

Every save of `~/.config/omarchy/shell.json` rebuilds every panel, menu and
overlay plugin, re-syncs every service, and re-syncs every bar widget. That
includes a save that only moves a bar icon or changes one widget setting. On p620
(52 enabled plugins) the bar is frozen for **28–75 s per save**.

Measured on p620, 2026-09-22/23 (shell PID 220018, #894 fix present): 13
`shell.json` saves since login, each re-registering ~99 IpcHandlers against 44
for a plugin reload, with `at-spi` marking the shell unresponsive. Bar Folder
saves `shell.json` on every drag, so moving 5 icons into it froze the bar for
more than half of every minute for ten minutes. `omarchy bar set`, the bar's
layout editor and `capture.sh --setup` pay the same cost.

### Cause

In upstream `shell/shell.qml` (in nixarchy `3ed0dea`):

1. `onShellConfigChanged` (line 67) runs on **any** `shell.json` change and fires
   `pluginRegistry.pluginsChanged()`. That signal means "the set of plugins
   changed", and it fires for a pure layout edit.
2. Its listener at line 1322 does `shell.panelEntries = shell.computePanelEntries()`,
   which is a new JS array every time. `panelEntries` is the `model` of an
   `Instantiator` (line 1325), and QML does not diff a JS array model, so every
   panel, menu and overlay plugin is destroyed and created again, even when the
   list is identical.

This is probably also the mechanism behind #847 (a `shell.json` save blanks the
bar or segfaults Quickshell in `IpcHandler::onPostReload`).

## Proposed outcome

- Moving a bar icon, dragging into Bar Folder, or `omarchy bar set` on a widget
  setting rebuilds **no** plugin panels and costs no multi-second freeze. The bar
  shows the new layout within about a second.
- Enabling or disabling a plugin in `shell.json` still loads or unloads it, as
  today.
- A plugin re-sync whose resulting panel list is identical leaves the existing
  panels in place.

## Affected users and systems

- Everyone on the nixarchy Omarchy shell: p620, razer and p510 through the
  flake-wide `inputs.nixarchy`.
- Anything that writes `shell.json` while the shell runs: the bar's layout
  editor, `omarchy bar set/put/move`, Bar Folder, `capture.sh`, and
  `omarchy plugin enable/disable`.

## Constraints

- Upstream Omarchy owns `shell.qml`, so this is a **carried build-time patch** in
  `pkgs/omarchy/default.nix`, next to the #877 and #893 blocks, failing the build
  if its anchor moves. It is dropped once upstream fixes it.
- Enabling or disabling a plugin through `shell.json` must keep working exactly
  as today. Only saves that do not change the enabled set may skip the re-sync.
- **Out of scope:** reloading only the changed plugin on install or remove (the
  rest of #710), which is a larger refactor.
- It takes effect for a running session only at the next re-login (the session
  pins `OMARCHY_PATH`). No live shell swapping.
- Urgent: the owner wants it merged as soon as it is verified, even if the
  hour-long install checks haven't finished (`--admin`), once local builds and
  tests pass.

## Open questions

- Does a widget-*setting* change (for example `columns` on Bar Folder) reach the
  widget without the full re-sync? Recommendation: the spec checks how a bar
  widget reads its settings (`barConfig`, re-read from `shellConfig`) before
  relying on it.
