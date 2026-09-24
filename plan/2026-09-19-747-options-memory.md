---
status: approved
issue: 747
spec: spec/2026-09-19-747-options-memory.md
---

# Plan: profile and attribute option-check evaluator memory

## Approved decisions

**Resumption authorization:** the owner explicitly instructed the team to
continue the open issues without further approval pauses on 2026-09-19.
Evidence-backed spec/plan amendments and implementation are therefore
authorized; record the design and evidence before making the change. This
supersedes the later approval pauses below, not the measurement or coverage
requirements. No host deployment is authorized.

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

## Resumed execution and implementation — 2026-09-19

The earlier diagnostic-only limitation was superseded by the owner's explicit
approval to continue implementation without further pauses. Work rebased onto
`main` at `133651d`; full profiles used clean commit `a653d47`, Nix 2.34.8,
GNU time 1.10, the same lock, and the approved pair expression with eval cache
disabled. The shared heavy lock was held and paginated install queries were
empty at each start. Desktop activity was recorded, not described as idle.

| setting | peak RSS (KiB) | wall (s) | user CPU (s) | GC cycles | GC heap (bytes) |
| --- | ---: | ---: | ---: | ---: | ---: |
| default | 12,241,972 | 148.64 | 231.98 | 18 | 11,626,876,928 |
| divisor 8 | 9,790,236 | 156.64 | 390.81 | 39 | 9,261,289,472 |

Captures, including command, metadata, statistics, exact paths, and exit codes:

- `/mnt/data/vmtest/747-baseline-20260919T143009Z/`
- `/mnt/data/vmtest/747-divisor8-20260919T143440Z/`

