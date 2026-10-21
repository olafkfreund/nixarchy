---
status: draft
issue: 1407
spec: spec/2026-10-21-1407-version-pin-check.md
---

# Plan: a hand-pinned Omarchy bump with a stale version string fails a check

## Decisions (approved spec)

- Extend `checks.omarchy-version-label`. No new check.
- The pin comes from `flake.lock`'s `nodes.omarchy`:
  - `original.ref` present (stable): `"v" + omarchyVersion` must equal it;
  - otherwise (edge): `omarchyVersion` must match
    `edge-[0-9]{8}-<locked.rev 0..7>`.
- The failure message names both values and `flake.nix:540`.
- Edge gets the change through its nightly merge of `main`, not as a
  carry.
- Two files and two steps, so the lead implements it (no coder).

Also in this PR: the general lesson from #1405, a **merge-commit, not
squash, rule** for PRs that merge a long-lived branch, appended to
CLAUDE.md §8 as a bullet, not a new section (§ numbers are
cross-referenced).

## Steps

1. **`flake.nix` (~:2525) and `tests/omarchy-version-label.nix`.**
   - The call passes
     `lock = builtins.fromJSON (builtins.readFile ./flake.lock);`.
   - The check takes `lock` and adds one `assert assertMsg` beside the
     wiring assertion, using `builtins.match`, with a one-line comment
     that dev pins are evaluated in the user's flake and never reach
     this check.
   - Verify by building `checks.omarchy-version-label`.
   - Red (scratch worktree): `omarchyVersion = "4.0.6"` with the lock at
     `v4.5.0-rc1`.
   - Red, edge form: a scratch worktree off `origin/edge` with the
     change cherry-picked and `omarchyVersion = "edge-20261021-0000000"`.
   - Green: both real trees.
   - Traps:
     - §5: commit before building any scratch tree, and use
       `git worktree add --detach`;
     - `nix fmt`, then `git diff --stat`.
2. **`CLAUDE.md` §8:** one bullet after the "stacked PR" paragraph.
   - **Merge a PR that carries another long-lived branch with a merge
     commit.** #1405 merged edge into `main` and was squash-merged, so
     `main` lost edge's ancestry, and the next edge run conflicted on
     every line both had touched (`cd.nix`, `flake.nix`, `flake.lock`).
   - Use `gh pr merge --merge` for such a PR, and say so in its body.
   - Verify: `grep -n 'long-lived branch' CLAUDE.md`.

## Tests

| check | expected |
|---|---|
| `omarchy-version-label` | green on main; red on the stale-version and wrong-rev variants |
| full generated list | no new reds (CI runs the PR) |

## Rollback

Revert the PR. The check goes back to wiring-only.
