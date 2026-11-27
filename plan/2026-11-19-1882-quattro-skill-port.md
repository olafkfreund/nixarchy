---
status: approved
issue: 1882
spec: spec/2026-11-19-1882-quattro-skill-port.md
coders:
  1: agy  # long prose port of two guides and SKILL.md rows: large, mechanical once the rules are set
  2: codex  # skill-parity rows and default.nix: small, exact
reviewers:
  - codex  # read-only review of the docs for Arch leftovers
---

# Plan: port quattro's rewritten omarchy skill

Owner pre-approved (2026-11-19). Branch docs/1882-quattro-skill-port, off the #1847 carry.

## Steps

1. pkgs/omarchy/skills/nixarchy/apps.md and system.md (new), SKILL.md Topic Guides, Command Groups, Configuration Locations, Decision Framework and Example Requests: port from upstream 2eb7eb3 (/nix/store/pqvfr752ynpz9h92rjnvq55i6j3ndg3m-source/default/agents/skills/omarchy/) for NixOS. Verify: grep the files for pacman, yay, AUR, /usr/, `omarchy pkg`.
2. data/skill-parity.nix: reclassify the rows the port now covers; pkgs/omarchy/default.nix: drop the `rm -f` of apps.md and system.md. Verify: checks.skill-parity under both pins, omarchy build.

## Tests

checks.skill-parity (edge and tag), readme-counts --check, nix build .#omarchy, the grep in step 1.

## Rollback

Revert the branch; the carry's rm -f and omitted rows return.
