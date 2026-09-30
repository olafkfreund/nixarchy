---
status: approved
issue: 1112
author: olafkfreund
---

# Intent: Stop first-run from pinning user units to old generations

## Problem

`pkgs/omarchy/enable-user-units.sh:28-43` calls `systemctl --user enable --now` for units that `modules/nixos.nix:1675-1778` already installs and wires through `wantedBy`. Enabling a linked NixOS unit can leave unit and target-wants links in `~/.config/systemd/user` pointing to that generation's store unit. Those links shadow `/etc/systemd/user`; after collection they can dangle, and before collection they can keep an obsolete definition. The issue reports this state on p620, including `omarchy-sleep-lock` not loading, so suspend can proceed without its lock service. The code confirms the enabling and declarative wiring; the p620 state is issue evidence, not reproduced in this intent gate.

The claim does not apply uniformly to every listed unit: the issue found `omarchy-crash-watch` loaded from `/etc` without a user link. The pending #1101 branch removes `bt-agent` from the first-run list and cleans only its two old links, while the remaining units are still imperatively enabled.

## Proposed outcome

First-run succeeds without creating user-level links for NixOS-managed units. Activation removes only obsolete links created by this behavior, including dangling ones, and preserves user-owned units. `omarchy-sleep-lock` resolves to the current `/etc/systemd/user` definition and loads at a graphical login. Verification identifies a missing or stale-shadowed Nixarchy unit before the user next suspends.

## Affected users and systems

Mode B machines with `programs.nixarchy.enable` and users who completed first-run; especially users whose first-run generation has been collected. The cleanup must cover normal users with homes outside `/home`, not system accounts or Mode A. `omarchy-sleep-lock` has the direct screen-lock impact; the monitor recovery, input method, and crash watcher are also in the first-run list when present.

## Constraints

- Rebase this branch onto main after #1101 merges, then generalise and replace its `pkgs/omarchy/cleanup-bt-agent.sh` cleanup instead of layering a second cleanup over it.
- Discover homes from evaluated `users.users` entries with `isNormalUser`; do not glob `/home/*`. Remove only links whose targets match the corresponding `/nix/store/*-unit-<name>.service/<name>.service` unit, at the exact user unit and target-wants paths. A user's own unit or link stays intact.
- A failed removal must warn and continue (`rm ... || true` under activation's `set -e`), so a read-only home cannot fail a system switch. Check both existing and dangling symlinks.
- Any cheap check must be break-proven. If the #1101 Bluetooth check is extended, limit its PATH dependencies to the commands it uses rather than pulling every Omarchy runtime dependency.
- No build, VM run, push, or PR at the intent gate. Keep #1101's pending work untouched until the rebase.

## Open questions

1. **What should first-run enable?** Owner approved stopping imperative enabling for the whole NixOS-managed list. These units already have `wantedBy`. If first-run needs one immediately, it uses `systemctl --user start`, never `enable --now`, so it creates no user-level link. Otherwise it starts at the next graphical login.
2. **Which links should cleanup remove?** Owner approved removing only the exact unit and `.wants` symlinks for this first-run list when `readlink` points at that unit's generated Nix store path. Preserve all other links and regular files, including user-authored units.
3. **How should verification report this?** Owner approved failure for any declared Nixarchy user unit that is `not-found` or shadowed by an obsolete generated-unit link in `~/.config`, with a clear cleanup hint. Report an intentional user-authored override distinctly rather than deleting it.
