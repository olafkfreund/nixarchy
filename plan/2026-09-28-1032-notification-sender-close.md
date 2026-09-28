---
status: draft
issue: 1032
spec: spec/2026-09-28-1032-notification-sender-close.md
---

# Plan: a notification closed by its sender leaves the screen

## Approved decisions, carried from the spec

- **The bug.** `shell/plugins/notifications/Service.qml:165-168` (Omarchy
  v4.0.4): the `closed` handler only deletes `liveRefs`. The popup row is never
  removed, and critical popups have duration 0 (`:104-105`), so they stay
  until dismissed by hand.
- **The fix.** The handler takes Quickshell's `reason`. It keeps the existing
  guard (`liveRefs[id] === notification`) first, and clears `liveRefs` before
  anything else. Only on `NotificationCloseReason.CloseRequested` does it
  call `removePopup(i, "close")` in a `Qt.callLater`, for every
  non-restored row with that `originalId`. Confirmed in Quickshell's source:
  `CloseNotification` gives `CloseRequested` (`server.cpp:140`), `dismiss()`
  gives `Dismissed`, and `expire()` gives `Expired` (`notification.cpp:65-66`).
- **History:** a sender's close **archives** to history through
  `removePopup`, like dismiss and expire. This follows Omarchy's own rule
  ("leaving the screen for any reason … becomes the newest history entry").
  `removePopupsByOriginalId`, which deletes without history, is rejected.
- **Carried** as `pkgs/omarchy/902-notification-sender-close.patch`, applied
  with `patch -p1 --forward --fuzz=0` beside `901`, so a reworded upstream
  line fails the build.
- **Reported upstream** at `omacom/omarchy`: drafted in the PR, and posted only
  after the owner has read the exact text and said go.
- **Probe in `checks.session`:** Do Not Disturb is asserted off, a critical
  `notify-send` is sent, its popup file must appear under
  `~/.local/state/omarchy/notifications/`, then `CloseNotification` over
  `busctl --user`, and the file must leave `notifications/` **and** appear in
  `notifications/history/`.

## Steps

**0. Before any local build:** `gh run list … | length` must print 0 (§6).
Repeated before steps 3, 4, 6 and 7.

1. **Confirm the Quickshell version** nixarchy actually runs. The overlay's
   `quickshell` is nixpkgs' own at or above 0.3.1, and otherwise pinned to
   0.3.1 (`flake.nix`, the quickshell override). Evaluate the version the
   session machine's shell gets, fetch **that** source, and grep it for
   `CloseRequested` and `void closed(`.
   → verify: the enum and the signal's argument exist in the version that
   ships. If they don't, stop and revise; the design depends on them.

2. **The patch.** Copy `Service.qml` from the pinned source, edit the handler
   exactly as in the spec, and generate
   `pkgs/omarchy/902-notification-sender-close.patch` with `diff -u`, with
   `a/`/`b/` paths `shell/plugins/notifications/Service.qml`. Hunk headers
   are generated, not hand-written (the #1031 hunk header was wrong by
   hand). Add a short header naming #1032, the upstream report, and the
   retirement condition.
   → verify: `patch -p1 --forward --fuzz=0 --dry-run` against a scratch copy
   of the pinned tree applies cleanly.

3. **Apply it.** `pkgs/omarchy/default.nix`, right after the `901` line: a
   `patch -d "$out/share/omarchy" -p1 --forward --fuzz=0 < ${./902-…}` line
   with a two-to-three-line comment in the same style (what, why carried,
   drop when upstream fixes it). Then `nix fmt` and read `git diff --stat`
   (the nixpkgs-fmt hook, §5).
   → verify: `nix build .#omarchy` green, and the built
   `share/omarchy/shell/plugins/notifications/Service.qml` contains
   `CloseRequested`.

4. **Build-level red (§1).** Commit steps 2–3 as a baseline. Break it by
   changing one context line of the patch so it can no longer apply, confirm
   the break landed with `git diff`, then run `nix build .#omarchy`.
   → verify: the build fails on the `902` patch (`--fuzz=0`). Restore with
   `git checkout HEAD -- pkgs/omarchy/902-*.patch`; green.

5. **The session probe.** `tests/session.nix`, after the hypr-rdp block, as
   the logged-in user (the existing `on_desktop`/`as_user` pattern):
   a. **DND off:** assert through the shell's `notifications isDnd` IPC, or,
      if the test can't reach the IPC, through `notifications.json`. Fail
      with a message saying the probe would pass without a popup otherwise.
   b. `notify-send -u critical -p -a nixarchy-probe -- "close me" ""` →
      capture the id.
   c. `wait_until_succeeds`: some file directly under `notifications/`
      contains `close me`. Record its name.
   d. `busctl --user call org.freedesktop.Notifications
      /org/freedesktop/Notifications org.freedesktop.Notifications
      CloseNotification u <id>`.
   e. **The property:** `wait_until_succeeds` that the file is gone from
      `notifications/` **and** present in `notifications/history/`. The
      timeout comes from the first run's measurement, with a floor high
      enough for a loaded runner (the #1031 lesson: a sub-second
      measurement × 3 is not a timeout).
   Heredocs are avoided in the Nix string (§5, nixfmt reindents).
   → verify: `checks.session` green, built by `drvPath` after a visible
   evaluation (§5).

6. **Session red (§1), twice, because the probe pins two things:**
   - **Patch out** of `default.nix` (temporary commit, confirm by `nix
     derivation show` that the build no longer references `902`) → the
     probe must fail at (e) with the file **still under `notifications/`**.
     Capture a screenshot in that failing run once, to confirm the file
     staying really does mean the toast is still on screen (the spec's proxy
     risk).
   - **History decision reversed:** a temporary patch variant calling
     `removePopupsByOriginalId(id, "")` instead of `removePopup` → the probe
     must fail at (e) on the **`history/`** half.
   → both failures captured for the PR, both temporary commits dropped, and
   green rebuilt the same way.

7. **Lint and docs.** `nix fmt -- --ci`, `statix`, `deadnix`. `tests/AGENTS.md`:
   one line under session coverage saying sender-close is probed and how.
   `pkgs/AGENTS.md`: `902` listed where carried patches are described, if
   that section lists them (grep first, §12).
   → verify: all exit 0; `git diff --stat` lists only the files named here.

8. **PR.** Squash the implementation commits into one with a full-sentence
   subject, keeping the artifact commits separate. The template gets both
   red outputs and links to all three artifacts. `Closes #1032`. **The
   upstream issue text is drafted in the PR description, not posted.**
   Before opening: `read_new` on the bus; post only if a trap qualifies.

9. **Upstream (the owner's word).** Show the owner the exact issue text.
   Post it to `omacom/omarchy` only on an explicit go, then link it from
   #1032 and from the patch header.

## Tests

| command | expected |
|---|---|
| `nix build .#omarchy` | green; the built `Service.qml` contains `CloseRequested` |
| same with a patch context line altered | red on the `902` patch |
| `checks.session` | green; probe (a)–(e) pass |
| same with the patch out | red at (e): file still under `notifications/` |
| same with `removePopupsByOriginalId` | red at (e): nothing in `history/` |
| `nix fmt -- --ci`, statix, deadnix | exit 0 |

## Rollback

Revert the commit. The `902` line and file go, `checks.session` loses the
block, and Omarchy's handler is back to upstream's. No state on any machine
changes. Toasts that are already stuck clear with
`quickshell ipc … notifications dismissAll`.
