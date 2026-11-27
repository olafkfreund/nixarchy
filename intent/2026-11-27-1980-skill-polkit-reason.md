---
status: approved
issue: 1980
author: x
---

# Intent: the agent skill tells agents how to give a pkexec prompt its reason

## Problem

Omarchy rc1's `SKILL.md` tells agents to set the polkit dialog's reason before
a privileged action with `omarchy-shell -q omarchy.polkit expect "<cmd>"
"<reason>"`. nixarchy replaces `SKILL.md` wholesale
(`pkgs/omarchy/skills/nixarchy/SKILL.md`, recorded in `data/skill-parity.nix`)
and its Privilege Escalation section does not mention it, so agents here
never set a reason and the owner sees a bare authentication dialog.

## Proposed outcome

nixarchy's skill teaches the call, worded for pins whose shell supports it,
and `data/skill-parity.nix` records the decision.

## Affected users and systems

Agents on nixarchy desktops at a quattro or rc1 pin.

## Constraints

The 4.5 tag's shell has no `omarchy.polkit expect`; the text must not tell an
agent to call something that does not exist there. Both pins' skill-parity
must pass.

## Open questions

None.
