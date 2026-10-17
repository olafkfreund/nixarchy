---
status: draft
issue: 1325
author: olafkfreund
---

# Intent: checks.menu-actions passes on edge, and each of its findings there is a decision rather than noise

## Problem

`checks.menu-actions` walks every menu row to the scripts it reaches, and
fails any row that reaches a hazard (pacman, a write to `/etc`, a user
service) without a decision in `data/menu-actions.nix`. On stable it passes.
On edge (Omarchy quattro, `edge-candidate`) it fails with 31 findings. They
were already there before main's latest merge, and are listed on #1325.

They fall into groups:

| rows | reaches | hazard |
|---|---|---|
| 7 `setup.default.browser.*`, `update.password.drive` | `omarchy-lifecycle-dispatch` | pacman |
| 8 `setup.default.editor.*` | `omarchy-install-hermes-cli` | systemctl-user |
| 6 `style.font.cjk.*` | `omarchy-restart-shell` | systemctl-user |
| 3 `setup.default.agent.{agy,kimi,ori}` | `omarchy-launch-openclaw` | systemctl-user |
| `setup.security.ssh-agent`, `remove.service.ssh-agent` | the ssh-agent scripts | systemctl-user, home-rm |
| `setup.security.fingerprint` | `omarchy-apply-lock` | etc-write |
| `style.theme` and `setup.default.agent.{gemini,antigravity}` | stale: no hazard reached | |

Some of these are probably not real. Every editor row reaching the Hermes
installer suggests the walker follows quattro's grouped dispatch scripts into
branches that row never takes (#1301 met the same shape in `menu-guards`). A
real hazard and a walker artefact are indistinguishable in the check's
output.

Nothing runs `menu-actions` against edge in CI. `omarchy-edge.yml`'s cheap
checks are `menu-verbs bin-ledger skill-parity panel-loaders review-pins
stable-eval`. So this has been red without anyone being told. #1304 recorded it and then closed.

## Proposed outcome

- `menu-actions` passes on the edge tree.
- Each finding has been decided on its merits:
  - a real hazard gets an entry or a patch, as on stable;
  - a walker artefact is fixed in the walker, so it does not need an entry
    that would hide a real one later;
  - a stale entry is removed.
- Stable stays green, and keeps its current counts.

## Affected users and systems

- Edge users, whose menu rows are the ones being judged.
- `data/menu-actions.nix` and `data/menu-exceptions.nix` on `edge-candidate`.
  Edge carries its own `data/` edits there.
- `.github/scripts/check-menu-actions.py`, if the walker is at fault. That
  file is shared with stable.

## Constraints

- **Stable must not move.** A walker change is shared, so `menu-actions` on
  main must stay green with the same counts.
- **§1:** each new classification, and any walker fix, needs a break that
  turns it red.
- **No upstream filing without approval** (§11), even where a quattro script
  is at fault.
- The edge branch is rewritten by the edge workflow. A carry has to survive
  the next `Edge: Omarchy quattro … on main …` merge, as earlier carries did.

## Open questions

1. **Should CI run `menu-actions` on edge?** Without that, this regresses
   silently again. It is a workflow change, so a maintainer decides (§11).
2. **Where do the artifacts and the fix live?** This intent proposes: the
   artifacts and any walker fix go on main, and the data entries are carried
   on `edge-candidate`.
