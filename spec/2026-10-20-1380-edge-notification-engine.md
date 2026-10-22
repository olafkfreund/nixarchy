---
status: approved
issue: 1380
intent: intent/2026-10-20-1380-edge-notification-engine.md
---

# Spec: edge builds on quattro's new notification engine, and a sender's close still takes a card down

## The deciding test: answered (b)

The intent's rule was: if a visible critical card that its sender closes
leaves on its own, choose (a); otherwise choose (b). Read at quattro
03ff1ef, and checked by me against the source:

- **Critical cards never expire.** `durationFor` returns `0` for
  `NotificationUrgency.Critical` (`Service.qml:286-289`, "Critical waits
  for you"), and a card's countdown runs only for a duration above 0
  (`Toast.qml:212,225`).
- **A sender's close leaves a visible card alone.** The handler
  (`Service.qml:881-888`) forgets the sender's object and calls
  `finishClose` only when the card is not on screen yet:
  `if (service.rowIndexFor(key) < 0) …`.
- **It survives restarts.** The card is saved in `live.json` and restored
  after a shell restart, still with no timeout (`Store.js:81-83,136`).
- **Upstream asserts this on purpose.** `test/shell.d/notifications/logic.cjs:684-702`
  says "sender withdrawal cancels pending cards but leaves an already
  visible snapshot intact". No commit gives a reason beyond "snapshots
  outlive their sender" (`docs/notifications.md:117-121`).

So a critical notification an app withdraws stays on screen until the user
dismisses it, across restarts. That is #1032's bug, now by design.
**Verdict: (b).**

## Design

### 1. Re-implement #1032, narrowed to the stuck case

Replace `pkgs/omarchy/902-notification-sender-close.patch` on edge with a
patch against the new engine's `watchNotification` handler:

```qml
notification.closed.connect(function(reason) {
  if (service.refs[key] !== notification) return
  delete service.refs[key]
  service.refsRevision += 1
  // Visible snapshots outlive their sender; pending rows must not appear
  // after the sender withdraws them.
  if (service.rowIndexFor(key) < 0) service.finishClose(key, "closed")
  // nixarchy #1032: a critical card never expires, so one its sender withdrew
  // stayed on screen for good. Take that one down; the rest keep upstream's rule.
  else if (reason === NotificationCloseReason.CloseRequested
           && service.urgencyOf(key) === NotificationUrgency.Critical)
    service.closeToast(key, "closed")
})
```

- **Narrowed to critical cards.** The old patch took down any visible card
  its sender closed. Upstream now chooses otherwise on purpose, and a
  normal or low card expires within 5–30 s anyway. Only the critical case
  is stuck for good, so it is the only one we override. That is the
  smallest divergence, and the one we can argue upstream.
- `closeToast(key, "closed")` is the engine's own path. It runs the leave
  animation, then `finishClose`, which records the card in `history.json`
  with `closed_reason: "closed"`. That keeps the old patch's decision that
  a sender's close archives the card.
- `NotificationCloseReason` comes from `Quickshell.Services.Notifications`,
  which `Service.qml` already imports (line 13). Closes the shell itself
  makes report `Dismissed` or `Expired`, not `CloseRequested`, so they
  never reach the new branch, and `closeToast` returns early for a key
  that is already leaving.
- **`urgencyOf`:** the plan reads how the engine records a card's urgency
  (the snapshot row or `refs`) and uses that field directly. If no
  urgency survives on a visible row, the narrowing falls back to any
  visible card, which matches the old patch, and the plan records that.
- `--fuzz=0` stays. The patch's header comment names #1032, #1380 and the
  upstream issue.

### 2. Upstream

The change is to how Omarchy behaves, so the default route is upstream
(§11). I draft an issue for omacom/omarchy: "A critical notification its
sender withdraws (CloseNotification) stays on screen until dismissed, and
across restarts". It cites `logic.cjs:684-702` and asks whether a
withdrawn critical card should leave. **It is posted only with your
approval.** The patch is carried until upstream decides.

### 3. `checks.session`'s #1032 step, retargeted

The new engine deletes the old per-toast files and `history/` at startup
(`Service.qml:1465-1478`). It keeps `live.json` (cards on screen) and
`history.json` (closed cards, with `closed_reason`) in the same
`~/.local/state/omarchy/notifications/` directory. The step keeps its
shape: a critical `notify-send -p`, then a `busctl` `CloseNotification`,
then two separate waits, so a failure still says which half broke.

1. Wait until `live.json` contains `close-me-1032`, so the card is up.
2. Send the close.
3. Wait until `live.json` **no longer** contains it. That is the bug half,
   which stays red without the patch.
4. Wait until `history.json` has it with `"closed_reason": "closed"`.
   That is the decision half.

Writes are batched (`Service.qml:1358-1366`), so the existing waits of 30 s
and 60 s stay as floors. `jq` reads the JSON instead of `grep` against a
file layout. This edit is edge-only: `main`'s 4.0.6 keeps the old engine,
the old patch and the old step.

### 4. Every later carried patch

The edge build stopped at 902, so the patches and substitutions after it
have not been tried on 03ff1ef. Once 902 is replaced, the plan builds
`.#omarchy` for edge on the newest quattro and fixes whatever else has
drifted, in this same change. Each fix is listed in the plan's
deviations. #1382 will later make that one pass instead of several.

### Where it lands

Everything goes to `edge-candidate`:
- `pkgs/omarchy/902-notification-sender-close.patch`, replaced (the same
  path, so the `default.nix` line is unchanged, unless the drift in §4
  moves it);
- `tests/session.nix`'s #1032 step.

These artifacts stay on the `fix/1380` branch off `main`. Nothing reaches
`main`. The trial merge of `main` into the new candidate must keep both
edge-only hunks.

## Alternatives rejected

- **(a) Drop the patch:** the test says a withdrawn critical card is
  stuck.
- **Re-apply the old, broad behaviour (any visible card):** that diverges
  from a deliberate upstream rule more than the bug requires.
- **Give critical cards a timeout:** that changes "critical waits for
  you", which nobody reported as wrong.

## Risks

- **An app that withdraws a critical notification on purpose while
  showing it**, for example a resolved alarm. The card now leaves, which
  is what `CloseNotification` asks for.
- **Upstream disagrees:** we keep carrying a small patch, and its
  `--fuzz=0` flags every rewrite of the handler.

## Verification (§1)

- `checks.session` on edge with the new patch: green, with the step's
  print line in the log.
- **Red:** without the patch, so upstream's handler, the step fails at
  wait 3 (`live.json` still holds `close-me-1032`) with a timeout. Proved
  through an edge-candidate run, since `session` is a VM check (§6), or
  locally when CI is idle.
- `.#omarchy` on the new quattro builds, along with edge verify's cheap
  checks.
- The edge run promotes, and `edge` moves.
