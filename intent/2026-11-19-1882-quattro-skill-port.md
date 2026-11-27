---
status: approved
issue: 1882
author: x
---

# Intent: port quattro's rewritten omarchy skill

## Problem

Omarchy quattro 2eb7eb3 rewrote its `omarchy` skill. The #1847 carry kept our `nixarchy` skill as it was, left upstream's new `apps.md` and `system.md` out (they teach pacman, the AUR and passwordless sudo), and recorded nine new command groups and new example requests as not carried. An agent on a quattro machine gets no guide for default apps, web apps, installing software, environment variables, power profiles or the dock.

## Proposed outcome

The nixarchy skill has its own `apps.md` and `system.md`, written for NixOS, linked from SKILL.md; SKILL.md lists the new command groups and examples where they exist on this port; data/skill-parity.nix rows move from omitted to adapted or preserved.

## Affected users and systems

Every agent on an edge (quattro) machine; the docs are shared by both pins, so nothing they say may be false on main's v4.5.0 tag.

## Constraints

Nothing Arch-shaped. A command that exists only on quattro says so. No change to what ships under main's pin beyond prose.

## Open questions

None (owner pre-approved, 2026-11-19).
