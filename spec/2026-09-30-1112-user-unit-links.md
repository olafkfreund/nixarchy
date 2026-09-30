---
status: draft
issue: 1112
intent: intent/2026-09-30-1112-user-unit-links.md
---

# Spec: Keep Nixarchy user units on the current generation

## Design

1. **Stop creating user links.** `pkgs/omarchy/enable-user-units.sh:27-43` currently checks which units exist and calls `systemctl --user enable --now`. Keep its missing-unit tolerance and `daemon-reload`, but use `systemctl --user start` for units first-run must run immediately; never call `enable`. The module already installs and starts these units through `wantedBy` (`modules/nixos.nix:1703-1774` on current main). Once #1101 merges, `bt-agent` is absent from the first-run list and the permanent unit is gone; do not restore either. Update the patch drift check at `pkgs/omarchy/default.nix:1541-1551` and the stale first-run rationale in `pkgs/AGENTS.md:619-645` to match the new behavior.

2. **Clean only generated links.** Rebase onto main after #1101 merges. Generalise and replace its `pkgs/omarchy/cleanup-bt-agent.sh:1-14` and `modules/nixos.nix:1157-1162` activation step, rather than running two cleanups. The cleanup covers the legacy `bt-agent` link plus the first-run units that NixOS declares: `omarchy-recover-internal-monitor`, `omarchy-sleep-lock`, `omarchy-crash-watch`, and conditional `omarchy-fcitx5`. For each, inspect only `~/.config/systemd/user/<unit>.service` and the corresponding `.wants/<unit>.service` (`graphical-session-pre.target.wants` for monitor recovery; `graphical-session.target.wants` for the others). Remove a path only when it is a symlink, including a dangling one, and its `readlink` target matches `/nix/store/*-unit-<unit>.service/<unit>.service`. Leave regular files, user-created links, and other targets untouched. A failed `rm` warns and continues; activation must not fail because a home is read-only.

3. **Find the actual users.** In `modules/nixos.nix`, derive cleanup homes from evaluated `config.users.users` entries whose `isNormalUser` is true, using each entry's configured `home`. Pass those homes explicitly to the cleanup script. This replaces #1101's `/home/*` scan, includes normal users living elsewhere, and excludes system users. Keep the activation under the existing `programs.nixarchy.enable` gate so Mode A does not change. The cleanup removes filesystem links; the user service manager still needs a daemon reload or fresh login to notice their removal. State that in the message shown to an affected user.

4. **Make stale units visible.** At `pkgs/verify.sh:306-310`, inspect `LoadState` and `FragmentPath` for the always-declared `omarchy-sleep-lock`, `omarchy-crash-watch`, and `omarchy-recover-internal-monitor` units, as well as their exact user-level unit links. Also inspect `omarchy-fcitx5` when the session's `INPUT_METHOD=fcitx` indicates the conditional module at `modules/nixos.nix:1764-1774` is configured. A declared unit that is `not-found`, or a unit shadowed by a generated store-unit link in `~/.config`, is a failure with a cleanup and reload hint. An intentional user-authored override is reported distinctly and left intact. Keep the existing active-state check for the sleep lock so an installed but stopped lock service still fails. Preserve #1101's separate permanent `bt-agent.service` failure check; the retired Bluetooth service is not a declared unit after #1101.

5. **Cover the real behavior.** Add a cheap `tests/user-unit-links.nix` runCommand wired into `flake.nix`. Run the actual first-run script with a stub `systemctl` that logs calls and models present/absent units; assert present units are started, absent units are skipped, and `enable` is never called. Run the cleanup against fixtures for generated links (including dangling), ordinary files, foreign links, read-only or failing removals, and a home outside `/home`; assert only generated links disappear and a failed removal warns without a nonzero activation result. Keep its PATH limited to commands the scripts use. Extend `tests/options.nix:3815-3832` to assert the evaluated activation names a normal user with a nonstandard home and excludes a system user, and that the declarative units retain their `wantedBy` links. `checks.options` runs in CI, not locally.

## Alternatives rejected

- Keep `enable --now` for units NixOS wires: it creates the generation-pinned links that caused this issue.
- Remove all user unit links or all files named like Nixarchy units: that can delete a user's own service or deliberate override.
- Keep #1101's Bluetooth-only cleanup and add a second script: it leaves the other affected units and the `/home/*` limitation.
- Treat an active sleep-lock process alone as proof: a dangling unit can leave an old process active until logout while the next login has no lock service.

## Risks

- Current-session user managers can cache a loaded old unit after link removal. Verification must distinguish on-disk cleanup from runtime state; tell users to reload the user manager or log out. Do not kill arbitrary processes during activation.
- A first-run unit whose start depends on a session target may not start during provisioning; `wantedBy` starts it at the next graphical login. First-run must still complete successfully if an optional unit is absent.
- The unit names and `.wants` directories are deliberately finite. If the module adds a new first-run unit, update this list and its check together.
- #1101 has not merged yet. Rebase first, preserve its pairing design and verification, and adapt its Bluetooth cleanup test. A broad PATH over all Omarchy runtime dependencies in that test could fetch gigabytes; filter to the tools it invokes.

## Verification

- Prove the cheap check can fail before accepting it: copy `pkgs/omarchy/enable-user-units.sh` aside outside the worktree, reintroduce `enable --now`, run `checks.user-unit-links` under the shared build lock and capture the red line, restore with `cp`, then show green. Separately copy the cleanup script aside, remove the generated-link removal, show its fixture fail, restore, and show green. Use the same copy-and-restore method for a break that lets a foreign link be removed. Never use `git checkout` to restore proof edits.
- The evaluated `tests/options.nix` case verifies the normal user with a nonstandard home and the declarative `wantedBy` wiring; CI runs `checks.options` because it is too large for the local cheap-check gate. Break its assertion by removing the home enumeration in a controlled copy/restore proof when that check is run.
- With CI idle, build the patched Omarchy package and the cheap check under the shared lock. After any `.nix` edit run `nix fmt`, inspect `git diff --stat`, and run `nix fmt -- --ci`, statix, and deadnix. Keep the CI text guards clear (`producer | grep -q`; writes to `omarchy/shell.json`).
- On a machine that had first-run links, inspect `systemctl --user show -p LoadState -p FragmentPath omarchy-sleep-lock.service` after activation and daemon reload or logout: it loads from `/etc/systemd/user`, the stale links are gone, and `nixarchy-verify` reports the lock service active. Also check a user-owned override remains untouched.
