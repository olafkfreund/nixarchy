---
status: draft
issue: 1192
intent: intent/2026-10-04-1192-greeter-crash-watch-panel-error.md
---

# Spec: no crash watcher in the greeter, and panel load errors that say what failed

## Design

### 1. Crash watcher: skip system users

In `modules/nixos.nix`, in the `omarchy-crash-watch` user unit (~line 1889),
add `ConditionUser = "!@system";` to `unitConfig`, next to the existing
`ConditionEnvironment` and `ConditionPathExists`.

`@system` matches every UID in the system range (below `SYS_UID_MAX`). That
covers `sddm` (uid 175 on p620) and any other greeter or service account that
runs a user manager. Real users are unaffected. The unit stays declared and
wanted, so nothing about real sessions changes.

`tests/options.nix` (~line 4069) already asserts that the unit file is
installed. Add one assertion after that loop:
`grep -qx 'ConditionUser=!@system' "$vm/etc/systemd/user/omarchy-crash-watch.service"`,
failing with a message that names the greeter.

### 2. Panel Loader error handler: carried patch

New `pkgs/omarchy/1192-panel-loader-errorstring.patch` (`-p1` against
`share/omarchy`), with a header in the style of `1155-panel-loaders-kept.patch`.
It says it's CARRIED, gives the upstream report link once it's filed, and
says when to drop it.

It replaces, in `shell/shell.qml`'s panel `Loader` `onStatusChanged`:

```qml
var detail = errorString && errorString() ? errorString() : ""
if (!detail && sourceComponent) detail = sourceComponent.errorString()
```

with:

```qml
var detail = sourceComponent ? sourceComponent.errorString() : String(source)
```

Qt 6's `Loader` has no `errorString()`, so the first line throws before the
fallback runs. The component's own `errorString()` is the real failure. When
there's no component, the source URL at least names the panel.

Applied in `pkgs/omarchy/default.nix` right after the `1155` line (~436),
using the same `patch -d "$out/share/omarchy" -p1 --forward --fuzz=0` form,
with a `# CARRIED (#1192)` comment. The two patches touch different hunks.

## Alternatives rejected

- **`ConditionUser=!sddm`:** names one greeter; GDM, greetd and any future
  greeter would each need adding.
- **Only stop the restart loop (`Restart=on-failure`, a start limit):** the
  watcher would still start in the greeter and fail once per login screen.
- **Delete the handler's detail entirely:** loses the one diagnostic that
  names a broken panel.
- **`substituteInPlace` instead of a patch:** the carried-patch convention
  exists so a reworded upstream fails loudly (`--fuzz=0`) and the header
  records why.

## Risks

- **Machines whose real user has a system-range UID** would lose the crash
  watcher. NixOS `isNormalUser` users start at 1000, so this is unlikely.
  The assertion message says so.
- **An upstream bump that rewords the handler** fails the build at patch time.
  That's intended: drop the patch if upstream fixed it, or regenerate it.

## Verification

- `nix flake check` on the branch, or at least the `options` and `session`
  checks.
- The built omarchy tree's `shell/shell.qml` contains the new line and no
  `errorString && errorString`.
- Downstream on p620, after the bump:
  - `systemctl --user -M sddm@ show omarchy-crash-watch -p ConditionResult`
    reports `no`;
  - no crash-watch restarts for uid 175 in the journal;
  - the watcher is still active in the real session.
