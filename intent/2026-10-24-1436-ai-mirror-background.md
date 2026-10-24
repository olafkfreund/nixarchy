---
status: approved
issue: 1436
author: olafkfreund
---

# Intent: show ai-mirror's background accessibility work on the site and in the manual

## Problem

nixarchy pins ai-mirror at `044eb25` (2.1.0). The site (`docs/index.md`)
never mentions ai-mirror. The manual (`docs/manual/plugins.md#ai-mirror`,
`docs/manual/ai.md`) describes an agent that drives the pointer and the
keyboard. It says nothing about what ai-mirror can now do without them:

- `a11y_act` reads back what it did.
- `set_value` moves a slider; `select` picks a list item.
- The agent can do all of this in a window you aren't using, while your
  cursor and keyboard stay yours.

It also doesn't say that every mutating call now needs `generation`, which
any user's own scripts will hit after the bump.

## Proposed outcome

- The ai-mirror input points at the new release tag (ai-mirror#72), and
  `nix flake check` passes, including `ai-mirror-mcp-remove`.
- The manual's ai-mirror section says what works in the background, in which
  apps (the measured table, linked, not copied), where it stops, and the
  `generation` change.
- The site gains a short ai-mirror showcase: one paragraph and the recording
  from ai-mirror#72, kept to the size the site's other media use.
- README parity holds (#831): anything the site claims, the README matches.

## Affected users and systems

Every nixarchy machine (ai-mirror is on by default), and readers of the
GitHub Pages site and the manual. The input bump changes what lands on
rebuild.

## Constraints

- It waits for the ai-mirror release. Nothing pins an untagged commit.
- The showcase file is reused from ai-mirror, not re-recorded.
- The site must not claim more than ai-mirror's measured table does.
- Work happens on a fresh branch from `main`. The open `feat/1177-pi-mcp`
  checkout is left alone.

## Open questions

1. Placement: a new "An agent that uses your desktop without taking it"
   section on `docs/index.md` next to "An agent that knows this machine"?
   I propose yes.
2. Should the media be hosted in nixarchy's `docs/` (as `nixarchy-demo.gif`
   is) or linked from ai-mirror's release assets? I propose a copy in
   `docs/video/`, matching the existing layout.

**Decided: as proposed** (new section on docs/index.md; media copied into docs/video/).
