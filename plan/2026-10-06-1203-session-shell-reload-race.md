---
status: approved
issue: 1203
spec: spec/2026-10-06-1203-session-shell-reload-race.md
---

# Plan: the session check does not race the shell's reload

## Approved decisions (from the spec)

- `hyprctl reload` does not restart the shell. Quickshell rebuilds its
  per-screen windows, IPC queues behind that, and the client's 2 s timeout
  expires. No event marks the end, so a `ping` wait would only move the race.
- `summon` is idempotent (`shell.summon()` sets `openPanelIds`; it is not a
  toggle), so the summon itself is retried until the shell answers, for up
  to 60 s. On timeout, an `AssertionError` says the shell did not answer IPC
  within 60 s of a `hyprctl reload` and names #1203.
- Only `tests/session.nix:742` changes. No helper, no
  `OMARCHY_SHELL_IPC_TIMEOUT`, no sleep.

## Steps

1. **`tests/session.nix:742`.** Replace
   `machine.succeed(on_desktop("omarchy-menu summon install"))` with a
   `try`/`except` around
   `machine.wait_until_succeeds(on_desktop("omarchy-menu summon install"), timeout=60)`.
   The `except` raises `AssertionError` with the #1203 message, chained with
   `from` the original exception. Add a two-line comment above it: why it
   retries (the shell rebuilds its windows after the reload, so IPC can miss
   the 2 s client timeout) and why that is safe (summon is idempotent).
   Leave the layer assertion and the close after it unchanged.
   → verify by `nix build .#checks.x86_64-linux.session -L` passing on p620,
   announced on the agent bus first (a ~15-25 min VM test). Confirm in the
   log that the summon line ran under `wait_until_succeeds`.
   Traps: `tests/AGENTS.md`: no `| grep -q` in a probe. The test-driver
   exception type on timeout is whatever `wait_until_succeeds` raises (a
   `RequestedAssertionFailed`/`Exception`), so catch `Exception`, not a
   narrower name that may not exist in this nixpkgs' driver. Keep the
   original `on_desktop` quoting.

## Tests

- `nix build .#checks.x86_64-linux.session -L` → passes.
- `nix fmt -- --ci`, statix, deadnix → clean.

## Rollback

Revert the PR. The check goes back to failing on the race now and then.
