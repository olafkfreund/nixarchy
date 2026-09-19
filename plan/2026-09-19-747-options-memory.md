---
status: approved
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

## Execution record — 2026-09-19

The plan was approved in commit `2915660`. Steps 1 and 4 have read-only
results; step 3's full profile is pending a coordinated quiet window.

- Baseline: `2915660d9ccf1fe3bbbd0fe2fea225dc84174a35`, clean worktree,
  Nix 2.34.8 and GNU time 1.10. `flake.lock` SHA-256:
  `00669a64319178c6badacd71ef1cbe359db365287ad208b8ede7b8f94e5e1194`.
- Local captures: `/mnt/data/vmtest/747-profile-20260919T083537Z/` contains
  `preflight.json` (revision, hashes, explicit environment allowlist, host/load,
  command), `options-baseline.nix`, schema-check captures, and
  `source-attribution.md`. These are local diagnostic artifacts, not CI proof.
- Workflow-specific, paginated queries returned install workflows 35431361043
  and 35431290840 in progress. The coordinator confirmed active build steps;
  no full options evaluation was started. Host load and competing processes
  were recorded, not assumed idle.
- A lightweight `NIX_SHOW_STATS=1 nix eval --expr 1` exited 0 and produced JSON
  fields for `gc`, `values`, `envs`, `sets`, `list`, and `time`. This verifies
  the output schema only; the literal expression measures none of the option
  check. Aggregate allocations/heap size do not identify retained references.

### Source-grounded hypotheses, not measured causes

- `tests/options.nix:97-99` binds three default configurations. `homeOn`
  at line 141 passes a newly evaluated named `osConfig` into Home Manager.
  Shared defaults may extend object lifetime, but their contribution to peak
  RSS is unmeasured.
- The editor home expression `homeOn everyEditor { }` appears in cases at
  lines 582 and 590, and inside the four-element activation-script map at
  line 2180. Each function call can repeat evaluation. Sharing could also
  retain more memory, so it is not yet an approved solution.
- `aiHomeWith`/`aiCase` at lines 285-289 evaluates each selected app home and
  its neighbor for opposite-state assertions. Four app configurations recur;
  this is another repeated-evaluation candidate, not a measured saving.
- `modeAInert` at line 2248 forces two complete system toplevel derivation
  paths, a wider workload than individual option reads. Removing it would
  delete the Mode A equivalence proof and is not an acceptable improvement.
- The `runCommand` attributes beginning at line 2112 also force generated
  files, scripts, package paths, and runtime-test values. A cases-only profile
  would miss those consumers and could not represent the actual check.

### Next single diagnostic question

First capture the complete baseline with the approved pair expression and
shared lock. If aggregate statistics leave attribution unresolved, ask whether
the repeated editor-home evaluations account for a material part of the
allocation and peak cost. Specify one temporary variant and its expected
observation before running; retain the full source diff and restore it after.
Do not promote that experiment to an optimization or claim the 15%/10% target
without complete-workload comparisons and the subsequent design approval.

No memory reduction, retained-state cause, or issue closure is claimed.
