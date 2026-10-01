---
status: approved
issue: 1126
spec: spec/2026-10-01-1126-session-journal-race.md
---

# Plan: Wait for the detached rebuild's invocation journal

`checks.session` currently treats `Result=exit-code` as if journald had
already exposed the unit program's stderr. That is false on a loaded runner.
Keep the result wait, then wait at most 30 seconds for a literal expected
line in the **same invocation's** journal. Read that scoped journal again
after the wait; an empty final log is still a failure. The missing-flake run
expects `does not exist`, the branch run expects `refusing to rebuild from
'agent/unmerged'`, and the `ALLOW_BRANCH_DEPLOY=1` run expects the positive
`Enabled apps:` marker before asserting that no refusal appears. An absent
marker must fail with the latest scoped log. The product unit, apply command,
branch guard and workflows do not change.

The implementation has one small helper shared by the three session probes
and a cheap fixture that exercises that **same source** with a journal that
shows systemd exit lines before the program marker. The fixture proves
delayed visibility, not a process sleep before exit. `checks.session` is the
real systemd/journald integration check and runs in PR CI only; do not run
that VM locally. A fixed sleep, a nonempty journal, and a boot-wide journal
search are not substitutes for the expected invocation marker.

## Steps

1. `tests/session-journal.py` (new) and `tests/session.nix:250,635-679`:
   extract the current single-read journal behavior into a helper used by
   the session test, initially **without** the new poll. Include the helper
   source in `testScript`. After each existing `Result=exit-code` wait, get
   and assert a nonempty `InvocationID`; make the missing-flake read
   invocation-scoped too. Pass the literal expectations `does not exist`,
   `refusing to rebuild from 'agent/unmerged'`, and `Enabled apps:` to the
   helper, retain the nonempty-log assertion and the override's no-refusal
   assertion -> verify by `python3 -m py_compile tests/session-journal.py`
   and `nix eval --raw .#checks.x86_64-linux.session.drvPath` after staging
   the new source. Traps: this intermediate state intentionally keeps the
   old timing bug for the next step's red proof; do not push it alone.

2. `tests/session-journal-race.nix` (new) and `flake.nix:1759-1911`: add a
   cheap registered `checks.session-journal-race` fixture that imports the
   real helper. On its first post-result read, expose only the systemd exit
   lines; on a later read, expose the expected program line. Cover each of
   the three markers, and a marker that never appears (it must time out with
   the scoped log). Place the check in the uniform-check list and stage
   **both new files** before any flake evaluation or build -> verify by
   `nix eval .#checks.x86_64-linux --apply builtins.attrNames` containing
   `session-journal-race`, then a **red**
   `flock /mnt/data/vmtest/codex-build.lock nix build .#checks.x86_64-linux.session-journal-race --no-link --print-build-logs`:
   the old single read sees the systemd lines but misses the program marker.
   Capture the failing output outside the worktree. Traps: a check that
   sees no actual helper call or never goes red is not proof; do not pipe
   the build through `tail` or otherwise lose its exit status.

3. `tests/session-journal.py`: replace the single read with a bounded
   `machine.wait_until_succeeds` for the literal expected marker in the
   invocation-scoped journal, then read and return that journal. Capture
   `journalctl` output before matching it (a here-string or equivalent),
   never `journalctl | grep -q` under `pipefail`. Keep the empty-log failure;
   on timeout include the latest scoped log. Use the same helper in the
   real VM and fixture; a renamed message must fail rather than pass on
   systemd's own lines -> verify by the locked cheap check green for all
   delayed-marker cases and the permanent-absence timeout case. Then
   `cp tests/session-journal.py /mnt/data/vmtest/1126-session-journal.good`,
   restore a one-shot read **in that file**, inspect `git diff` to prove the
   break landed, run the locked check red, `cp` the good file back, and run
   the check green again. Never use `git checkout` to restore a break;
   keep the saved copy and logs outside the repo.

4. `tests/session.nix` and `flake.nix`: finish with the three invocation
   expectations and registered cheap check wired exactly as above -> verify
   by searching for any remaining result-then-single-read assertion in
   `tests/session.nix`, checking the generated PR-check registration, and
   running the static gates below. The diagnostic-only journal snapshots
   and probes that already wait for their line stay as they are. No product
   script or CI workflow edit is needed.

## Tests

- Add new files with `git add` **before** flake evaluation/build; a flake
  ignores untracked files. After every `.nix` edit run `nix fmt` and inspect
  `git diff --stat`. Require `nix fmt -- --ci`,
  `nix run nixpkgs#statix -- check .`,
  `nix run nixpkgs#deadnix -- --fail .`, Python syntax compilation, and
  `git diff --check` to pass.
- Build the cheap fixture and each red break one at a time under
  `flock /mnt/data/vmtest/codex-build.lock`. Before any non-cheap build, check
  `gh run list --limit 8 --json status -q '[.[]|select(.status!="completed")]|length'`
  and build only at zero. No local `checks.session` VM run; PR CI's generated
  checks cover both the cheap fixture and the real session check.
- Confirm the red baseline and copy-aside regression fail for the expected
  late-visibility reason, not a missing input or test crash. The restored
  fixture passes delayed missing-flake, refusal and override markers, and
  reports a bounded failure with the scoped log when the marker never
  appears. Put those red and green lines in the PR.
- Scan new shell commands for `producer | grep -q` and do not write
  `omarchy/shell.json`. No `writeShellApplication` is edited; if scope
  expands to one, build that package itself so ShellCheck runs
  (`tests/AGENTS.md:18-23`).

## Rollback

Revert the implementation commits that add the helper, fixture and check
registration, and that change the session probes. This restores the prior
single-read test behavior; it does not alter an installed service or user
data. Remove any saved break-proof copy from `/mnt/data/vmtest` after its
output has been included in the PR.
