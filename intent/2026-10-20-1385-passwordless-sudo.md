---
status: draft
issue: 1385
author: olafkfreund
---

# Intent: Omarchy's timed passwordless sudo works on nixarchy

## Problem

On edge, the top panel's passwordless-sudo icon (quattro's
`PasswordlessSudo` indicator) opens a terminal that prints a NixOS
explanation and ends `Failed (exit code 1)`. The menu row *Setup >
Security > Passwordless Sudo* does the same on stable 4.0.6. The owner
wants the feature to work.

It fails by design today. `pkgs/omarchy/nix-bin/omarchy-sudo-passwordless`
(bin-ledger `replace`) replaces upstream's command, because:

- upstream grants access by writing
  `/etc/sudoers.d/99-omarchy-nopasswd-<uid>`, but NixOS's `/etc/sudoers`
  has no include for `/etc/sudoers.d`, so the file would never be read;
- the 4.0.5-era upstream script then printed "enabled" regardless, a lie
  about a security state.

`docs/manual/security.md` explains this and points at
`security.sudo.extraRules`, which has no timer: it stays until removed and
rebuilt. #1280 hid the menu row on newer releases rather than offer
passwordless root one click away. Quattro's panel icon brought the command
back into reach, still failing.

There are two upstream designs:

- **4.0.6 (stable):** a simple script. It writes the file with `sudo tee`
  and arms a `systemd-run` timer that deletes it after N minutes (15 by
  default).
- **Quattro (edge):** a hardened rewrite (`docs/passwordless-sudo.md`):
  - timed grants whose deadline sudo itself enforces (`NOTAFTER`), so they
    hold across suspend;
  - grant files validated with `visudo` and renamed into place
    atomically;
  - a lock at `/run/lock/omarchy-sudo-passwordless.lock`;
  - a boot-time tmpfiles cleanup rule
    (`/etc/tmpfiles.d/omarchy-nopasswd-sudo.conf`) that new grants
    require to exist;
  - permanent grants;
  - a no-prompt status probe for the panel indicator, through installed
    root "internal actions";
  - pacman hooks, which are Arch-only.

The common precondition: **sudo must read `/etc/sudoers.d`, and that
directory must be root-owned and writable only by root.** Neither is true
on NixOS today.

## Proposed outcome

- Clicking the panel icon, or the menu row, gives upstream's behaviour:
  1. the warning;
  2. a confirmation;
  3. a duration;
  4. passwordless sudo for that long;
  5. automatic expiry;
  6. the icon going red while it is active, and a click turning it off.
- Nothing is granted until the user confirms in that flow. Sudo reading
  `/etc/sudoers.d` grants nothing on its own, since only root can write
  there.
- Expiry survives reboot: a boot-time cleanup removes timed grants, as
  upstream does.
- Users who do not want the feature can turn it off declaratively, which
  also removes the include.
- The manual's security page describes what it does here instead of
  saying it cannot work.

## Affected users and systems

- Every nixarchy machine, if on by default. Its sudo configuration gains
  one include line.
- Stable (4.0.6's simple script) and edge (quattro's rewrite), which ship
  different upstream commands. The NixOS side, meaning the include, the
  directory and the boot cleanup rule, can be shared.
- Files: `modules/nixos.nix` (sudo, tmpfiles); the stub, which is deleted
  so upstream's command is vendored; `data/bin-ledger.nix`;
  `docs/manual/security.md`; the menu/visibility rule from #1280.

## Constraints

- **Security first.**
  - The include is `@includedir /etc/sudoers.d` with the directory 0750
    root.
  - `visudo` must accept the generated `/etc/sudoers`.
  - Nothing user-writable ever reaches sudo's policy.
  - The quattro version's own checks (`verify_root_path`, the lock, the
    tmpfiles precondition) must pass as written, not be patched away.
- **Mode A (§7):** someone importing `nixosModules.nixarchy` into their
  own configuration must not have their sudo policy changed unless they
  opt in. Installer-managed machines may default on.
- **§14 coexistence:** a user's own `security.sudo.extraConfig` or
  `extraRules` must merge, not be replaced. A fixture covers a user with
  their own `extraConfig`.
- **§1/§2:** a check proves a grant file in `/etc/sudoers.d` is honoured
  (red without the include), and a VM check proves the full flow: grant,
  sudo without a password, expiry or disable, password required again.
- Pacman hooks are not ported (`na`), and the rows say so.

## Open questions

- **Default:** I propose it is on for installer-managed machines
  (`programs.nixarchy.installerManaged`) and off in Mode A, behind
  `programs.nixarchy.security.passwordlessSudoToggle` (a bool). When it is
  off, the stub's message stays, naming the option. Or should it be on
  everywhere nixarchy is imported?
- **Edge first or both?** Quattro's rewrite has more moving parts (fixed
  root action paths, which assume `/usr/bin`, and the tmpfiles
  precondition). I propose doing the shared NixOS side plus stable's
  simple script first, then edge's rewrite as a second PR on
  `edge-candidate`, so the stable fix is not held up by the port.
