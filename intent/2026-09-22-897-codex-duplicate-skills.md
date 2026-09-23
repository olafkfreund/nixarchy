---
status: approved
issue: 897
author: olafkfreund
---

# Intent: Codex lists every nixarchy skill twice

## Problem

On every activation, `modules/home.nix:992` links each nixarchy skill into
four directories:

```sh
for agentdir in .agents/skills .claude/skills .codex/skills .pi/agent/skills; do
```

Codex reads two of them. The binary of Codex 0.155.1 contains both
`.agents/skills` and `.codex/skills` as skill paths. So Codex finds all 16
nixarchy skills twice (`nixos`, `nixos-doctor`, `devenv`, `nixarchy`, …).
This was measured on p620 on 2026-09-22: 16 of 16 names were present in both
directories, and both links pointed at the same store tree.

Today the two copies are identical, so the cost is noise: each skill appears
twice in Codex's skill list and takes twice the space in its context. It
becomes a real fault when the copies differ. That already happened once on
the same machine: a hand-written `home-manager` skill in `~/.codex/skills`
sat next to nix-skills' `home-manager` in `~/.agents/skills`. Codex then had
two different skills with one name and no rule for which one wins.

The list comes from upstream. `omarchy-provision-user` (Omarchy 4.0.4, line
87) links into five directories: the same four plus `~/.hermes/skills` and
each Hermes profile. So upstream has the same duplicate for Codex. nixarchy
already differs from upstream here, because it does not link Hermes.

## Proposed outcome

- On a nixarchy machine, Codex lists each nixarchy skill once.
- Claude Code, Pi and Antigravity see exactly what they see today.
- Links an earlier generation left in `~/.codex/skills` are removed on the
  next activation. They are not left in place until someone notices.
- Skills a user wrote by hand in any of these directories are never touched.
  That is the rule the current loop already follows: it removes only
  symlinks into a store skills tree.

## Affected users and systems

- Every nixarchy machine that has Codex installed. Claude Code, Pi and
  Antigravity users are unaffected, by design.
- `modules/home.nix` (the relink block) and its entry in `modules/AGENTS.md`
- Possibly upstream Omarchy, if the fix is also proposed there

## Constraints

- A Codex version that reads only `~/.codex/skills` must not lose the
  nixarchy skills. If such versions are still in use, "stop linking
  `.codex`" is not safe unconditionally.
- Must not remove anything a user placed in `~/.codex/skills` by hand.
- No new dependency. The change is to the existing shell loop.
- The divergence from upstream must be written down in `modules/AGENTS.md`,
  the way other deliberate differences are.

## Open questions

1. From which Codex release does `~/.agents/skills` work, and does any
   supported nixarchy channel ship an older one? This decides whether
   dropping `.codex` can be unconditional.
2. Fix it here only, or also report or patch it upstream in
   `omarchy-provision-user`? Upstream carries the same duplicate.
3. Unconditional, or behind an option (for example
   `programs.nixarchy.agentSkills.codexDir`) for users on an older Codex?
4. Out of scope unless you say otherwise: Hermes, which upstream links and
   nixarchy does not.
