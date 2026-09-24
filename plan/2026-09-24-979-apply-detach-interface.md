---
status: draft
issue: 979
spec: spec/2026-09-24-979-apply-detach-interface.md
---

# Plan: `--status`, `--log`, `--expect-sha256`

## The approved decisions, carried over

1. **All three in one change.** They share one argument parser and one unit.
2. **`--status` decides `none` from `SubState` and `InvocationID`, NEVER from
   `Result`.** `modules/apps.nix:3376` records why: a unit that never ran reads
   `Result=success ExecMainStatus=0`.
3. **`--json` is the contract; the plain output is not.** Said in `--help`.
4. **`--expect-sha256` is opt-in.** #967 refused every changed file from every
   caller and broke non-interactive apply; here a caller that checked something
   says so, and one that did not is neither protected nor blocked.
5. **#967 closes into this.**

## Steps

1. **`modules/apps.nix`, the flag parser (`:3349`)** -- add `--status`,
   `--json`, `--log`, `--follow`, `--invocation ID`, `--expect-sha256 K=V`
   (repeatable, collected into an array). Unknown flags keep exiting 2.
   → verify by step 5.
2. **A `rebuild_state` helper** -- one `systemctl --user show -p
   SubState,Result,ExecMainStatus,InvocationID`, mapped to none/running/
   succeeded/failed. `none` when `SubState` is empty or `dead` **and** there is
   no `InvocationID`.
   → verify by step 5's never-ran case.
3. **`--status` and `--log` act before anything else** and exit: they are
   queries, not applies.
   → verify by step 5.
4. **`--expect-sha256` checked inside the unit** -- the array is passed through
   to the `--in-unit` invocation and compared before the copy loop. A mismatch
   names the part and both hashes, and exits non-zero **before copying**.
   → verify by step 5's mismatch case.
5. **`tests/apply-detach-interface.nix`** -- a `runCommand` with stub
   `systemctl` and `journalctl`, modelled on `tests/apply-imports.nix`.

   | case | assert |
   |---|---|
   | unit never ran | `--status` says **none**, not succeeded |
   | unit failed | `failed`, with the exit code |
   | `--json` | parses; has state, result, exit, invocation |
   | matching `--expect-sha256` | proceeds |
   | mismatching | refuses, names the part, **and did not copy** |

   **Section 1**, two breaks in the PR: `--status` with a `Result`-first
   shortcut (the never-ran case goes red), and the comparison removed (the
   mismatch case goes red on "did not copy", not on a message).
6. **`modules/AGENTS.md`** -- the unit as a stated interface.

## Tests

`checks.apply-detach-interface`, `checks.apply-imports` (same script),
`checks.options`, `nix fmt -- --ci`, statix, deadnix.

No workflow edit: `generated-checks.sh` enumerates flake checks.

## Rollback

`git revert`. The flags disappear; the unit is unchanged throughout, so a
detached rebuild behaves exactly as it does today.
