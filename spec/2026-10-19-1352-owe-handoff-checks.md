---
status: draft
issue: 1352
intent: intent/2026-10-19-1352-owe-handoff-checks.md
---

# Spec: two checks that fail #1349 for reasons in the checks themselves

One PR covers both fixes (the intent's second question).

## What owe 0.2.11 does, from its source

From `src/daemon/main.c` at tag `v0.2.11`:

- When a video replaces the shell's still, owed starts the renderer behind it
  and sets `handoff_pending`, but leaves `engine` at `shell`
  (`renderer loading behind the shell's still`, logged in #1349's run at
  05:29:44.901).
- When mpv reports the first frame, `check_media_ready` calls
  `activate_renderer()`, and `engine` becomes `renderer`.
- If no frame arrives within `MEDIA_READY_TIMEOUT_MS` (5000 ms),
  `media_failed` → `cancel_handoff`: the renderer is stopped, and the shell
  keeps its still for good.

That answers the intent's open question about budget. Within about 5 s,
`engine` either reaches `renderer` or never will. The check's existing 60 s
poll (30 × 2 s) covers that with margin, so no number changes. If llvmpipe
cannot produce a first frame in 5 s, owed itself gives up and the check
fails. That would be a true statement about this owe on a GPU-less machine,
not something to make the check tolerate.

## Design

### 1. `tests/session.nix`: wait for the handoff, not only for the renderer

In the video poll (around line 2345), the loop's exit condition becomes

```python
if (status.get("source_kind") in ("video", "gif") and status.get("render_alive")
        and status.get("engine") == "renderer"):
```

The three asserts after the loop stay word for word, so a failure still says
which of the three never happened. Only the comment above the loop changes,
to say that owe ≥ 0.2.11 hands over at the first frame (omacom/owe#17).

On owe 0.2.10, `engine` is `renderer` at the moment `render_alive` turns
true, so the loop exits on the same iteration as before. The check therefore
passes on both versions, and the fix and the bump can land in either order
(an intent constraint).

### 2. `tests/home-activation-writes.nix`: no pipe into an awk that exits

The hold section changes from `rehome ${act "nixarchySeed"} | awk '…exit…' > hold.sh`
to the shape every other section of this file already uses:

```sh
rehome ${act "nixarchySeed"} > seed.sh
awk '…' seed.sh > hold.sh
```

The awk program is unchanged, `exit` included. Reading a file, an early exit
cannot signal a writer, so status 141 is impossible by construction.

## Alternatives rejected

- **Raise the poll budget.** The budget was never the problem: the loop exits
  as soon as `render_alive` is true, before the handoff finishes.
- **Assert `handoff_pending` or a new status field.** owe's `status` does not
  report it. Waiting for `engine` is the observable the user cares about,
  since that is what puts the video on screen.
- **Drop the awk `exit` instead.** That also works, but leaves a pipe whose
  safety depends on awk's behaviour. A file matches the file's own idiom.
- **Hold owe at 0.2.10.** owe's change is an improvement (no blank frame
  during the handoff), and the check is what is wrong.

## Risks

- **llvmpipe misses owe's 5 s first-frame deadline in CI.** Then `session`
  stays red on 0.2.11 with `engine is 'shell'` even after this fix. The fix's
  own run on 0.2.10 cannot show this. #1349 re-run on top of this branch is
  the measurement. If it happens, it is a new finding for owe on GPU-less
  machines, filed separately, and not something to hide here.
- None for users: test files only.

## Verification

- **Fix 1, red/green (§1).**
  - Green: `checks.session` passes on this branch (owe 0.2.10). It is then
    re-run with #1349's two-line bump applied on top (owe 0.2.11), where it
    must also pass. That pair is the run that varies the variable that
    matters (§3).
  - Red: on the same 0.2.11 tree, point the video poll at a file owe cannot
    decode (a zero-byte `loop.mp4` in the test's video derivation). The media
    deadline cancels the handoff, `engine` stays `shell`, and the check must
    fail on the `engine` assert after the poll runs out. This shows the
    property ("owed takes the layer") can still fail.
  - These are VM runs, so they run locally only when
    `gh run list … | length` prints 0 (§6). Otherwise CI runs them on
    throwaway commits that are later dropped from the branch.
- **Fix 2.**
  - The mimeapps-hold control in the same check (`nohold.sh`, "the hold's rm
    is not what removes the list") still fails when the hold's `rm` is
    deleted. Re-run it once to show it was not disturbed.
  - SIGPIPE, shown deterministically under bash with `set -o pipefail`, a
    writer larger than the pipe buffer, and the same awk program:
    `seq 1 200000 | awk 'NR==1{print; exit}'` exits 141, and the same
    program reading a file exits 0. Both outputs go in the PR.
  - `checks.home-activation-writes` builds green (cheap tier, under the lock).
- `nix fmt -- --ci` clean.
- #1349 re-run after this merges: `session` and `home-activation-writes`
  green. The owe and omawrite launch test stays with the maintainer, as that
  PR asks.
