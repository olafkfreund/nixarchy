---
status: approved
issue: 1566
author: olafkfreund
---

# Intent: an ai-mirror skill that asks "microVM or the real desktop?"

## Problem

When an agent is asked "test this application" or "do this on the desktop", it
has two places to do it, and nothing tells it so:

- **The real desktop**, through the host's `ai-mirror mcp`. The person has to
  grant control in a dialog, and the agent is then driving their actual session,
  windows, notifications and accounts.
- **A disposable microVM.** nixarchy already ships two templates with ai-mirror
  inside (`nixarchy vm templates`, measured on p620 2026-11-02):
  - `nixarchy-desktop`: the stock nixarchy desktop, 1280x800, 8 GiB, its vsock
    port open about 45 s after a cold boot;
  - `hyprland-ai-mirror`: plain Hyprland, lighter.

  In both, control is granted without asking, because starting the VM is the
  consent. The agent connects with
  `claude mcp add ai-mirror-<name> -- socat - VSOCK-CONNECT:<cid>:7000`.

An agent that does not know the VM path drives the real desktop by default.
One that does know it has to re-derive the steps from the template notes:
create, run detached, wait for the port, add the MCP server, clean up. The
cleanup is already being missed. p620 has a stale `ai-mirror-ai-mirror` MCP
entry pointing at a VM that no longer exists (`claude mcp list`: failed to
connect).

## Proposed outcome

- A skill `ai-mirror`, shipped with nixarchy's agent skills
  (`pkgs/omarchy/skills/`), triggers on requests to test an application, try
  something on the desktop, click through a UI, or drive a window.
- **Its first step is to ask the person**, in one question: *in a microVM
  (`nixarchy-desktop` template), or on this host's real desktop?* With one
  line of trade-off each:
  - VM: isolated and disposable, but slower, no GPU, and a first build can be
    long.
  - Host: real hardware and real data, but they must grant control and watch
    it.

  It does not pick for them.
- **Then it runs the chosen path end to end:**
  - VM: `nixarchy vm create <name> --template nixarchy-desktop`, then
    `vm run --detach`, then wait for the vsock port, then register the MCP
    server, then do the work. Getting the app into the guest is part of the
    path, through the host directory share.
  - Host: the ai-mirror loop as `AGENTS.md` describes it: `index`, then
    `control agent`, then wait for the grant, then observe and act, then
    `control off`.
- **Cleanup is part of the VM path:** stop and remove the VM unless the person
  wants to keep it, and remove its `ai-mirror-<name>` MCP entry.
- Facts the skill states are the measured ones from the template notes (boot
  wait, sizes, no GPU, notifications on DND), not new claims.

## Affected users and systems

- nixarchy: a new `pkgs/omarchy/skills/ai-mirror/SKILL.md`, and the place that
  installs the skills list, if it is enumerated.
- Every agent on a nixarchy host that has the skills (Claude Code, and the
  other agents that read them).
- No change to ai-mirror, the templates or `nixarchy vm`.

## Constraints

- The skill **asks**. It never starts a VM or asks for host control before the
  person has chosen, and it accepts a standing choice they state ("always use a
  VM for tests").
- It does not weaken ai-mirror's gate or describe the VM's auto-grant as
  anything but "starting the VM is the consent".
- Commands in it must be ones that exist (`nixarchy vm --help`, the template
  notes) and must be checked by running them once.
- The skill is text; no new package, dependency or service.

## Decisions (approved 2026-11-02)

1. Ships in nixarchy, `pkgs/omarchy/skills/ai-mirror/`.
2. The spec measures whether a server added with `claude mcp add` mid-session is
   usable without a restart; if not, the skill drives the guest's ai-mirror
   over the vsock socket with a JSON-RPC script.
3. Default template `nixarchy-desktop`; `hyprland-ai-mirror` only when the app
   needs nothing from the shell.
