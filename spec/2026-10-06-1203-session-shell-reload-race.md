---
status: draft
issue: 1203
intent: intent/2026-10-06-1203-session-shell-reload-race.md
---

# Spec: the session check does not race the shell's reload

## What `hyprctl reload` does to the shell

The intent asked what the reload triggers and what signals the end of it.
Read from the omarchy 4.0.4 tree:

- The shell is not restarted. `omarchy-launch-shell` runs only from
  `hl.on("hyprland.start", ...)` (`default/hypr/autostart.lua:6`), not on a
  reload.
- The shell does not listen for the reload either: the only `configreloaded`
  handler is the keyboard-layout bar widget
  (`shell/plugins/bar/widgets/KeyboardLayout.qml:100`).
- What the log shows (every panel's `IpcHandler` registering again at
  131.4-131.8 s) is Quickshell re-creating its per-screen windows after
  Hyprland re-applies its config. Until that finishes, IPC calls queue behind
  it, and the client's 2 s timeout expires.

So no event marks "reload finished", and a `ping` wait would pass before the
rebuild starts and move the race rather than remove it (the intent's question
1).

## Design

### Retry the summon, not a wait before it

`summon` is idempotent. `shell.summon()` (`shell/shell.qml:1170`) marks the
panel open in `openPanelIds`; a second summon of an open panel leaves it open.
It is not a toggle. A request that timed out on the client and is processed
late, followed by a retry, still ends with one open menu.

In `tests/session.nix:742`,

```python
machine.succeed(on_desktop("omarchy-menu summon install"))
```

becomes a retry until the shell answers, with a 60 s budget (the same
headroom the file gives `omarchy-shell shell ping` after a restart, `:2366`).
If the budget runs out, raise an `AssertionError` that says the shell did not
answer IPC within 60 s of a `hyprctl reload`, and names #1203. That keeps the
failure readable instead of ending on the client's "omarchy-shell is not
running".

The existing assertion right after it (the `omarchy-menu` layer appears within
30 s) is unchanged, so the check still proves #1069.

### Scope

Only `:742`. It is the one IPC call that follows a `hyprctl reload`
directly. The reload at `:719` is followed by `hyprctl getoption`, which asks
Hyprland, not the shell (intent question 2). A shared helper for one call
site is not worth it.

`OMARCHY_SHELL_IPC_TIMEOUT` is left alone (intent question 3). The retry
already absorbs a slow reload, and raising the timeout would also hide a shell
that is slow in general.

## Alternatives rejected

- **Wait on `omarchy-shell shell ping` before summoning.** It can answer
  before the rebuild starts, so it moves the race instead of closing it.
- **`OMARCHY_SHELL_IPC_TIMEOUT=10s` on the summon.** It probably works, but
  it is a guessed number, and it hides a shell that answers slowly for any
  reason.
- **A fixed `sleep` after the reload.** Ruled out by the intent.
- **Removing the second `hyprctl reload`.** It cleans up the Hyprforge file
  for the later sections; without it they run with `border_size = 7`.

## Risks

- **A shell that really died now takes 60 s to report it**, instead of 2 s.
  The cost is a minute of runner time on a run that is failing anyway.
- **The menu opened by a late first request, and then the retry**: summon is
  idempotent, so there is still one menu. The close at `:756` closes it.

## Verification

- `nix build .#checks.x86_64-linux.session` passes on p620. It is a ~15-25 min
  VM test, and the run is announced on the agent bus first.
- The race itself is not reproducible on demand. The change is checked by
  reading: the only remaining immediate IPC call after a reload is the
  retried one.
- `nix fmt -- --ci`, statix, deadnix and the repo's `tests/AGENTS.md` rules:
  no new `| grep -q`.
