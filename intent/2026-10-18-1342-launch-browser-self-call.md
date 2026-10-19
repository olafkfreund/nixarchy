---
status: approved
issue: 1342
author: olafkfreund
---

# Intent: upgrading to Omarchy 4.0.5 must not turn a link into an endless process chain

## Problem

Omarchy 4.0.5 ships `config/hyprland-mimeapps.list`, which sends http and
https links to `omarchy-browser.desktop`. That entry runs
`omarchy-launch-browser`. 4.0.5's own launcher knows to skip the entry when it
looks up the real browser (`omarchy-cmd-default-browser`).

nixarchy seeds `config/` into `~/.config` at every switch (`seed_dir`,
`modules/home.nix:1132`), so the new list appears the moment a machine
switches to 4.0.5. The session keeps running the launcher it logged in with:
Hyprland's `PATH` is fixed at login, and Quickshell and everything it starts
inherit it. The 4.0.4 launcher asks `xdg-settings`, gets
`omarchy-browser.desktop` back, so its `$browser_exec` is the launcher itself,
and `$browser_exec --help` calls it again, forever.

On p620 on 2026-10-18, 58 links in about 50 minutes became 206,000 processes
and a load average of about 1,850, on the host that also carries all four
self-hosted CI runners. Logging in again ended it. Killing chain members one
at a time made it worse (each orphan starts a new chain).

No nixarchy release ships 4.0.5 yet (the newest is v4.0.4-5), so every user's
first 4.0.5 upgrade is still ahead of them.

## Proposed outcome

- A machine that switches to 4.0.5 and opens a link before logging in again
  does not fork without bound. At worst the link fails to open, and says why.
- The release that ships 4.0.5 tells users to log in again after upgrading.
- A launcher whose resolved browser is itself refuses, rather than recursing,
  so the next skew of this shape also stops at one process.
- Something in CI can see the failure (§2).

## Affected users and systems

- Every nixarchy machine on its first switch to 4.0.5, until its next login.
- `pkgs/omarchy/default.nix` (the launcher), the seed in `modules/home.nix`,
  the release notes and the Discussions post.
- Hosts that share a process table with something else: p620 carries the CI
  runners.

## Constraints

- An Omarchy fix belongs upstream (§11). Here the running 4.0.4 launcher is
  upstream's own, and 4.0.5 upstream is consistent with itself. The skew comes
  from nixarchy seeding into a running session, so the fix is ours. A guard
  in the launcher is a carried patch, with `--replace-fail` and a ledger row.
- A guard in the 4.0.5 package cannot reach the 4.0.4 launcher already
  running. Only the seed side, or the user logging in again, can.
- Mode A: a user with their own `mimeapps.list` or browser setup is untouched.
- The seed never overwrites a user's file; that stays true.

## Open questions

1. **Hold the seed or not.** Should the seed skip `hyprland-mimeapps.list`
   while the running session predates it, and seed it on the next login? That
   is the only change that protects the already-running 4.0.4 launcher. The
   alternative is the release note alone, for that window.
2. Whether the self-call guard is worth carrying once no 4.0.4 session is left.
   It costs one `--replace-fail` per bump, and it is the only protection
   against the next skew of this shape.
