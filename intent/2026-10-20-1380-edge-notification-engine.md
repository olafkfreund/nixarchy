---
status: approved
issue: 1380
author: olafkfreund
---

# Intent: edge builds on quattro's new notification engine, and a sender's close still takes a card down

## Problem

On 2026-10-20 upstream replaced quattro's notification engine
(omacom/omarchy#15932, "Omapager's stacks, snoozes and panel", about 60
commits between 4f920a2 and 03ff1ef). Edge carries
`pkgs/omarchy/902-notification-sender-close.patch`, #1032's fix to the old
engine's `closed` handler, applied with `--fuzz=0`. That handler no longer
exists, so `.#omarchy` fails on 03ff1ef with
`Hunk #1 FAILED at 162`. Every edge run is now red (39393393370), and
`edge` is held at 2a479e88. That build works, but nothing new reaches edge
users, including today's 4.0.6 overlay row.

It is not a rebase. #1032 was: an app withdraws its notification
(`CloseNotification`) and the toast stays up, for good if it is critical.
The new engine handles a sender's close on purpose, and differently:

```qml
// Visible snapshots outlive their sender; pending rows must not appear
// after the sender withdraws them.
if (service.rowIndexFor(key) < 0) service.finishClose(key, "closed")
```

A pending card is dropped, but a visible one stays. Upstream wrote that down
as the intended behaviour. Whether it brings back #1032's stuck critical
card depends on parts of the new engine nobody here has read yet: expiry,
stacks, the panel, and critical-urgency handling.

Two more things follow from the same change:

- `checks.session`'s #1032 step drives the old engine's on-disk popup and
  `history/` files. The new engine keeps history in the shell, so the step
  can no longer observe anything, whichever way this goes.
- The build stops at the first failed patch, so the carried patches and
  substitutions after 902 have not been tried against 03ff1ef.

## Proposed outcome

- Edge builds and promotes on the new engine.
- **A sender's close takes its card down, or a recorded decision says why
  not.** Either:
  - (a) the new engine already keeps a critical card from being stuck (for
    example, it expires or can be dismissed in a way the old one could
    not), and the 902 patch is dropped on edge with that reason written
    down; or
  - (b) it does not, and the fix is re-implemented on the new engine as a
    small carried patch.
- `checks.session`'s sender-close step tests the new engine, at whichever
  layer can observe it, and is proved red against the behaviour it guards
  (§1).
- Every other carried patch on edge applies to the new quattro.

## Affected users and systems

- Edge-channel users: p620 and razer. `main` and stable 4.0.6 keep the old
  engine and the patch unchanged.
- On `edge-candidate`: `pkgs/omarchy/default.nix` (the 902 line),
  `pkgs/omarchy/902-notification-sender-close.patch`, `tests/session.nix`
  (the #1032 step), and any later patch that has drifted.

## Constraints

- **Edge only.** Nothing here may change `main`'s 4.0.6 behaviour. The
  edits go where `main` and `edge` already differ, or are proved by a trial
  merge not to conflict when `main` is next merged in.
- **Upstream's design is upstream's** (CLAUDE.md §11). If (b) is chosen, it
  is a fix to how Omarchy behaves, and the default route is upstream.
  Carrying a patch here is the fallback, and filing upstream needs your
  approval.
- `--fuzz=0` stays on any re-implemented patch.
- §6: `checks.session` is a VM check, so it runs only when CI is idle, or
  through the edge run itself.

## Open questions

- **(a) or (b)?** I propose the spec reads the new engine and tests one
  thing: does a visible critical notification that its sender closes ever
  leave the screen without the user acting? If it does, then (a). If it
  does not, then (b), plus an upstream issue drafted for your approval.
- **Unblocking edge first.** While this is open, edge stays at 2a479e88.
  The alternative is to drop the 902 patch now, so edge builds, and decide
  (a) or (b) afterwards. That publishes a possibly stuck critical toast to
  edge users in the meantime. I propose keeping edge held, since its
  current build works, unless you would rather have 4.0.6's row and the
  new quattro on edge sooner.

## Decisions (owner, 2026-10-20: "use your recommendations")

- (a) or (b) is decided by one test: does a visible critical notification
  its sender closes ever leave the screen without the user acting? Yes
  means (a), and the patch is dropped with the reason recorded. No means
  (b), and an upstream issue is drafted for approval, with the small
  patch carried only until upstream fixes it.
- Edge stays held at 2a479e88 until then. The 902 patch is not dropped
  just to unblock the build.
