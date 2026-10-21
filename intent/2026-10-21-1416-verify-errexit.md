---
status: approved
issue: 1416
author: olafkfreund
---

# Intent: nixarchy-verify runs every check on every machine, and #1417's leftover guests stop reading as failures

## Problem

`nixarchy-verify` is the hardware half of the test suite: it covers
everything a VM cannot (§2). On p620 on 2026-10-21 it printed 35 lines and
exited 1, with no ✗ and no message, at its "ai-mirror beside Voice"
section.

`pkgs/verify.sh:472`:

```bash
aim_owner=$(grep -oE '"owner": ?"[a-z]+"' "$aim_state" 2>/dev/null | grep -oE '[a-z]+"$' | tr -d '"')
```

`writeShellApplication` runs the script under
`errexit nounset pipefail` (`flake.nix:834` reads the file into one). With
no `owner` in `state.json`, or no file at all, the first `grep` exits 1,
`pipefail` carries it out of the command substitution, and `errexit` ends
the run. Every later section never ran on such a machine: Bluetooth,
Radios, both MicroVM sections, Theme, Owe, Nixarchy fixes, Menu rows,
Shell, apps, gliff and Boxes. The run read as a short pass. That is §4's
"a check that cannot RUN reads as a check that passes", in the one script
that exists to catch what CI cannot. With `|| true` added, the same
machine ran to the end: 44 passed, 2 failed, 7 worth a look.

Nothing tests `verify.sh` at all today. No `checks.*` runs it, so the next
pipeline that can fail under `errexit` will kill the run the same way.

#1417, found in the same run, is a reporting bug in the same script: a
leftover, undeclared `/var/lib/microvms/<name>` is reported as a failed
guest.

## Proposed outcome

- `nixarchy-verify` runs to its summary line on a machine where any single
  probe's command fails. A probe that cannot answer says so (`·` or ✗ with
  a reason) instead of ending the run.
- A guest under `/var/lib/microvms/` that the system no longer declares is
  reported `·`, "no longer declared; its state can be removed", and not ✗
  (#1417).
- A check runs the **packaged** `nixarchy-verify` against stubs, so a
  future abort under `errexit` fails CI.

## Affected users and systems

- `pkgs/verify.sh` (the ai-mirror line, the MicroVM guest loop, and any
  other unguarded pipeline found by a sweep).
- A new `tests/verify-*.nix` check, plus its `flake.nix` entry.
- Everyone who runs `nixarchy-verify`. It is read-only, so there are no
  machine effects.

## Constraints

- **Run the packaged binary**, not `bash pkgs/verify.sh`. The `errexit`
  comes from `writeShellApplication`, and a check on the source file would
  pass with the bug present (`pkgs/AGENTS.md`, "writeShellApplication also
  sets errexit").
- **§1:** the check must fail on today's line (red), with a stubbed
  ownerless `state.json`, and on a stubbed undeclared guest for #1417.
- The script stays read-only (`--print-roots`, never `--gc`).

## Open questions

1. **Fold #1417 in, or keep it separate?** I propose folding it in. It is
   the same script, the same stub harness, and found in the same run; one
   check covers both. Both issues close on the one PR.
2. **Sweep:** fix only line 472, or also grep the script for every
   `$(… | …)` and command substitution that can fail under `errexit`, and
   guard each one the same way? I propose the sweep. The harness can only
   exercise the branches its stubs reach, so a static sweep catches the
   rest. Each guard is `|| true` or `|| status=$?`, with nothing
   restructured.
3. **How much of verify.sh does the check stub?** I propose the minimum
   that reaches the summary line: stub `systemctl`, `bluetoothctl`,
   `nix-store`, `ai-mirror` and the few hardware probes, as fail or empty.
   Then assert two things: the run reaches "passed, … failed", and the
   #1417 line reads `·`.

## Decisions (owner, 2026-10-21)

Approved with all three proposals: #1417 folded in; sweep every failable
substitution; a stub harness on the packaged binary that must reach the
summary line.
