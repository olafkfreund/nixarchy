---
status: draft
issue: 1032
author: Olaf Freund
---

# Intent: a notification closed by its sender leaves the screen

## Problem

When an application closes its own notification (`CloseNotification` over
D-Bus), the shell's toast stays on screen. For a **critical** notification,
which never expires, it stays until someone dismisses it by hand. After the
close, the id is forgotten, so the sender can't even replace the toast with
a new one.

Confirmed against the pinned Omarchy source (v4.0.4,
`shell/plugins/notifications/Service.qml`):

- `:165-168`: the `closed` handler only deletes the live reference. It
  never removes the popup row.
- `:104-105`: critical popups get duration 0, so no timer removes them
  either.
- nixarchy carries no patch to this file today.

Every app that retracts its own notifications is affected: media players,
chat clients, and anything that shows a "waiting" card and then withdraws
it. nixarchy-voice already had to stop closing its confirmation card and
replace it with a low-urgency one instead (olafkfreund/nixarchy-voice#170).

## Proposed outcome

A notification its sender closes leaves the screen at that moment,
critical ones included. Dismissing and expiring behave exactly as they do
today. A later notification that reuses the id displays normally.

## Affected users and systems

Every nixarchy machine running the Omarchy shell's notification server.
The code is upstream Omarchy's and behaves the same on Arch, so upstream
users are affected too.

## Constraints

- **The fix belongs upstream** (AGENTS.md §11, and the routing rules in
  `pkgs/omarchy/skills/nixarchy/contributing.md`). Decided: **both.** Carry
  a patch here until upstream fixes it, and report it at `omacom/omarchy` so
  the patch can be dropped. Nothing is posted there until the owner has seen
  the exact text and said go.
- The patch follows the existing convention (`pkgs/omarchy/901-*.patch`)
  and fails the build if an Omarchy bump rewords the lines it depends on,
  rather than silently not applying.
- Dismiss and expire already go through `removePopup`. The fix must not
  change their behaviour, including notification history, which a sender's
  close may or may not be meant to affect. The spec decides.
- AGENTS.md §2: found by using it, so it isn't fixed until a check can see
  it. `checks.session` runs a real notification server.

## Open questions

1. **What happens to history?** Should a sender's close only take the toast
   down, or also drop the entry from the notification centre? freedesktop
   says the server "should" remove it. Omarchy's own dismiss keeps history.
   The spec will propose one and say why.
2. **Where does the probe live?** `checks.session` already boots the shell.
   Sending a critical notification and then `CloseNotification` over
   `busctl`, then asserting the popup model is empty, should fit there. The
   spec will confirm the shell exposes something to assert against.
