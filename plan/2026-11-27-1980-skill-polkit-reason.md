---
status: approved
issue: 1980
spec: spec/2026-11-27-1980-skill-polkit-reason.md
---
coders:
  1: agy     # a documentation port with a ledger note
reviewers:
  - codex
---

# Plan: the agent skill tells agents how to give a pkexec prompt its reason

Decisions: the spec's design, unchanged. Worktree `/mnt/data/vmtest/wt-1980`,
branch `fix/1980-skill-polkit-reason`, off the #1975 Phase 1 edge branch.

## Steps

1. `pkgs/omarchy/skills/nixarchy/SKILL.md`: add the paragraph and example to
   `## Privilege Escalation` as the spec says. `data/skill-parity.nix`: note
   the port in that section's reason (do not change the hashes; they describe
   upstream). Verify (lead): `checks.skill-parity` and every check reading
   the skill pass under rc1 and under main's 4.5 tag.
   Traps: house style is short paragraphs, plain words; the README's skill
   counts must not move.

## Tests

Skill checks under both pins.

## Rollback

Revert the commit.
