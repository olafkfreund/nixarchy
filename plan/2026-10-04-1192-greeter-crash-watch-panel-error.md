---
status: draft
issue: 1192
spec: spec/2026-10-04-1192-greeter-crash-watch-panel-error.md
---

# Plan: no crash watcher in the greeter, and panel load errors that say what failed

## Decisions (from the approved spec)

- Add `ConditionUser = "!@system";` to the `omarchy-crash-watch` user unit,
  and assert it in `tests/options.nix`.
- Add the carried patch `pkgs/omarchy/1192-panel-loader-errorstring.patch`,
  replacing the panel `Loader`'s
  `errorString && errorString()` handler with
  `sourceComponent ? sourceComponent.errorString() : String(source)`.
  Apply it right after `1155` in `pkgs/omarchy/default.nix` with
  `--fuzz=0`.

## Steps

1. `modules/nixos.nix` ~1894 (`omarchy-crash-watch.unitConfig`): add
   `ConditionUser = "!@system";` with a one-line comment (the greeter's user
   manager is a system user).

   Verify by
   `nix eval .#nixosConfigurations.<test-host>.config.systemd.user.services.omarchy-crash-watch.unitConfig.ConditionUser`,
   or by grepping the generated unit in a check build.
2. `tests/options.nix` ~4072, after the unit-existence loop: add
   `grep -qx 'ConditionUser=!@system' "$vm/etc/systemd/user/omarchy-crash-watch.service"`,
   failing with a message that names the greeter.

   Verify by building that check.
3. `pkgs/omarchy/1192-panel-loader-errorstring.patch` (new):
   - **header** in the style of the `1155` patch: CARRIED; why; the upstream
     report (filled in once filed); "drop when upstream fixes it";
   - **body** is a `-p1` hunk against `shell/shell.qml`, generated from the
     omarchy input's source (`nix flake metadata`, then the store path), with
     `diff -u`.

   In `pkgs/omarchy/default.nix`, after the `1155` `patch` line (~436),
   add `# CARRIED (#1192): …` and the `patch -d "$out/share/omarchy" -p1
   --forward --fuzz=0 < ${./1192-panel-loader-errorstring.patch}` line.

   Verify by building the omarchy package: `grep -c 'errorString &&'` on the
   output's `share/omarchy/shell/shell.qml` returns 0, and the new line is
   present.
4. Run `nix flake check`, or at least the `options` and `session` checks.
   Commit one per step, then open a PR linking the intent, spec and plan.
   Merge it once CI is green.

## Tests

- The `options` check passes with the new assertion. Reverting step 1 makes
  it fail.
- The omarchy build applies the patch, and the output carries the new
  handler.
- Downstream, after `nix flake update nixarchy` in nixos_config:
  `systemctl --user -M sddm@ show omarchy-crash-watch -p ConditionResult` is
  `no` on p620.

## Rollback

Revert the PR in nixarchy, and bump nixarchy downstream.
