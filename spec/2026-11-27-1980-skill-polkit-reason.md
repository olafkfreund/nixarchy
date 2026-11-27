---
status: approved
issue: 1980
intent: intent/2026-11-27-1980-skill-polkit-reason.md
---

# Spec: the agent skill tells agents how to give a pkexec prompt its reason

## Design

Add to the Privilege Escalation section of
`pkgs/omarchy/skills/nixarchy/SKILL.md` a short paragraph and example, ported
from rc1's text (`default/agents/skills/omarchy/SKILL.md`, the block around
`omarchy-shell -q omarchy.polkit expect`): build the command as an array, call
`omarchy-shell -q omarchy.polkit expect "${cmd[*]}" "<who and why>"`, then
`pkexec "${cmd[@]}"`; the reason applies once, to the next matching prompt
within a minute. Worded so it is safe where the call does not exist: "if
`omarchy-shell` has the `omarchy.polkit` target" (it fails quietly otherwise,
and the prompt simply has no reason). Keep nixarchy's own sudo-versus-pkexec
rules as they are.

`data/skill-parity.nix`: the section's reason notes the port.

## Alternatives rejected

- Copy upstream's whole section: it carries Arch-specific advice nixarchy's
  replacement deliberately drops.

## Risks

Skill tests (`checks.skill-parity`, and any check reading the skill's text)
under both pins.

## Verification

`checks.skill-parity` and the other skill checks pass under rc1 and main's
4.5 tag.
