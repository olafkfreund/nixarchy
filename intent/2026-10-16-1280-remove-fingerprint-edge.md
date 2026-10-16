---
status: draft
issue: 1280
author: olafkfreund
---

# Intent: Removing fingerprint authentication works on edge

Follows `intent/2026-10-15-1285-quattro-hardware-ports.md`, which ported the
fingerprint resume hook to a declared NixOS unit.

## Problem

On the edge channel, Setup > Security > Remove fingerprint fails before it
does anything. `quattro`'s `omarchy-remove-security-fingerprint` gained two
things that stable's version does not have:

- **An identity step at the top**, which runs `/usr/bin/id -un` (or
  `/usr/bin/id -nu "+$SUDO_UID"` under sudo). NixOS has no `/usr/bin/id`, so
  the command fails and `|| exit 1` ends the script. The user sees nothing
  removed and no message that explains why.
- **`remove_resume_hook`**, which deletes
  `/usr/lib/systemd/system-sleep/fprintd-resume` and an fprintd
  `10-stop-timeout.conf` drop-in under `/etc/systemd/system`. On nixarchy
  neither file exists: #1288 declares the resume restart in the build, and
  `omarchy-apply-lock` no longer writes either file on edge. So the function
  is a no-op, but it is why the command is still a named `/usr` exception in
  `tests/session.nix`.

The PAM edit is not part of this problem. `remove_pam_config` is already
removed on both stable and edge, and the build refuses if any script still
names `/etc/pam.d/sudo`. The #1280 status comment said otherwise and needs
correcting.

## Proposed outcome

- On edge, the command runs to the end. It drops the packages, removes
  `/etc/pam.d/omarchy-lock-fingerprint`, and deletes the invoking user's
  saved prints under `/var/lib/fprint/<user>` as upstream intends. It still
  says that PAM is declared in the build.
- The user-name safety checks upstream added stay exactly as they are; only
  the path to `id` changes.
- The command leaves `tests/session.nix`'s `/usr` exceptions, and a check
  fails if either the `/usr/bin/id` call or the resume-hook paths come back.
- #1280 can close.

## Affected users and systems

- Edge users with a fingerprint reader who remove it from the menu.
- `pkgs/omarchy/default.nix` (an edge carry commit), `data/bin-ledger.nix`,
  `tests/session.nix`, and a check on the `edge` branch.
- Stable is unaffected: its version has neither addition.

## Constraints

- An edge carry, not a change to main (the #1278 design): main's package must
  not grow version conditionals.
- It must not weaken the identity check. It decides whose prints are deleted
  with `rm -rf`, so a wrong name there destroys someone else's data.
- `--replace-fail` on every edit, so a `quattro` change stops the edge build
  rather than shipping a half-patched script.

## Open questions

- Should `remove_resume_hook` become `:`, or be kept as is? It is harmless on
  NixOS, but keeping it means keeping the `/usr` exception. I recommend `:`.
