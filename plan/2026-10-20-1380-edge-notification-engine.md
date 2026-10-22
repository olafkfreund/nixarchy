---
status: approved
issue: 1380
spec: spec/2026-10-20-1380-edge-notification-engine.md
---

# Plan: edge builds on quattro's new notification engine, and a sender's close still takes a card down

Approved decisions, carried from the spec:

- **Verdict (b).** At quattro 03ff1ef, critical cards never expire
  (`durationFor` returns 0), and a sender's close leaves a visible card in
  place (`Service.qml:881-888`). Upstream asserts this on purpose.
- **The patch:** replace `pkgs/omarchy/902-notification-sender-close.patch`
  (the same path) with a patch to `watchNotification`'s `closed` handler.
  It takes `reason`, and adds a branch: when the card is visible, the
  `reason === NotificationCloseReason.CloseRequested`, and its urgency is
  Critical, call `service.closeToast(key, "closed")`. Two comment lines
  name #1032. `--fuzz=0` stays.
  - If no urgency survives on a visible row, the branch applies to any
    visible card (the old behaviour), recorded as a deviation.
- **Upstream:** draft an issue for omacom/omarchy citing
  `logic.cjs:684-702`. Post it only with the owner's approval.
- **`checks.session`'s #1032 step,** edge only, keeps its shape:
  1. a critical `notify-send -p`;
  2. wait until `live.json` holds `close-me-1032`;
  3. `busctl … CloseNotification`;
  4. wait until `live.json` no longer holds it (the bug half);
  5. wait until `history.json` holds it with
     `"closed_reason": "closed"` (the decision half).

  Read the JSON with `jq`, and keep the 30/60 s floors. The state
  directory is `~/.local/state/omarchy/notifications/`.
- **Any later drifted patch** on the new quattro is fixed in this same
  change, each one recorded in Deviations.
- **Everything lands on `edge-candidate`.** These artifacts stay on
  `fix/1380`, and nothing reaches `main`.
- **Who implements:** two files and several steps, so the `coder` agent
  does steps 2-3, and the lead does 1, 4 and 5.
- **Builds wait for the owner's go-ahead.**

## Steps

1. **Lead: set up and measure.**
   - `git worktree add --detach /mnt/data/vmtest/wt-edge1380 origin/edge-candidate`.
   - In it, pin quattro's newest commit the way the edge workflow does:
     `gh api repos/basecamp/omarchy/commits/quattro --jq .sha`, then set
     that SHA in both copies in `flake.nix` that the workflow edits (the
     `omarchy` URL and `omarchyVersion` as `edge-<date>-<short>`), then
     `nix flake update omarchy`.
   - Clone quattro at that SHA under `/mnt/data/vmtest`, and read how
     `Service.qml` stores a card's urgency (the snapshot row, `refs`, or
     the `NotificationUrgency` property). Record the field the patch uses.
2. **Coder: the patch.** In the quattro clone, edit
   `shell/plugins/notifications/Service.qml`'s `closed` handler as
   decided, then `git diff > …/902-notification-sender-close.patch`, with
   a header comment of 3 lines naming #1032, #1380 and that it is
   narrowed to critical cards.
   → verify: `patch -p1 --dry-run --forward --fuzz=0` against a clean
   clone exits 0.
3. **Coder: the session step.** In the edge worktree,
   `tests/session.nix`'s #1032 block (around lines 1065-1094 on edge)
   becomes the five-part step above. Its comment explains the new
   engine's files in at most 4 lines.
   Traps:
   - the batched writes (`Service.qml:1358-1366`) mean a wait, never an
     immediate read;
   - keep `dismissAll` first, and the DND assertion;
   - a `jq` filter on a file that does not exist yet must fail the wait,
     not throw out of `wait_until_succeeds`, so use `test -s` first.
4. **Lead: build and prove.**
   - `.#omarchy` must build. Fix every other drifted patch or anchor,
     one at a time, and list them in Deviations.
   - Then edge verify's cheap checks.
   - Then `checks.session`, **only when CI is idle (§6)**:
     - green;
     - **red** with the patch's `patch -d` line commented out, which
       fails at wait 4 because `live.json` still holds it. Confirm the
       break landed with `git diff`.
     - Restore with `git checkout HEAD --` after committing a baseline.
5. **Lead: ship.**
   - Commit on the worktree, then a trial merge of `origin/main`: it must
     keep the patch and the step.
   - Push to `edge-candidate`, then `omarchy-edge.yml -f from_candidate=true`
     (after #1383 this keeps the pin; until then it re-fetches the newest
     quattro, so re-check drift if it moved).
   - Draft the upstream issue text in #1380, unposted, and ask the owner.
   - Close #1380 when `edge` moves.

## Tests

- The patch dry-runs at fuzz 0.
- `.#omarchy` and the cheap checks are green.
- `session` is green, and red without the patch at the bug half.
- An edge run promotes.

## Rollback

Restore the previous `edge-candidate` commit. Edge stays at 2a479e88
until a fixed candidate promotes, since `edge` only fast-forwards.
