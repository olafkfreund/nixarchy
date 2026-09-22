---
status: draft
issue: 877
author: olafkfreund
---

# Intent: keep-loaded plugins lose their shell API on the first settings change

## Problem

A plugin that stays loaded (`"keepLoaded": true`) and reads its settings from
`shell.barConfig` stops seeing them after the first time `shell.json` changes.
Until the shell restarts, `shell.barConfig` reads `null` and the plugin falls back
to its manifest defaults.

The visible case is nixarchy-podman's full-screen menu:

- `omarchy bar set nixarchy.podman showStats false --json` applies to the bar popup
  at once;
- the menu ignores it until `omarchy-restart-shell`.

That plugin now documents the restart as a workaround
(olafkfreund/nixarchy-podman#10). Any keep-loaded menu plugin behaves the same.

### Cause, confirmed on razer

Found with log lines in a copy of omarchy 4.0.4's `shell/shell.qml`, run in place
of the shell for a few minutes.

- `manifestHasKind(manifest, kind)` (`shell.qml:349`) returns
  `!!manifest && Array.isArray(manifest.kinds) && manifest.kinds.indexOf(kind) !== -1`.
- **At creation:** the plugin's scoped API is created with a manifest read through a
  QML property. There `kinds` is a Qt sequence wrapper: it has a length and entries,
  but `Array.isArray` is false. So the recorded capability profile says `no-menu`.
- **At the first `shell.json` change:** `onShellConfigChanged` → `pluginsChanged` →
  `syncPluginApis` → `prunePluginApis` recomputes the expected profile from
  `installedPlugins[id]`, a plain JS object, and gets `menu`.
- **The mismatch:** the two profiles differ, so `revokePluginShellApi` destroys the
  API. Keep-loaded instances get a new `shell` only on a plugin reload, so the
  plugin keeps the destroyed object.

The log:

```
create key=nixarchy.podman cached=false kindsIsArray=false kindsLength=2 kinds=menu,bar-widget
prune  key=nixarchy.podman … enabled=true active=true profile=own-service|no-bar|no-indicators|no-menu expected=own-service|no-bar|no-indicators|menu
revoke key=nixarchy.podman
```

The plugin is enabled throughout. The only difference is the `menu` flag, and it
comes from the array check.

This is the same trap nixarchy-podman's `AGENTS.md` records for its own code: lists
read through a QObject `var` property are Qt sequence wrappers, not JS arrays.

## Proposed outcome

- On a nixarchy machine, a keep-loaded plugin keeps a working `shell` API across
  `shell.json` changes. The Podman menu picks up `omarchy bar set` on its next
  open, with no shell restart.
- The fix is carried the way the #749 `shell.qml` patch is: marked CARRIED, anchored
  so an Omarchy bump that moves the line fails the build rather than silently
  dropping the fix, and deleted as soon as upstream has it.
- A check fails on today's `shell.qml` and passes with the patch.
- The upstream report is filed. It is already drafted, with the evidence above; the
  owner files it.

## Affected users and systems

- `pkgs/omarchy/default.nix`: one more patch to `shell/shell.qml`.
- Probably a check: `patched-files`, or a small test of `manifestHasKind` against a
  sequence-like object.
- `docs/internals/` or `pkgs/AGENTS.md`: the carried-patch record, if that is
  where #749's lives.
- Every nixarchy machine. The live check is on razer.
- Afterwards: nixarchy-podman can drop its "restart the shell" docs line, as a
  separate PR there.

## Constraints

- **`AGENTS.md` §11: a fix to how Omarchy behaves belongs upstream, not patched
  here.** This patch exists only because the owner asked for it. It must say it is
  carried, and it comes off when upstream fixes the line.
- Patches use `--replace-fail`, or an asserted anchor, so a moved line fails the
  build (`pkgs/AGENTS.md`, "Patching upstream").
- No change to omarchy's behaviour beyond reading `kinds` correctly. The profile
  strings, the revoke logic and the cache stay as upstream wrote them.
- Prove the check fails first (`AGENTS.md` §1).
- Nothing is filed upstream unprompted (§11). The owner files the report.

## Open questions

1. **Carry the patch, or only file upstream?** §11's default is upstream only. The
   owner asked for a local fix; this intent assumes approving it means "carry it,
   like #749".
2. **Scope.** `Array.isArray(...kinds)` appears in 18 places across `shell.qml` and
   `services/PluginRegistry.qml`. Only `manifestHasKind` is proven to misfire. Most
   of the others read manifests from `installedPlugins`, which is plain JS. Pick
   one:
   - (a) patch `manifestHasKind` only, and list the rest in the upstream report;
   - (b) patch every site.

   I recommend (a): one proven line, the smallest carried patch. An unproven site
   patched here is a guess re-applied at every bump.
3. **The safety net:** re-injecting `shell` into keep-loaded instances after
   `syncPluginApis` would make any future revoke harmless too. I recommend leaving
   it to upstream, and not carrying a second, larger patch.
