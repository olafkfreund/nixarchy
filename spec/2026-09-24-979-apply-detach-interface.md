---
status: approved
issue: 979
intent: intent/2026-09-24-979-apply-detach-interface.md
---

# Spec: a detached rebuild a caller can watch, and only build what it checked

## The intent's questions, decided

1. **All three in one change**, not split. My lean was to ship
   `--expect-sha256` alone because it is what closes #967; the maintainer chose
   all three. They share one argument parser and one unit, so the split would
   have been three passes over the same twenty lines.
2. **JSON is the contract; the plain output is not.** Said in `--help`, because
   once nixarchy-flatsnap calls `--status --json` its shape cannot drift without
   breaking another repository.
3. **#967 closes into this.** Its intent and spec stand, its plan is marked
   superseded with the fault; this issue's `--expect-sha256` is the shape that
   avoids it.

## Design

### `--status [--json]`

Reads `SubState`, `Result`, `ExecMainStatus` and `InvocationID` in one
`systemctl --user show`, and maps them to one of **none / running / succeeded /
failed**.

**`none` is decided from `SubState` and `InvocationID`, never from `Result`.**
`modules/apps.nix:3376` already records why: a unit that never ran reads
`Result=success ExecMainStatus=0`. An implementation that consults `Result`
first answers "succeeded" for a rebuild that never happened, which is the one
wrong answer that matters.

JSON shape, and this is the promised part:

```json
{"state":"failed","result":"exit-code","exit":1,"invocation":"a1b2..."}
```

`state` is always one of the four. `invocation` is `null` when there is none.

### `--log [--follow] [--invocation ID]`

`journalctl --user -u nixarchy-rebuild`, with `--invocation=<id>` defaulting to
the one `--status` reports, so a caller gets *that* run rather than everything
the unit has ever done.

### `--expect-sha256 <part>=<sha256>`

Repeatable. Recorded by the caller before `--detach` returns, checked **inside
the unit, before the copy**. On a mismatch the unit exits non-zero and says
which part moved, and nothing is copied or built.

**This is opt-in by construction, and that is the whole point.** #967 refused
every changed file from every caller, and the callers that cannot answer a
prompt are exactly the ones it stopped -- `checks.options` among them, which is
how `main` went red. Here a caller that checked something says so; a caller that
did not is neither protected nor blocked.

### The unit as a stated interface

`nixarchy-rebuild`, `RemainAfterExit`, no `--collect`, and SubState rather than
ActiveState. Written into `modules/AGENTS.md` as an interface other repositories
may rely on, because nixarchy-flatsnap already does, from a hard-coded copy.

## Alternatives rejected

| | why not |
|---|---|
| Refuse any changed file (#967's shape) | Built, shipped, reverted within the hour. Breaks non-interactive apply, which is an ordinary way to use it. |
| `--status` reading `Result` first | Answers "succeeded" for a unit that never ran. Our own comment says so. |
| A separate `nixarchy-rebuild-status` command | A second command to discover, install and document, for a flag on the one that starts the run. |
| Leaving flatsnap's workaround | It hard-codes our unit name in another repository. That is a published interface whether we admit it or not. |

## Risks

- **Publishing an interface is a promise.** Once flatsnap calls `--status
  --json`, the shape is fixed. Mitigated by saying which half is contractual.
- **`--expect-sha256` inside the unit is a new failure mode** for `--detach`:
  a run that refuses before building. It must say which part moved and what the
  two hashes were, or it is as opaque as the silence it replaces.
- **Argument parsing.** `--expect-sha256` is repeatable and takes a value; the
  existing parser is a simple `case` with `exit 2` on anything unknown. Getting
  this wrong turns a typo into "usage" rather than into a refusal.

## Verification

- **A `runCommand` driving the real script**, as `tests/apply-imports.nix` does:
  the script out of `systemPackages`, a fake flake, and a stub `systemctl` and
  `journalctl` on PATH. This works because `nixarchy-apply` is generated but the
  stub targets are *its* dependencies, not the script itself -- unlike
  `tests/apply-confirm.nix`, where a stub for `nh` lost to `writeShellApplication`'s
  strict PATH.
- Cases: a unit that never ran reports **none**, not succeeded (the trap); a
  failed unit reports failed with its exit code; `--json` parses and carries all
  four keys; a matching `--expect-sha256` proceeds; a mismatching one refuses
  **and does not copy**.
- **Section 1:** the `none` case seen failing with the `Result`-first shortcut
  in place, and the mismatch case seen failing with the comparison removed.
  Both outputs in the PR.
- **What no check reaches:** a real detached rebuild. The unit is stubbed, so
  this proves the interface, not the build.
