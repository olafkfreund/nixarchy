---
status: approved
issue: 1126
intent: intent/2026-10-01-1126-session-journal-race.md
---

# Spec: Wait for detached rebuild journal messages

## Design

1. In `tests/session.nix:635-641,657-679`, keep the existing wait for the
   user unit's `Result=exit-code`, then obtain its nonempty `InvocationID`.
   For the missing-flake, branch-refusal, and `ALLOW_BRANCH_DEPLOY=1` runs,
   poll only that invocation's journal with `machine.wait_until_succeeds`
   until its expected text appears (bounded at 30 seconds). Read that same
   invocation's full journal once after the wait and retain the nonempty-log
   assertion. On timeout, include the latest scoped journal in the assertion
   failure. Capture journal output before matching it; do not pipe an
   unbounded `journalctl` producer into `grep -q` under the test driver's
   `pipefail` (`tests/AGENTS.md:1170-1220`).

2. The expected text for the first run is the missing-flake error, `does
   not exist` (`tests/session.nix:635-641`; `modules/apps.nix:3560-3564`).
   The branch run waits for `refusing to rebuild from 'agent/unmerged'`
   (`tests/session.nix:650-675`; `pkgs/branch-guard.nix:43-54`). The override
   run waits for `Enabled apps:` (`modules/apps.nix:3567-3568`), which the
   apply prints only after passing the branch guard and the flake-directory
   check. Once that marker is visible, retain the assertion that the
   completed invocation has no `refusing to rebuild` line
   (`tests/session.nix:676-679`). Do not treat a nonempty journal or systemd's
   exit lines as proof that program output has arrived.

3. Put the small polling helper in `tests/session-journal.py` and include
   that source in `tests/session.nix`'s `testScript` (currently at line 250),
   so the real session test and a cheap delayed-visibility fixture exercise
   the same implementation. The helper takes the scoped journal command and
   expected literal, polls with the VM driver's `wait_until_succeeds`, then
   reads and returns the log. It does not change `nixarchy-apply`, its user
   unit, or the branch guard (`modules/apps.nix:3506-3544`).

4. Add `tests/session-journal-race.nix` as a cheap check and register it in
   `flake.nix`'s uniform checks. Its test-only journal fixture returns
   systemd's exit lines without the program marker on the first read after
   `Result=exit-code`, then exposes the marker on a later read. Exercise the
   actual helper for each expected marker, including the override marker,
   and assert a permanently missing marker times out with a useful scoped
   log. This fixture models delayed *visibility*, not a sleep before the
   program exits. `checks.session` remains the real user-unit integration
   check and runs in CI only (`tests/AGENTS.md:25-36,746-759`).

## Alternatives rejected

- A fixed sleep after `Result=exit-code`: runner load and journal delivery
  vary, so any fixed delay can still race and wastes time when the line is
  already present.
- Waiting only for a nonempty journal or for systemd's exit lines: those are
  already present in the reported failure and do not prove that the program's
  stderr arrived.
- Delaying the branch guard before it prints: this also delays unit
  completion, so it does not reliably reproduce a line arriving after the
  result is visible.
- Searching the whole boot journal: an older invocation could satisfy the
  assertion for the current run. Keep `--invocation=<id>` scoping.
- Changing the product's unit or logging path to satisfy a test race: the
  evidence concerns observation timing in the test, not a product failure.

## Risks

- A renamed message would make the bounded wait fail. That is intentional:
  the test relies on these messages to prove the failure and override paths;
  the timeout must show the current invocation's log for diagnosis.
- The fixture proves the polling logic against controlled late visibility,
  while only CI's `checks.session` proves actual systemd and journald
  integration. Do not describe the cheap fixture as a VM or real-journal
  result.
- Bringing a helper source into the Nix `testScript` must preserve its Python
  syntax and scope. Verify evaluation and the cheap check before relying on
  CI's session run. New test files must be git-tracked before flake evaluation.

## Verification

- First extract the current single-read behavior into the shared helper and
  run the registered cheap fixture red: its first journal read lacks the
  expected program marker. After polling is implemented, break it back to a
  single read with a copy-aside and run red again. Confirm each break applied
  using `git diff`; save the good copy outside the worktree and restore it
  with `cp`, never `git checkout`.
- With bounded polling restored, `checks.session-journal-race` passes delayed
  refusal, delayed `Enabled apps:`, delayed missing-flake output, and the
  timeout case. `checks.session` passes in PR CI, proving the real user unit
  and invocation-scoped journal behavior. Do not run the session VM locally.
- Run `nix fmt -- --ci`, statix, deadnix, and `git diff --check` after the
  `.nix` edits. Confirm the new check is registered and generated PR checks
  will run it. Put the red and green fixture output in the PR.
