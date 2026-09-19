---
status: draft
issue: 747
spec: spec/2026-09-19-747-options-memory.md
---

# Plan: profile and attribute option-check evaluator memory

## Approved decisions

This plan authorizes diagnostic work only after its approval. No cause has
been established, and no production optimization is authorized. Shared fixture
retention is a hypothesis. Do not split the check, collapse fixture modes,
remove coverage, or alter CI gates or installed machines.

The existing hosted options step measures proof lookup, possible build, and
proof push. Its 11,719 MiB/16,384 MiB reading is context, not a baseline for a
local evaluator-only experiment. GNU time reports maximum child RSS, not which
child consumed it. Keep the existing CI instrumentation unchanged and compare
each measurement series only with its own comparable baseline.

The evaluator expression must request both `outPath` and `drvPath`, matching
`.github/scripts/already-proven.sh`; that wrapper discards stderr, so profile
the expression directly. Preserve evaluator stdout, stderr, exit code, and
GNU time output separately. Disable evaluation caching explicitly. Missing
statistics or failed evaluation invalidates the measurement.

Preserve every boolean case, runtime-test input, assertion, and distinction
between the default NixOS machine, standalone Home Manager, and Home Manager
with a named host through `osConfig`. The complete `pkgs.runCommand` evaluation
is the workload, not only the `cases` report.

The eventual optimization targets are at least 15% lower median peak RSS and
no more than 10% higher median elapsed time on comparable complete-workload
runs. These are acceptance choices, not predictions. Full coverage, an actual
successful `checks.options` build, and continuing hosted measurements remain
required before closing #747. A profile alone cannot close it.

## Steps

1. **Prepare the measurement baseline without building.** In this isolated
   worktree, verify clean status and record the source revision, lock hash,
   Nix version, command, relevant cache/environment settings, and fixture
   additions since the original CI reading, including #782 if merged.
   Identify the GNU time executable; do not use the shell builtin. Create a
   unique capture directory under `/mnt/data/vmtest/` outside the tracked tree.
   Record environment variables by an explicit relevant allowlist, never a
   wholesale environment dump that could include credentials.
   → Verify: the revision, diff, lock hash, tool paths/version, and capture
   location are recorded; no implementation files changed.

2. **Coordinate a quiet window.** Read the CI install queue and observe host
   load, memory availability, and competing activity immediately before each
   heavy run. No expensive evaluation or VM build may start while an install
   job is active. Do not parallelize measurements or cancel another job.
   If installs or other competing load make results unsafe or noisy, postpone
   measurement and continue read-only analysis. Acquire the shared
   `/mnt/data/vmtest/.nixarchy-heavy.lock` with `flock`, then recheck queue and
   load before evaluating; keep it held through the capture. The existing
   `heavy-build.sh` hardcodes `nix build`, so use the same lock directly for
   `nix eval`, not that wrapper. This lock coordinates local heavy work; it
   does not replace the no-active-install check.
   → Verify: record queue state, host, timestamp, and workload observations
   beside each run; no unsupported claim that the host was idle.

3. **Capture one complete baseline profile.** Execute the command in Tests
   once, capturing its exit status even on failure. Inspect the installed
   Nix version's actual statistics fields before interpreting them. Do not
   equate total allocations with live retained memory or a retaining reference.
   → Verify: exit status is zero, stdout contains the output and derivation
   paths, stderr contains usable evaluator statistics, and GNU time records
   peak RSS and elapsed time. Missing fields invalidate the measurement.

4. **Trace attribution from the real consumers.** Read `tests/options.nix`
   constructors through `cases`, `broken`, `report`, and all `pkgs.runCommand`
   inputs. Examine the three shared defaults, repeated scenario constructor
   calls, and named-host Home Manager configurations carrying `osConfig`.
   Compare that source structure with the available statistics. Record what
   is measured, what is inferred, and what remains unknown separately.
   → Verify: the report names source locations and evidence for each
   hypothesis; it includes runtime-test inputs rather than only booleans.

5. **Choose at most one diagnostic experiment at a time if attribution is
   unresolved.** State the question, source-grounded variant, expected
   observable difference, and cost before running. Save the original file
   separately, confirm the diagnostic diff, and retain the same source tree,
   lock, evaluator, settings, and command. A variant isolating fixture families
   has a different workload: its savings are attribution evidence only, never
   an accepted optimization. Restore the original file before interpreting
   the next experiment; do not stage diagnostic edits.
   → Verify: the variant actually landed, its measurement is valid, and the
   tracked source returns to its original content afterward. If evidence is
   inconclusive, report that instead of running an unbounded experiment loop.

6. **Write the diagnostic result and stop at the design gate.** Add measured
   results and links to captures to this plan's execution record. Explain any
   invalid measurements or unresolved cause. If evidence supports an
   optimization, propose an amendment to the spec naming its exact files,
   transformation, and coverage proof; obtain approval before drafting its
   implementation plan. Do not implement that proposal under this plan.
   → Verify: no diagnostic changes remain in production files, the report
   distinguishes evidence from hypotheses, and #747 stays open.

## Tests and measurement contract

After steps 1 and 2, with `time_bin` set to the verified GNU time path and
`capture_dir` set to a new capture directory, run under bash:

```bash
(
exec 9>/mnt/data/vmtest/.nixarchy-heavy.lock
flock -n 9 || exit 1
# Recheck the install queue and host load here before the timed command.
# If the step 2 conditions are not met, exit without evaluating.
measure_rc=0
NIX_SHOW_STATS=1 "$time_bin" -v -o "$capture_dir/time.txt" \
  nix eval --option eval-cache false --raw \
  .#checks.x86_64-linux.options \
  --apply 'd: d.outPath + " " + d.drvPath' \
  >"$capture_dir/paths.txt" 2>"$capture_dir/evaluator.txt" || measure_rc=$?
printf '%s\n' "$measure_rc" >"$capture_dir/exit-code.txt"
test "$measure_rc" -eq 0
)
```

Expected: two store paths, actual evaluator statistics, GNU time's RSS and
elapsed time, and exit code zero. No pipeline may hide the evaluation status.

Future candidate comparisons, after a separately approved implementation
design, start with one full baseline and one candidate in the same fixed tree.
Only a useful candidate justifies up to three complete samples per variant,
alternating variants and checking load before every run. Keep all samples,
compare medians against the 15%/10% targets, and stop on noisy load rather than
repeat until favorable. Preserve the full workload and identical profiling
settings. Gains within variability do not satisfy the target.

This diagnostic stage adds no test framework, new `checks.*` entry, workflow,
or VM build. Any eventual coverage check must first fail against the relevant
defect and pass with the fix. The eventual implementation must preserve exact
case names and results, build the complete options check, run relevant static
checks, and verify the existing hosted measurement on the final change.

## Rollback

Restore only diagnostic files from the saved baseline copies and verify their
diff is empty; never reset or alter another agent's worktree. Preserve captures
for review even when an experiment fails. Revert this task's documentation
commit if needed. There is no deployed system state or CI configuration to
roll back.
