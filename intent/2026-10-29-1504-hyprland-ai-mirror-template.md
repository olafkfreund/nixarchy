---
status: approved
issue: 1504
author: olafkfreund
---

# Intent: a sandbox desktop an agent drives with ai-mirror

## Problem

ai-mirror (#773) lets an agent drive the user's **real** Hyprland desktop.
A human approves each grant in a dialog, and a kill switch ends it. That is
right when the work is on the user's own desktop. For "other testing" it is
the wrong place: trying an app, a config or something risky. The agent's
windows land on the user's screen, and the agent sees the user's files and
session. Today there is no second place to send that work.

The `hyprland` microvm template (#821,
`modules/microvm/templates/hyprland.nix`) is already a headless, throwaway
Hyprland guest built for automation: grim, AT-SPI wired up, one fixed
1920x1080 output, and no window on the host. Nothing inside it speaks
ai-mirror, so an agent cannot drive it with the tools it already uses.

Measured on 2026-10-29 against `origin/main` `85b84dd`:

- The guest's Hyprland (`pkgs.hyprland`) is 0.56.2, so ai-mirror's Lua
  dispatch works there. ai-mirror finds the compositor through
  `hyprctl instances` (`src/ai_mirror/host.py:24`), and this needs no host
  setup.
- Nothing can grant control in the guest. `control agent` only writes
  `owner: pending`, and the approval dialog is part of the Omarchy shell,
  which this plain-NixOS guest does not run. The request expires after
  30 s.
- Nothing on the host can reach the guest. `modules/microvm/guest.nix`
  documents "no SSH, no host network surgery": the serial console is the
  only door.

## Proposed outcome

- `nixarchy vm templates` lists a new template, `hyprland-ai-mirror`. It is
  the `hyprland` template with ai-mirror running inside it.
- An agent on the host adds the VM as a second MCP server next to the real
  one, for example `ai-mirror-sandbox`. It uses the same tools (`screenshot`,
  `input`, `windows`, `launch`, `a11y_*`, `wait`) against the VM's desktop.
- Control in the guest is granted without a human. Starting the VM is the
  consent. The real desktop's gate is unchanged: it still asks every time.
- Stopping the VM ends everything, and nothing it did survives.
- No live view. The user has said a headless guest is fine.

## Affected users and systems

- Users of `nixarchy vm run` and declarative `services.microvm` machines.
- `modules/microvm/templates/` (new template), `data/microvm-templates.nix`
  (catalogue entry), the docs for VM templates, and possibly the runner if
  the host connection needs a per-VM setting.
- ai-mirror itself: no change expected. Any change there would be a separate
  ai-mirror issue.
- The existing `hyprland` template stays as it is. Its header promises
  "plain NixOS … no plugins".

## Constraints

- **The real desktop's gate does not change.** The auto-grant exists only
  inside the guest's closure. Nothing on the host can turn on auto-grant for
  the real desktop (ai-mirror AGENTS.md: "Control is a request a human
  answers").
- **No route from the guest to the host's compositor.** An action meant for
  the sandbox must never reach the real desktop. The guest has no host
  Wayland or Hyprland socket, and the host-side MCP entry is a separate
  server, never a fallback.
- **guest.nix's choice stands:** no SSH login in the disposable guest unless
  the spec argues for it. The host connection is a narrow channel that
  carries ai-mirror's stdio MCP and nothing else.
- **The template is built in CI like the others.** The catalogue must still
  evaluate for everyone: no unfree packages, and no secrets in the closure.
- **No change to ai-mirror's ownership model** that the real desktop would
  inherit.

## Open questions

1. **Host connection.** My default is vsock: `ai-mirror mcp` behind a
   guest listener, and `socat - VSOCK-CONNECT:<cid>:<port>` as the host's MCP
   command. It needs the host's `vhost_vsock` and a CID per running VM. This
   is not yet measured with this runner. The alternative is a forwarded SSH
   port with a key, which `guest.nix` deliberately avoids.
2. **Disposable, declarative or both?** `nixarchy vm run` VMs share one
   closure, so a CID baked into the closure allows one sandbox at a time.
   Proposed: the disposable path first, one sandbox at a time, with that
   limit stated in the template's note.
3. **How the auto-grant works.** Proposed: a guest-only user service that
   confirms pending requests with `ai-mirror control confirm <id>`, so
   ai-mirror's code is untouched. The alternative is a guest-only ai-mirror
   setting, which would be an ai-mirror change.
4. **Is Chromium needed?** It is roughly a sixth of the `hyprland`
   template's 5.2 GiB. The new template inherits it by importing that
   template. Proposed: keep it, because a browser is a common thing to test.

## Decisions (owner, 2026-10-29)

Approved with the proposed defaults: 1. vsock, measured in the spec before
it is relied on; 2. the disposable path first, one sandbox at a time;
3. a guest-only confirming service, with no ai-mirror change; 4. Chromium
kept.
