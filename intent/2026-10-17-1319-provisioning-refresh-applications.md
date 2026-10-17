---
status: draft
issue: 1319
author: olafkfreund
---

# Intent: First-login provisioning must not overwrite the user's launchers or links

## Problem

`omarchy-provision-user` calls `omarchy-refresh-applications` on first login
(line 118 of the built script). #1304 replaced Restore's call to it, but
provisioning still runs it unchanged. It can lose data in two ways:

- **Launchers.** It runs
  `cp -f --no-preserve=mode "$OMARCHY_PATH"/applications/*.desktop ~/.local/share/applications/`.
  This overwrites a launcher the user edited. It also replaces a Home Manager
  link with a regular file, because `-f` unlinks a target it cannot open.
- **mise stubs.** `install/user/mise.sh` → `omarchy-mise-install` runs
  `rm -f ~/.local/bin/<cmd>` and writes a stub whenever nothing outside
  `~/.local/bin` provides `<cmd>`. A Home Manager link at
  `~/.local/bin/claude` is exactly that case. The stub then shadows the Nix
  package (#707).

Home Manager activates before the first graphical login, so both can hit a
fresh machine. Provisioning also re-runs on every login until it succeeds
once.

## Proposed outcome

- First-login provisioning seeds a launcher only where no file or link of
  that name exists.
- It never deletes or replaces anything in `~/.local/bin`, so the agents stay
  the Nix packages.
- A machine whose user already has Home Manager links finishes provisioning
  with every one of them intact.

## Affected users and systems

- New installs, and anyone whose provisioning marker is missing (#997's
  failure history).
- `pkgs/omarchy/nix-bin`. #1304's skip-if-present Restore lives there, and
  the shared seeding logic could too.
- `omarchy-provision-user`, which is vendored and called as is.
- `data/bin-ledger.nix`, which needs rows for whatever is replaced or patched.

## Constraints

- Reuse #1304's Restore logic rather than writing a second copy.
- Provisioning must still seed launchers on a clean home: the desktop must
  not come up empty.
- **The check:**
  - It pre-creates an edited launcher and a symlinked `~/.local/bin/claude`,
    runs the provisioning call, and asserts both are untouched.
  - Prove it fails on the current tree first (§1).
  - Isolate HOME and `XDG_*`, and assert the real home is untouched (§4).
- Mode A: users who are not on the Omarchy session are unaffected.

## Open questions

1. Replace `omarchy-refresh-applications` itself, for every caller, or only
   provisioning's call to it? Replacing it also covers any future caller.
2. Should provisioning write mise stubs at all on nixarchy? #1304 dropped
   them from Restore, because the agents are Nix packages.
