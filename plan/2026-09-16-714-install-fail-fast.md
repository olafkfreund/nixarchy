---
status: draft
issue: 714
spec: spec/2026-09-16-714-install-fail-fast.md
---

# Plan: a failed install check fails in minutes, not at the 90-minute cap

## Decisions, carried from the approved spec

- **D1.** Each `create_machine` VM is shut down from a `try`/`finally` at the
  point of use, not through a shared helper.
- **D2.** The `finally` falls back to `release()` if `shutdown()` raises, so a
  wedged guest cannot reproduce the hang by another route.
- **D3.** `tests/install-teardown.nix` (`checks.install-teardown`) asserts, for
  each of the six tests, that every machine created is released on the failure
  path.
- **D4.** One local timed measurement with a deliberate always-false assertion,
  recorded in the PR against the 79 minutes on record (run 35025579251).
- **D5.** `globalTimeout` and `timeout-minutes` are untouched.

**Scope correction, found while surveying the six files** (the spec assumed
each test already had a `shutdown()` to move):

| test | `create_machine` | `shutdown()` |
|---|---|---|
| `install` | 3 | 3 |
| `free-space` | 2 | 2 |
| `install-encrypted` | 1 | 2 |
| `install-iso` | 4 | 1 |
| `install-iso-net` | 2 | **0** |
| `reinstall-vm` | 3 | **0** |

So this is not only "move the shutdown into a `finally`". `install-iso-net` and
`reinstall-vm` never release their machines at all, and `install-iso` releases
one of four — on the success path as much as the failure path. Those are
nightly, hours long, and their hang is invisible behind their own runtime.
Step 2 covers them, and the PR says so plainly rather than describing this as
a refactor.

## Steps

1. **`tests/install-teardown.nix` and `flake.nix`: D3, first, against today's
   tests**, so the red is real. It reads each driver derivation's test script
   and, for every `create_machine` binding, requires a `finally` that shuts that
   name down.
   → verify: `nix build .#checks.x86_64-linux.install-teardown` fails, naming
   at least `install-iso-net` and `reinstall-vm`. Capture the output.
2. **The six tests: D1 and D2**, one file at a time, smallest first
   (`install-encrypted`, `free-space`, `install`, `install-iso`,
   `install-iso-net`, `reinstall-vm`). Where no `shutdown()` exists, add one
   with a comment saying why it is not optional.
   → verify: `checks.install-teardown` green; each file's driver builds
   (`nix build .#checks.x86_64-linux.<name>.driver`).
3. **Break-proof D3:** remove one `finally`, prove the break landed with
   `git diff`, watch the check name that file, restore.
   → verify: red, then green.
4. **D4, the measurement.** Add a deliberate `assert False` to
   `tests/install.nix` after the target boots, build `checks.install` locally,
   and time from the assertion line to the builder exiting. Remove it.
   → verify: under two minutes, against 79 on record. **Check the CI queue
   first** (AGENTS.md §6): no install job may be in flight.
5. **`tests/AGENTS.md`:** a `create_machine` VM is yours to release, on every
   path — the driver neither reaps it at cleanup nor kills it at
   `globalTimeout`, because both iterate `self.machines` and it is not in there.
   → verify: `grep -n "#714" tests/AGENTS.md`.
6. **Local checks:** `install-teardown`, `options`, `stable-eval`,
   `config-warnings`; statix, deadnix, `nix fmt -- --ci` last.
   → verify: all pass.
7. **PR:** link the three artifacts, paste the step 1 and step 3 reds and the
   step 4 timing, state the scope correction, `Closes #714`. Squash auto-merge.
   → verify: CI green, merged.

## Tests

```sh
nix build .#checks.x86_64-linux.install-teardown --print-build-logs  # red before step 2
nix build .#checks.x86_64-linux.install.driver
nix build .#checks.x86_64-linux.reinstall-vm.driver
nix build .#checks.x86_64-linux.options
```

## Rollback

Revert the squash commit. Failing install checks go back to costing 90 minutes
and a slot.
