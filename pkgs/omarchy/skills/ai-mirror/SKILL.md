---
name: ai-mirror
description: >
  REQUIRED before driving a graphical desktop with the ai-mirror MCP tools —
  testing an app by clicking through it, taking screenshots of it, typing into
  its UI. It first asks whether to use a disposable microVM or this host's real
  desktop, and never starts a VM or asks for control before the answer.
  Triggers: test this app, test this application, try it on the desktop, click
  through, drive the UI, ai-mirror, microvm, in a VM, screenshot the app.
  For configuring the desktop itself use `nixarchy`.
---

# ai-mirror: a disposable VM or the real desktop

## 1. Ask first

Ask one question, then wait for the answer:

> Test in a disposable microVM (`nixarchy-desktop`), or on this host's real desktop?
> - **microVM:** nothing on your desktop is touched and control needs no dialog; the first run can be a long build and rendering is software-only.
> - **Real desktop:** instant and with the real GPU, but it moves your mouse and keyboard, and you approve a dialog.

If the person has already stated a standing preference, follow it without asking.
Do not start a VM or call `control` before the answer.

## 2. Host path

1. `ai-mirror index` first (keys, plugins, gotchas for this machine).
2. `control {mode: agent}` asks a human. Poll `status` until `owner` is `agent` or `off`; `off` means no. Say so and stop.
3. Prefer `shell_state`, `windows` and `a11y_find` to screenshots. Use the frame of the latest screenshot for `input`.
4. After a keypress that should open something, confirm with `wait` before depending on it.
5. `control {mode: off}` when done.

Rules: `not_owner` or `stale_generation` means the human stopped you: stop, observe, never retry blindly. `wrong_target`: you still have control but aimed wrong; observe and aim again. An `input` error with `delivered`/`of` means part of the batch landed; observe before retrying.

## 3. VM path

```sh
nixarchy vm create mirror-test --template nixarchy-desktop   # hyprland-ai-mirror if no shell is needed
nixarchy vm run --detach mirror-test                         # then wait ~45 s for the vsock port
```

- Build the app on the host and `launch` its store path in the guest: the guest shares the host store. Files go through `~/.local/state/nixarchy/microvm/<name>/share` (guest `/mnt/host`).
- Tell the person if the first build is long rather than waiting silently.
- Drive the guest with `mirror-vm`, next to this file (`~/.claude/skills/ai-mirror/mirror-vm`; `~/.agents/skills/…` for other agents; it is not on `PATH`). One call is one connection, so one batch is one session: control is granted automatically, then released at the end.

```sh
~/.claude/skills/ai-mirror/mirror-vm mirror-test steps.json --out ./shots     # "-" reads steps from stdin
```
```json
[
  {"tool": "status"},
  {"tool": "windows"},
  {"tool": "screenshot"},
  {"tool": "input", "args": {"actions": [{"type": "move", "x": 10, "y": 10}], "frame": "@last"}}
]
```

`"@last"` is the latest screenshot's frame id. Each screenshot is saved as `--out/NN-screenshot.png` (default `.`) and printed as a path; look at it with your image reader. Output is one JSON line per step. A tool error stops the batch (exit 1); exit 2 means the VM is not running, 3 means no grant within 30 s.

## 4. Cleanup

`nixarchy vm stop <name>`, then `nixarchy vm rm <name>`, unless the person wants to keep it. `stop` returns before the VM is down, and `rm` refuses a running VM: wait until `nixarchy vm list` shows it `stopped`. If an `ai-mirror-<name>` MCP entry was registered, `claude mcp remove ai-mirror-<name>`.

## 5. Limits

- `nixarchy vm templates` is the source of truth for the notes below.
- The guest is 1280x800 `Virtual-1` with software rendering: GL apps are slow.
- Notifications start on do-not-disturb; run `omarchy-shell notifications setDnd off` to test them.
- The first `nixarchy-desktop` run realises a 17.7 GiB closure unless the host already has most of it.
- The guest's ai-mirror still says "your real desktop" and "human-confirmed". In the VM path that is the guest, not the host.
- An MCP server added with `claude mcp add` mid-session is not usable until Claude Code restarts, so use `mirror-vm`.
