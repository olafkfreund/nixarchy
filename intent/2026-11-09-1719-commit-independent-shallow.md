---
status: draft
issue: 1719
author: x
---

# Intent: the commit-independence guard can run on a hosted checkout

## Problem

The nightly's `commit-independent` job (#1644, #1694) checks that a commit
that changes nothing a check builds leaves every check's proof alone. Its
first nightly run, 42554626479 on 2026-11-09, failed one second into the
script and filed #1719:

    error: '/home/runner/work/_temp/commit-independent.xcpEOo/tree' is a
    shallow Git repository, so 'revCount' is not available

- `actions/checkout@v5` clones at depth 1 unless told otherwise, and the
  job does not tell it otherwise.
- `.github/scripts/commit-independent.sh` makes a worktree of that clone and
  evaluates it as `git+file://…` (`:21`, `:42`). CI's nix is Determinate Nix
  (`.github/actions/setup-nix`, `determinate: true`), and it refuses a shallow
  `git+file` flake that does not say `shallow=1`.
- Local nix 2.34.9 evaluates the same shallow clone without complaint
  (measured on 2026-11-09: a `--depth 1` clone listed all 214 checks). So
  every local run passed, and only the hosted run could fail (§3: the
  variable that differs is the nix in CI).
- The guard has therefore never compared anything. Until it does, a commit
  that moves a check's proof goes unseen, and the nightly fails every night
  for a reason unrelated to that question.

`release.yml` met the same refusal before (`:129-185`): two releases
published without notes. It fixed it with `fetch-depth: 0` and a step that
fails early on `.git/shallow`.

## Proposed outcome

- The nightly's `commit-independent` job reaches its comparison and reports
  `N checks, none moved`, or names the checks that moved.
- A shallow tree fails with a message that says the clone is shallow, not
  with a `revCount` error from nix.
- A local run can show the failure, so the fix has a §1 proof.

## Affected users and systems

- `.github/workflows/nightly.yml` (`commit-independent` job, `:581-598`) and
  `.github/scripts/commit-independent.sh`.
- The nightly and its `report`, which files #1719 each night until this is
  fixed.
- No user machine; nothing that ships changes.

## Constraints

- A workflow edit is a CI-gate change (§11). The owner reviews it, and
  the job's trigger, timeout and `needs` lists stay the same.
- The guard must still compare like with like: both sides of the probe
  commit are evaluated the same way.
- Its question is whether a commit moves a proof. The tree it evaluates
  should behave like a user's full clone, where `revCount` exists and
  changes with every commit.
- The job stays on a hosted runner and does not take an install slot.

## Open questions

1. Full history (`fetch-depth: 0`) or `?shallow=1` in the script's URLs?
   - Full history matches a user's clone. A check that read
     `self.revCount` would then move with the probe commit, and the guard
     would name it.
   - `shallow=1` leaves `revCount` unset, so such a check would fail to
     evaluate instead.
   - Proposed: `fetch-depth: 0`, as `release.yml` does.
2. Should the script refuse a shallow tree itself, with its own message,
   as `release.yml`'s step does? Proposed: yes. It runs outside CI too, and
   local nix would not refuse.
3. How is the failure shown locally, given that local nix accepts a shallow
   clone? To be measured in the spec, either with Determinate Nix or through
   the script's own refusal.
