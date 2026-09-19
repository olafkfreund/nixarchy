---
status: approved
issue: 773
author: olafkfreund
---

# Intent: ai-mirror ships with nixarchy, and no agent takes the desktop without a human saying yes

Closes #773.

## Problem

[ai-mirror](https://github.com/olafkfreund/ai-mirror) lets a coding agent see
and drive the desktop: keyboard and mouse, screenshots, the clipboard, and the
accessibility tree. The owner wants it on every nixarchy machine. As it stands
that would hand desktop control to any agent that reaches it, because:

- **an agent can grant itself control.** `control mode=agent` is accepted from
  an agent with no human in the loop (`src/ai_mirror/control.py:86-97`);
- **observation needs no grant.** Screenshots, clipboard reads and
  accessibility reads all work while control is off (`src/ai_mirror/api.py`),
  and the red widget only shows when an agent holds control, so watching
  happens with nothing on screen;
- **anything with a shell can use it.** MCP registration decides which agents
  find it, but any agent with a shell can run the `ai-mirror` command itself.

Its Home Manager module also turns on accessibility for every GTK and Qt app in
the session. It needs a hand edit to `bindings.lua` before the kill switch
works. And its package leaves out the licence and notice it is required to
carry.

## Proposed outcome

The owner's decision, 2026-09-19:

- The `ai-mirror` binary, its bar widget (right section) and its kill switch
  (Super+Shift+Escape, seeded for new installs) are on every nixarchy machine.
- **No agent is connected to it automatically.** Registering it as an MCP
  server is a separate, explicit opt-in.
- **An agent cannot take control until a human confirms** on screen. That
  holds on every way in: MCP, the command line and the API.
- Whether watching (screenshot, clipboard, accessibility) also needs a grant,
  or at least a visible sign, is decided and written down.
- Session-wide accessibility is off unless the user wants it.

## Affected users and systems

Every nixarchy desktop, and every coding agent a user connects. On the
nixarchy side:

- `flake.nix` (the input);
- the default-plugin set (the widget);
- a new opt-in for MCP registration;
- the seeded binds, tests and docs.

In the ai-mirror repo: the human-confirm step, the observation decision, and
licence and notice files in the package.

## Constraints

- **No automatic MCP registration.** In particular, ai-mirror must not sit
  behind `programs.nixarchy.mcp`. That option is a boolean that defaults to
  true (`modules/nixos.nix:660`), so it would be on for everyone.
- **The human confirm lands upstream before this ships as a default.**
- **An existing home with no kill-switch bind cannot grant control** until it
  has a working stop mechanism.
- **Installed together with nixarchy-voice (#774), the two stay unconnected**
  unless the user opts in. That is tested at runtime, not only by reading the
  generated configuration.
- Accessibility defaults off in nixarchy, and a user's own accessibility
  settings are never forced off.
- Mode A stays inert, including environment variables.
- Every new check is proven to fail first (§1).

## Open questions

- **Does observation need its own grant, or only a visible indicator?** Screen
  and clipboard reads work with control off today. This is the owner's call,
  made with ai-mirror's change.

**On approval (2026-09-19):** whether observation (screenshots, clipboard, a11y) needs its own grant is decided in the spec and brought back to the owner. The default proposal is a visible indicator whenever it is observing.
