---
status: draft
issue: 1031
author: Olaf Freund
---

# Intent: hypr-rdp's Lua fallback never fires on Hyprland 0.56

## Problem

`programs.nixarchy.services.hypr-rdp` starts and immediately dies on
Hyprland 0.56.0:

```
failed to initialize display capture
  0: failed to set headless output resolution
  1: Hyprland IPC error: unknown request
```

The secret renders, the `ExecStartPre` guard passes, the headless output is
created. Only setting its resolution fails. Hyprland 0.56 dropped the legacy
`keyword` IPC request as part of the Lua-config migration this repo already
tracks (`monitors.lua`, `bindings.lua`).

hypr-rdp already carries the correct fallback — `keyword_monitor()` retries
through `eval hl.monitor({...})` — and it never fires, because the guard
`is_non_legacy_parser_error()` matches only the string `"non-legacy parsers"`
while 0.56 answers `"unknown request"`. Confirmed against the pinned source at
`src/hyprland.rs:250-254`.

So this is one string comparison away from working, and the RDP feature is
unusable on the compositor version every nixarchy machine runs.

## Proposed outcome

`systemctl --user start hypr-rdp` on a Hyprland 0.56 session brings the daemon
up, with a headless output at the configured resolution, and a client can
connect. Nothing about the packaging of `hypr-rdp` changes for a future
nixpkgs version.

## Affected users and systems

Anyone who sets `programs.nixarchy.services.hypr-rdp.enable`. Concretely p620
and p510, which were configured for RDP this week and have never had a working
daemon. The overlay attribute at `flake.nix:784` is the only place the package
is built.

## Constraints

- **Must not** change the cargo vendor hash. A `.rs`-only change leaves
  `Cargo.lock` alone, so the hash stays valid; anything touching dependencies
  does not.
- **Must** keep the exit cheap. `docs/internals/flake.md#the-rdp-daemon-...`
  says the overlay indirection exists so that deleting the input when nixpkgs
  carries hypr-rdp costs one line. Whatever carries the fix must go away with
  it.
- **Must** be dropped when upstream ships the fix. v0.1.6 is the newest tag and
  the narrow matcher is still on upstream `main`; a patch carried here is
  re-applied at every source bump (AGENTS.md §11).
- **Must not** file anything at `MuNeNiCK/hypr-rdp` without the owner's
  explicit word (AGENTS.md §11). This issue is about unblocking our fleet; the
  upstream report is a separate decision.
- The fix must be **proven red→green** against the real daemon, not only
  against a matcher unit test (AGENTS.md §1). `hyprctl keyword` and
  `hyprctl eval` were both exercised by hand on p620 already; that is evidence
  the fallback is correct, not that the patched binary takes it.

## Open questions

1. **Do we also report this upstream?** The routing rule says a fix to how the
   dependency behaves belongs upstream, and a carried patch is a recurring
   cost. I will not open anything at `MuNeNiCK/hypr-rdp` unless you say so.
2. **What can see this, and where?** #1030's check proves the closure builds
   with RDP enabled; nothing starts the daemon. A check that would have caught
   *this* needs a booted session with a compositor — `checks.session` territory,
   and possibly more than this issue should carry. The spec decides whether the
   probe lands here or is filed as its own issue (AGENTS.md §2).
