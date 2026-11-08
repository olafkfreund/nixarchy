---
status: draft
issue: 1659
author: olafkfreund
---

# Intent: reboot and power-off ask for authorisation before closing windows

## Problem

`omarchy-system reboot|shutdown` (upstream Omarchy, shipped unchanged in
`pkgs/omarchy`) tries to close every window (`omarchy-hyprland-window-close-all
--wait`, line 53), clears the "restart required" marker, and only then runs
`systemctl reboot|poweroff --no-wall` (lines 22-23).

When polkit wants a password for that call, as the owner's own
`nixos_config#2761` makes it for every caller on p620 and razer, a
cancelled or failed password leaves the user with every window closed and
the machine still up. A dialog left unanswered past the menu unit's
`RuntimeMaxSec=30s` gets the unit killed with nothing reported.

On a stock nixarchy machine, logind allows reboot for the active local
session without a password, so the bug needs a polkit rule that nixarchy
itself does not ship.

## Proposed outcome

- Reboot and power-off check authorisation first. Windows close only after
  it succeeds.
- A refusal, a cancel or a timeout leaves the windows and the marker as they
  were and says so in a notification.
- No change for a machine where no password is asked.
- Each promised outcome (refused, cancelled, timed out) has a probe, or the
  promise is narrowed to what a probe can see.

## Affected users and systems

- Anyone whose polkit asks for a password on `org.freedesktop.login1.reboot`
  or `power-off`: the owner's p620 and razer today, and any user with a
  hardened polkit.
- `omarchy-system` (upstream script). The 30-second limit is its own
  `systemd-run --property=RuntimeMaxSec=30s` (line 75), so both halves are
  upstream code. nixarchy's only polkit rule (`modules/nixos.nix:1857`)
  covers `pkexec env` and does not touch login1.

## Constraints

- **§11 and the routing rules:** this changes how Omarchy itself behaves,
  and such a fix belongs upstream rather than as a patch carried here. Never
  file upstream unprompted.
- A carried patch, if chosen, follows `pkgs/AGENTS.md`'s patch rules
  (`--fuzz=0`, a check that fails when the hunk stops applying).
- `pkcheck` must be in the script's runtime inputs (§7, an undeclared
  command reads as a wrong answer).
- §2: the fix needs a probe. `checks.session` can install a polkit rule that
  denies, and assert the windows survive.

## Decisions (owner, 2026-11-08)

1. Both: carry a patch here now, because the owner's machines are hit, and the owner files it upstream (omacom/omarchy). The patch goes when upstream takes it. No agent files upstream.
2. The 30-second timeout is fixed in the same change: a killed unit reports a failure.
3. The one-prompt mechanism is the spec's main question.

## Open questions (as drafted)

1. **Where the fix goes:** carry a patch here, ask you to file upstream
   (omacom/omarchy), or both (carry now, drop it when upstream takes it)?
   Upstream on Arch hits the same thing under any polkit rule that asks for
   a password, so upstream is the natural home.
2. The 30-second timeout is in the same script, and it bounds the whole
   unit, not only the prompt. Fix it in the same change (report a failure
   when the unit is killed), or leave it to upstream?
3. A `pkcheck` first does not make the later `systemctl reboot` skip its own
   prompt: polkit asks again unless the rule's result is `auth_*_keep`. Which
   mechanism makes "authorised, then close windows, then reboot" one
   prompt? This is the spec's main question.
