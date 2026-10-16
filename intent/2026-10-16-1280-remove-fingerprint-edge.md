---
status: draft
issue: 1280
author: olafkfreund
---

# Intent: Removing fingerprint authentication leaves edge's `/usr` exceptions

Follows `intent/2026-10-15-1285-quattro-hardware-ports.md`, which ported the
fingerprint resume hook to a declared NixOS unit.

## Problem

On the edge channel, `omarchy-remove-security-fingerprint` is still one of the
named `/usr` exceptions in `tests/session.nix`, which #1280 is open for. The
reasons recorded for that are out of date:

- **The exception's comment says the command edits `/etc/pam.d/sudo` in
  place.** It does not. `remove_pam_config` is deleted on both stable and
  edge, and the build refuses if any script still names `/etc/pam.d/sudo`.
- **`/usr/bin/id` is already ported.** `quattro` added an identity step that
  runs `/usr/bin/id`, and edge's first carry (`050ad10a`, #1278) rewrote both
  calls to `/run/current-system/sw/bin/id`. The built script works.

What really keeps the command on the list is `quattro`'s new
`remove_resume_hook`. It deletes `/usr/lib/systemd/system-sleep/fprintd-resume`
and an fprintd `10-stop-timeout.conf` drop-in under `/etc/systemd/system`.
On nixarchy neither file exists: #1288 declares the resume restart in the
build, and `omarchy-apply-lock` no longer writes either file on edge. So the
function does nothing here, but it names `/usr`.

(An earlier draft of this intent said the command fails at `/usr/bin/id`. It
had compared the raw upstream file, not the patched one.)

## Proposed outcome

- On edge, `remove_resume_hook` is `:`, so the command names no `/usr` path.
  Everything else stays as upstream wrote it: the identity check, dropping the
  packages, removing `/etc/pam.d/omarchy-lock-fingerprint`, and deleting the
  invoking user's saved prints.
- The command leaves `tests/session.nix`'s `/usr` exceptions, and
  `data/bin-ledger.nix` gives the right reason for its patch.
- A check fails if the resume-hook paths come back.
- #1280 can close, and its status comment is corrected.

## Affected users and systems

- Nothing a user sees changes; this is bookkeeping and a guard.
- `pkgs/omarchy/default.nix`, `data/bin-ledger.nix` and `tests/session.nix`
  on the `edge` branch, as an edge carry commit.
- Stable is unaffected: its version has no `remove_resume_hook`.

## Constraints

- An edge carry, not a change to main (the #1278 design).
- `--replace-fail`, so a `quattro` change stops the edge build rather than
  shipping a half-patched script.
- The identity check is not touched: it decides whose prints `rm -rf` deletes.

## Open questions

None. Decided at the first approval: `remove_resume_hook` becomes `:`.
