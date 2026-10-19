---
status: draft
issue: 1352
author: olafkfreund
---

# Intent: two checks that fail #1349 for reasons in the checks themselves

## Problem

Pinned-package bump #1349 (owe 0.2.10 → 0.2.11, omawrite 0.7.1 → 0.7.2) is
red, and neither failure is a regression in anything that ships.

1. **`checks.session` asserts owe's old handoff timing.** owe 0.2.11
   (omacom/owe#17) keeps the shell's still on screen until the new video's
   first frame is drawn, and only then sets `engine` to `renderer`. Our check
   (`tests/session.nix`, around line 2345) stops polling as soon as
   `render_alive` is true and asserts `engine == "renderer"` at once. Under
   0.2.11 `render_alive` comes first, so the assertion fires during the
   handoff and fails. owe got better and the check read that as a failure
   (CLAUDE.md §4: a check that encodes the old model fails because the work
   succeeded).
2. **`checks.home-activation-writes` can die of SIGPIPE.** The mimeapps-hold
   section added in #1342 pipes the activation script into an `awk` that
   `exit`s once it has the block it needs. If the writer is still writing when
   awk exits, it gets SIGPIPE, and the check fails with status 141 having
   asserted nothing wrong. It depends on timing: it passed on #1344 and on
   `main`, and failed on #1349.

## Proposed outcome

- `checks.session` passes on owe 0.2.11. It still fails if owed never takes
  the layer from the shell, which is the property the assertion exists for.
- `checks.home-activation-writes` cannot fail from SIGPIPE, and still fails
  if the #1342 hold is removed.
- #1349 can then be re-run on top, and judged on the bump alone.

## Affected users and systems

- Test files only: `tests/session.nix` and `tests/home-activation-writes.nix`.
  Nothing a user installs changes.
- The `system-checks` job (session) and the `omarchy` job (home-activation-
  writes) on every PR.

## Constraints

- §1: each fix has a break proof. The session property ("owed takes the
  layer") must still be able to fail, and so must the hold check.
- A VM check (`session`) runs locally only when CI is idle (§6). Otherwise its
  proof comes from CI.
- The session check must keep working on owe 0.2.10 as well as 0.2.11, so the
  fix and the bump can land in either order.
- No upstream post: owe's behaviour is intended.

## Open questions

- **Does the VM produce the first frame within the poll's budget?** The
  guest has no GPU (`ZINK: failed to choose pdev`, so it falls back to
  llvmpipe). If a first frame takes longer than the current 60 s, the budget
  has to grow. I will measure that before the spec fixes a number.
- **One PR or two?** I propose one, since both block the same bump and are
  small.
