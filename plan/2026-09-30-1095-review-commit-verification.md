---
status: draft
issue: 1095
spec: spec/2026-09-30-1095-review-commit-verification.md
---

# Plan: Keep the main-install verdict on the commit GitHub could not read

The review walks main's commits newest first, collecting every install-check
run for each SHA. A failed per-run jobs request must leave an explicit row for
that SHA and make the main-install table say **could not read**. An older
successful install cannot verify a newer unreadable commit. If another run
for the same SHA witnessed a successful install, that success still verifies
the SHA. A gate that says a commit cannot affect an install keeps its existing
irrelevant result. No workflow or CI-gate changes are required.

## Steps

1. `pkgs/review.sh:62-100`: track a read-error row in
   `main_install_verdict`; choose a witnessed successful install before an
   error for the same SHA, and choose an unreadable result before walking to
   an older SHA -> verify by the existing `--main-install-verdict` fixture
   mode with an error-only newer SHA and an error-plus-success same SHA.
   Traps: preserve gate-success/irrelevant precedence, running status, and
   the no-run result; do not treat an unknown API response as a failed
   installation.
2. `pkgs/review.sh:557-575`: capture each `gh api .../jobs` response before
   printing its TSV row. On request failure, discard partial output and
   print one explicit error row with the current SHA; continue to inspect
   other runs for that SHA -> verify by a stubbed `gh` fixture where the
   newest SHA's jobs request fails and an older SHA's succeeds.
   Traps: preserve the checked failures for the commit list and run list at
   lines 559-561; leave the existing literal-tab SHA matches at lines 563
   and 567 alone. `od -c` confirmed they are real tab bytes.
3. `pkgs/review.sh:578-594`: render the unreadable verdict as a main-install
   **could not read** finding -> verify by the collector-plus-verdict fixture
   producing the unreadable classification and inspection of the table
   branch. Traps: findings are report output; do not make an ordinary finding
   an exit failure or turn an API failure into a verified row.
4. `tests/review-pins.nix:151-196`: stub `gh` and execute the real
   `main_install_runs` function from `pkgs/review.sh`, then feed its rows to
   the real `--main-install-verdict` mode. Assert a failed newest request
   yields its SHA as unreadable and an explicit error row; assert a failed
   rerun plus a successful install for the same SHA yields verified for that
   SHA -> verify by `checks.x86_64-linux.review-pins`.
   Traps: source only the collector function so the fixture never queries
   unrelated upstream repositories; fail visibly if extraction finds no
   function. Use stubbed, tab-delimited `gh` results, not live GitHub.
5. `pkgs/review.sh`, `tests/review-pins.nix`: save the fixed script with `cp`
   outside the source tree, temporarily remove the error-row behavior, and
   run `checks.x86_64-linux.review-pins` under the shared build lock. It must
   fail by selecting the older verified SHA. Restore the fixed script with
   `cp`, run the check under the lock again, and capture its passing line ->
   verify by both red and green output in the PR.
   Traps: never use `git checkout` for a break proof; confirm the break
   changed the intended code before building; do not commit proof logs or
   temporary copies. No VM or `checks.options` run.

## Tests

- `flock /mnt/data/vmtest/codex-build.lock nix build
  .#checks.x86_64-linux.review-pins --print-build-logs --no-link` once red
  and once green, one build at a time. The red failure must identify the
  newer unreadable SHA that the broken collector skipped; the green run must
  cover both the error-only and same-SHA-success cases.
- `nix fmt -- --ci`, `nix run nixpkgs#statix -- check .`, and
  `nix run nixpkgs#deadnix -- --fail .` pass after the Nix test edit. Run
  `nix fmt` after editing any `.nix` file, then inspect `git diff --stat`.
- Inspect the changed lines for `producer | grep -q` and writes to
  `omarchy/shell.json`, the existing CI text guards. Confirm no workflow
  file changed.
- Fill the PR template with the red and green lines and links to the intent,
  spec and plan. Do not merge.

## Rollback

Revert the implementation commits on the task branch or revert the merged
change in a follow-up PR. This restores the previous collector and verdict;
no user data or persistent state is migrated.