Both exit 0. Their output and derivation paths match byte for byte, as do
evaluator function/primitive calls, environments, values, sets, and list
counters. Baseline GC allocations total 27,969,363,792 bytes; the heap is not
a retained-object attribution. The installed libgc is Boehm 8.2.12; its
[environment reader](https://github.com/ivmai/bdwgc/blob/v8.2.12/misc.c#L1190)
and [documented trade-off](https://github.com/ivmai/bdwgc/blob/v8.2.12/include/gc.h#L318)
support this experiment. Collection frequency changes peak usage without
changing the checked workload, but does not identify a retaining fixture.

The single candidate sample cuts RSS 20.0% and adds 5.4% wall time, but consumes
68.5% more user CPU. Do not promote it from a many-core desktop to hosted CI
or run repeat samples for a setting we are not shipping. Default GC stays intact.

### Implement the amended spec

1. Set `NIX_SHOW_STATS=1` only on the existing options step. Keep the current
   timing, proof lookup/build, and exit-code propagation; do not add an eval.
2. In `already-proven.sh`, duplicate stderr onto descriptor 3 only when stats
   are requested, otherwise point descriptor 3 at `/dev/null`. Send only the
   existing pair eval there. Keep proof rows and cache/refusal logic unchanged.
3. Extend `checks.proof-push` using the real lookup script with a nix stub.
   Check stats visibility, normal suppression, exact rows, and failed-eval
   fallback. The original script fails with
   `NIX_SHOW_STATS=1 evaluator diagnostics were discarded`; the fix passes.
4. Run shell syntax/ShellCheck, Nix formatting, workflow lint, and the existing
   proof-push check under the shared lock when available. Do not rebuild the
   expensive options workload just to test stderr plumbing.
5. Prepare a PR with `Refs #747`, the measurements and red/green evidence.
   Keep #747 open: hosted statistics and a demonstrated acceptable memory
   reduction remain outstanding. Root coordinates publication and CI scheduling.

Rollback is the reverse of these three code changes; no installed machine,
allocator default, or CI gate has changed.

Verification completed after rebasing onto `main` at `5ab1d25`: the full
`checks.proof-push` build passed (derivation
`0bhz3sxyag67spjmxx3cklzjn92v5kb1-nixarchy-proof-push.drv`), including the new
statistics/failure-fallback assertion and all existing proof-push cases.
Bash syntax, ShellCheck, nixfmt, statix, deadnix, and whitespace checks passed.
Actionlint passed with external ShellCheck/Pyflakes disabled after its default
external-tool invocation stalled; changed shell code was checked separately.

## Addition — 2026-09-22: a warning before the ceiling

Not in the plan as approved; added at the maintainer's direction, with the
reduction itself still outstanding.

**Where #747 stands.** Everything this plan implemented is on `main` (#757, #760,
#795): the peak is measured on every run and printed to the log. That produced
the hosted statistics the plan asked for -- six `main` builds at **11,490 to
12,153 MiB of 16,384**, 70-74%, stable. The garbage-collector lever was measured
and rejected (-20% RSS for +68% CPU). A demonstrated reduction is the part left,
and it is research: the next experiment named above is the repeated editor-home
evaluations.

**The gap this closes.** The step recorded the number and did nothing with it.
Past 16 GB the runner is killed and the job reports `cancelled` with no failed
step, which AGENTS.md §6 lists three other causes for. So the step now emits a
`::warning::` at 14,336 MiB (87.5%) -- loud while there is room to act, and
never a failure, because the check has already passed by then.

**Proved** with the step's own shell, extracted from `build.yml` and run under
`bash -eo pipefail` against stubbed `/usr/bin/time` output, so no 12 GB
evaluation was spent:

| stubbed peak | result | exit |
| --- | --- | --- |
| 11,490 MiB (today's real reading) | no warning | 0 |
| 14,335 MiB | no warning | 0 |
| 14,336 MiB | **warning** | 0 |
| 14,800 MiB | **warning** | 0 |
| 14,800 MiB, guard removed | no warning | 0 |

The first attempt at that last break did not apply: a `sed` address expected
`peak_mib -ge` adjacent, and the line reads `"$peak_mib" -ge`. It was caught
because the break was checked for having landed before its result was read.

#747 stays open.


## Implementation plan — 2026-09-24: the population rescope

Drafted against the amendment approved the same day
(`spec/2026-09-19-747-options-memory.md`, "Amendment — 2026-09-24").
**Status: approved 2026-09-24.** Implementation may proceed; the steps below
are the contract, and step 8's refusal to iterate is part of it.

### The decisions, carried over so this is self-contained

- **The remedy is not additive.** Four single-target interventions were
  measured and all read null. Releasing one fixture out of ten leaves nine
  pinning a monotonic climb, so the released one is a dip rather than a lower
  peak. The population is rescoped in one change or not at all.
- **The live set is 8.04 GB of a 12.56 GB peak.** RSS overstates by 1.56×.
- **The profile climbs monotonically to the final collection.** A remedy that
  lands turns that tail into a plateau; that is the verification.
- **`vm` is flake-rooted and immovable from this file.** The floor is one
  system. ~10.5 systems account for the 8.04 GB at ~0.77 GB each.
- **Coverage proof:** `deepSeq report` byte-identical in the same tree, plus
  the built check still passing. **Not** unchanged evaluator counters.

### Steps

1. **Record the pre-change profile**, under the heavy lock, in a quiet window:
   `GC_PRINT_STATS=1 nix eval --option eval-cache false .#checks.x86_64-linux.options`.
   Keep the full sequence of `In-use heap` lines, not only the maximum — the
   shape is the instrument.
   → verify: 18-ish collections, monotonic, ending at the peak. If the
   baseline is NOT monotonic, stop: the premise has changed and this plan does
   not apply.

2. **Capture the coverage baseline in the same tree**:
   `nix eval --raw --apply 'd: builtins.deepSeq d.report d.report'` on the
   check, saved to a file.
   → verify: non-empty, and it names every case.

3. **Rescope `mvInvariantSmall` (L2196) and `mvInvariantBig` (L2211)** into a
   `let` local to `microvmProblems`, their only consumer. Two bindings, ~4
   systems — the largest addressable block.
   → verify: `nix-instantiate --parse` clean, `nix fmt` clean.

4. **Rescope `notImported` (L417)** into `modeAInert`, its only use. Already
   done once as an isolated experiment and measured null; it is included here
   because the amendment's whole point is that it only pays as part of the
   population.
   → verify: as above.

5. **Leave `loaderOff` (L399) bound.** Seventeen uses, sixteen of them narrow,
   and a narrowly-forced binding measures 0 KiB live. Rescoping it would be a
   large diff for no predicted gain, and the rule the amendment carries is to
   bind at the narrowest scope covering the reuse — seventeen uses spanning the
   file is that scope.
   → verify: stated in the PR, so the omission is deliberate rather than
   overlooked.

6. **Measure the post-change profile**, same command, same lock, same window
   discipline, in the variant tree.
   → verify — and this is the acceptance test: **the tail is a plateau or
   sawtooth rather than a monotonic climb.** A lower peak alone is not
   sufficient evidence (it sits inside a ~3% RSS band); an unchanged shape is
   sufficient evidence of failure regardless of the peak.

7. **Prove coverage**: `deepSeq report` from the variant compared byte for byte
   against step 2's baseline, and `nix build .#checks.x86_64-linux.options` in
   the variant tree so `broken` is actually exercised.
   → verify: `cmp` silent, build green.

8. **If the shape does not change, stop and report the negative.** Do not
   iterate by adding more bindings until something moves — that is
   retry-until-green against a 3% band, and §10 forbids it. Record the profile
   and leave #747 open.

### Tests

| command | expected |
|---|---|
| baseline profile | monotonic, peak at last collection |
| variant profile | **plateau or sawtooth tail** |
| `cmp` of the two `report` captures | silent |
| `nix build .#checks.x86_64-linux.options` (variant) | green |
| `nix fmt -- --ci`, statix, deadnix | clean |

Both profile runs need the heavy lock and a quiet host: §6 forbids heavy local
evaluation while an install job is active, and the plan's step 2 discipline
(recheck the queue inside the lock, immediately before the timed command)
caught a race twice on 2026-09-24.

### Rollback

One file, `tests/options.nix`, and the change is movement of declarations
rather than logic. Reverting restores the current bindings exactly. No option,
no module, no CI gate, nothing in a system closure, no user-visible behaviour.

### What this plan does not claim

It does not claim the change will work. The amendment's own risk section says
it may land null, and step 8 exists to report that rather than to keep going.
It also does not claim the work is worth doing — the check passes today at 74%
of the ceiling and PR #943 makes its failure readable — and that judgement was
left to the approver rather than assumed.
