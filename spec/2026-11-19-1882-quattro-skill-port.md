---
status: approved
issue: 1882
intent: intent/2026-11-19-1882-quattro-skill-port.md
---

# Spec: port quattro's rewritten omarchy skill

## Design

New `pkgs/omarchy/skills/nixarchy/apps.md` and `system.md`, written from upstream's 2eb7eb3 text with every Arch instruction replaced by the NixOS answer: software through `programs.nixarchy` app selections and `nixarchy-apply` (not `omarchy pkg add` or the AUR), environment variables through Home Manager `home.sessionVariables` or uwsm `env.d`, updates through `omarchy update` = flake update plus rebuild, sudo as NixOS configuration. SKILL.md links both from Topic Guides and gains rows for the quattro command groups, each marked quattro-only where v4.5.0 lacks it. data/skill-parity.nix reclassifies the affected rows. pkgs/omarchy/default.nix stops removing apps.md and system.md, since ours overwrite upstream's on copy.

## Alternatives rejected

Shipping upstream's files with substitutions: too many Arch statements to patch line by line, and the next bump re-breaks them.

## Risks

A doc claim false on one pin. Mitigated by marking quattro-only commands and by skill-parity anchors.

## Verification

checks.skill-parity under both pins, readme-counts, the omarchy build, and a grep of the shipped skill for pacman, yay, AUR and /usr/.
