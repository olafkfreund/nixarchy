---
status: approved
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
  evaluates it as `git+file://…` (`:21`, `:42`). CI's nix comes from
  `DeterminateSystems/nix-installer-action` (`.github/actions/setup-nix`,
  `source-tag: v3.22.5`). The run's log shows the action's default input
  `determinate: true`, which installs Determinate Nix. That nix refused the
  shallow `git+file` flake; the spec confirms that the nix variant explains
  the difference.
- Local nix 2.34.9 evaluates the same shallow clone without complaint
  (measured on 2026-11-09: a `--depth 1` clone listed all 214 checks). The
  local runs were also on full clones, so they never met a shallow tree at
  all (§3: two variables differ, the depth and the nix).
- So the guard has compared checks locally (`nightly.yml:583` records a
  66-minute first measurement), but never in the hosted nightly it was
  written for. Until it does, a commit that moves a check's proof goes
  unseen there, and the nightly fails every night for a reason unrelated to
  that question.
- Worse, local nix accepting a shallow tree means a local run on one would
  pass with `revCount` unset. A check that read `self.revCount` would then
  look commit-independent when it is not.

`release.yml` met a related refusal (`:129-185`), and two releases
published without notes. Its checkout already had `fetch-depth: 0`; a later
`git fetch --depth=200` re-shallowed the clone. Removing `--depth` fixed it,
and a step that fails early on `.git/shallow` now guards it. Its error was
nix fetching by rev ("shallow repositories are only allowed when
`shallow = true;`"), not this one.

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

- A workflow edit is a CI-gate change (§11). The owner reviews it. The
  job's trigger and timeout, and the `needs` lists of `digest` and `report`
  that name it, stay the same.
- The script refuses a shallow tree itself, whatever its nix would do, so a
  local run cannot pass for the wrong reason. The test is
  `git rev-parse --is-shallow-repository`, not `release.yml`'s
  `[ -f .git/shallow ]`: in a worktree, which this script makes and is often
  run from, `.git` is a file and the `shallow` file sits in the common git
  directory, so that test would always pass (agy review).
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
2. How is the failure shown locally, given that local nix accepts a shallow
   clone? Proposed: through the script's own refusal, on a `--depth 1`
   clone (deterministic), plus a Determinate Nix reproduction if the spec
   can get one cheaply. Otherwise the next nightly is the proof of the
   CI half.

Approved by the owner on 2026-11-09 with every proposed answer above.
