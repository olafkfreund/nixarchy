---
status: draft
issue: 714
intent: intent/2026-09-16-714-install-fail-fast.md
---

# Spec: a failed install check fails in minutes, not at the 90-minute cap

## Design

Every VM made with `create_machine` is shut down on **every** exit path, not
only the one where the test passes.

- **D1. A `finally` at the point of use, not a shared helper.** Each of the six
  tests wraps the block between `create_machine` and its existing
  `target.shutdown()` in `try:` / `finally:`, with the shutdown moved into the
  `finally`:

  ```python
  target = create_machine(..., name="target")
  try:
      target.start()
      ...                      # every assertion, unchanged
  finally:
      target.shutdown()        # the line that already exists, moved
  ```

  Answering the intent's first open question: a helper would have to own
  machine creation to own its cleanup, which means changing how six tests make
  their VMs to fix when they release them. The `finally` is the smaller change
  and is visible at the line it protects — and the comments already sitting
  above those `shutdown()` calls ("or this check never finishes") end up in the
  right place.

- **D2. `shutdown()` must not be able to hang either.** If the guest is wedged,
  `shutdown()` waits. Each `finally` therefore falls back to `release()` — the
  driver's own kill path — if the graceful shutdown raises:

  ```python
  finally:
      try:
          target.shutdown()
      except Exception:
          target.release()
  ```

  Without this, a failure that leaves the guest unresponsive reproduces the
  original 79-minute hang through a different door.

- **D3. The check is `tests/install-teardown.nix`,** a stubbed `runCommand`
  that reads the test scripts out of the built driver derivations and asserts,
  for each of the six, that every `create_machine` result is shut down from a
  `finally` block. It is a source-shape assertion, and the spec says so plainly:
  it cannot prove the driver exits, only that the cleanup is on the failure
  path. What proves the behaviour is D4.

- **D4. One real measurement, once, recorded rather than automated.** On the
  branch, with a deliberate always-false assertion added to
  `tests/install.nix` after the target boots, `checks.install` is built locally
  and timed. Expected: the driver exits within a minute of the assertion rather
  than sitting until `globalTimeout`. The before figure is already known from
  run 35025579251: assertion at 21:39:16, job killed at 22:58, **79 minutes**.

  This answers the intent's second question. It costs one local VM build, not a
  CI slot, and it is run when no install job is in flight (AGENTS.md §6).

- **D5. What is deliberately not changed:** `globalTimeout` (85 minutes) and
  `install-check.yml`'s `timeout-minutes: 90`. Both are backstops, and a CI
  gate is a human's to move (§11). Worth recording, though, that the backstop
  is weaker than it looks: `terminate_test` iterates `self.machines`, which a
  `create_machine` VM is never added to, so the global timeout would not have
  killed the target either.

## Alternatives rejected

- **A shared `with managed_machine(...)` helper.** Cleaner in principle, and it
  changes machine creation in six tests to fix machine destruction. More diff,
  more to get wrong, no extra safety.
- **Lowering `globalTimeout` so the backstop fires sooner.** It would not have
  helped at all: the handler cannot see these machines. It would also turn a
  precise failure into a timeout, which reads as flakiness (§6).
- **`atexit` in the test script.** Runs after the driver's own cleanup and is
  invisible at the point of use.
- **Reporting it upstream instead.** The driver's contract is consistent —
  `create_machine` hands you a machine and you own it. Our tests did not. A
  change to nixpkgs would take weeks and would not fix this repository today.
  Worth raising later, not instead.

## Risks

- **`finally` swallowing the failure.** It must not: the shutdown is inside
  `finally`, the assertion's exception propagates, and D3 asserts the shape.
  The PR shows a failing run's log ending with the assertion text.
- **A shutdown that itself fails** masks the original error with a secondary
  one. D2's `except Exception: release()` keeps the first exception as the one
  that propagates.
- **Six files, one pattern, and `install-iso`/`reinstall-vm` run nightly only**
  — a mistake there is seen a day later. D3 is a cheap check precisely because
  it covers those two without booting them.
- **Hosts:** CI only. No installed machine is affected.

## Verification

- `checks.install-teardown` passes, and is seen red with one `finally` removed.
- `checks.install` and `checks.free-space` still pass locally (the refactor
  must not change what they assert).
- D4's measurement, in the PR: wall-clock from the deliberate assertion to the
  driver exiting, against the 79 minutes on record.
- statix, deadnix and `nix fmt -- --ci`.
