---
status: approved
issue: 747
intent: intent/2026-09-19-747-options-memory.md
---

# Spec: measure and reduce option-check evaluator memory

## Evidence-backed implementation amendment — 2026-09-19

The owner's instruction to continue without further approval pauses authorizes
this amendment. The local full-workload baseline measured 12,241,972 KiB RSS,
148.64 s wall, and 231.98 s user CPU. With only `GC_FREE_SPACE_DIVISOR=8`
changed, the identical output/derivation paths and evaluator operation counters
measured 9,790,236 KiB, 156.64 s wall, and 390.81 s user CPU. These are single
samples, not acceptance medians. The 20.0% lower peak is accompanied by 68.5%
more user CPU; a desktop with parallel collection does not establish the same
wall-time trade-off on the hosted runner. Do not ship that collector setting.

Instead expose the actual evaluator's statistics in the existing options CI
step, with no second evaluation and no default allocator change:

- `.github/workflows/build.yml`: set `NIX_SHOW_STATS=1` on the existing
  "Check every option both ways" step. Keep its RSS/time measurement, condition,
  command, failure propagation, and timeout unchanged.
- `.github/scripts/already-proven.sh`: preserve the existing pair evaluation's
  stderr when statistics are explicitly requested; otherwise retain suppression.
  Duplicate the destination file descriptor rather than reopening `/dev/stderr`,
  so caller log-file offsets are shared correctly. Stdout remains proof rows.
- `tests/proof-push.nix`: exercise the real script against a tiny nix stub.
  Assert requested diagnostics survive, normal diagnostics remain suppressed,
  proof rows are byte-identical, and evaluation failures retain the empty-path
  fallback. Run the check against the original suppression and observe failure.

This is a diagnostic PR using `Refs #747`, not a memory-reduction closure.
The original 15%/10% acceptance target still applies to a future optimization.
Hosted statistics establish how the allocation/collection shape compares with
the workstation before choosing that optimization. No workflow gate is changed.

## Design

### 1. Profile the evaluation that CI actually requests

The approved [intent](../intent/2026-09-19-747-options-memory.md) requires
retained-state evidence before choosing a redesign. No profile has been run
for this task. Whole-system fixture retention remains a hypothesis.

`.github/workflows/build.yml` already measures the existing options step with
GNU time. `.github/scripts/build-unless-proven.sh` delegates proof lookup to
`.github/scripts/already-proven.sh`, which evaluates both `outPath` and
`drvPath` before looking in the cache. That evaluation discards stderr, so
putting `NIX_SHOW_STATS=1` around the wrapper would lose the evaluator report.

Run its equivalent expression directly, preserving stdout, stderr, exit code,
and GNU time output in separate files. Disable the evaluation cache explicitly
for every comparison so an already-cached answer cannot stand in for an eval:

```bash
NIX_SHOW_STATS=1 "$time_bin" -v -o "$capture_dir/time.txt" \
  nix eval --option eval-cache false --raw \
  .#checks.x86_64-linux.options \
  --apply 'd: d.outPath + " " + d.drvPath' \
  >"$capture_dir/paths.txt" 2>"$capture_dir/evaluator.txt"
```

`time_bin` is the discovered GNU time executable, not the shell builtin;
`capture_dir` is a unique directory under `/mnt/data/vmtest/`. Verify both
before execution. A failing evaluation or absent statistics is a failed
measurement, never a zero-memory result. Check the installed Nix version's
actual statistics fields before interpreting them; allocation totals alone
do not establish which objects remain live or identify a retaining reference.

Record the source revision and diff, Nix version, lock file hash, host, relevant
environment/cache settings, command, and observed competing workload alongside
the measurements. Existing hosted RSS numbers provide context, not a numerical
baseline for a different machine or command. Keep the existing CI measurement
unchanged.

The CI wrapper measures the whole proof-lookup/build/push step; this profile
measures its evaluator subprocess alone. Their elapsed times have different
scope, and GNU time's maximum child RSS does not identify which subprocess
peaked. Compare each series with its own baseline, never subtract one from the
other or treat them as interchangeable.

### 2. Attribute the cost before selecting a code change

Trace `tests/options.nix` from its configuration constructors through `cases`,
`broken`, `report`, and the values passed to `pkgs.runCommand`. Include the
runtime-test inputs: measuring only the boolean report would omit part of the
real evaluation.

The first candidates to examine are the three shared defaults, repeated
scenario-specific constructor calls, and named-host Home Manager configurations
that carry `osConfig`. Preserve the distinction between standalone Home Manager,
named-host Home Manager, and the default NixOS machine. Record concurrent plugin
fixture additions when choosing the baseline, including #782's two additional
NixOS configurations if they have merged.

Start with one baseline profile. If its aggregate statistics cannot identify
the cost, choose one explicit, source-grounded diagnostic experiment before
running it. Temporary diagnostic variants may isolate fixture families, but
their reduced workload cannot count as a performance improvement or coverage
proof. Keep diagnostic edits isolated and restore the complete baseline.

The first implementation plan must cover profiling and attribution only.
Once the evidence identifies a candidate optimization, amend this spec with
the exact files, transformation, and coverage proof, and obtain approval before
writing a plan that implements it. This spec does not pre-approve fixture
deduplication, changed lifetimes, a custom evaluator, or splitting the check.

### 3. Compare the complete workload under controlled conditions

Use an isolated worktree at a fixed baseline, then compare the original and
candidate `tests/options.nix` variants within that same source tree and fixed
lock. Record each variant's diff. Comparing arbitrary commits or PR numbers
confounds the candidate with changing inputs and option coverage.

Run sequentially during a coordinated quiet window with no active install CI
jobs. Start with one baseline and one candidate; only if the candidate looks
useful, gather up to three full samples per variant, alternating variants and
checking load before each run. Compare median peak RSS and median elapsed time;
retain every sample. Stop rather than repeatedly benchmarking through noisy
or competing workload. Keep profiling settings identical across variants.

The proposed acceptance target is at least **15% lower median peak RSS** and
no more than **10% higher median elapsed time** on the complete evaluation.
These are review targets, not a claim that an unknown optimization will achieve
them. For illustration only, 15% below the recorded 11,719 MiB is about
9,961 MiB; hosted confirmation must use a contemporaneous hosted baseline.
If the target is unattainable or the apparent gain is within run variability,
report that result and revise the design rather than lower the target silently.

## Alternatives rejected

- **Split the check first:** adds evaluations before establishing what consumes
  memory and may undo #742/#745's runtime gains. Reconsider only with evidence.
- **Duplicate the CI measurement:** #757/#760 already provide it, and adding
  another wrapper would not identify the retained state.
- **Drop cases or collapse mode distinctions:** reduces the workload by losing
  the behavior this check protects.
- **Attribute all RSS to three shared defaults from source inspection:** Nix's
  laziness, transient allocations, and garbage collection require measurement.
- **Add runner memory or change CI gates:** outside this task's approved scope.

## Risks

- A shared fixture can reduce repeated evaluation while increasing object
  lifetime; a shorter source diff does not establish a memory improvement.
- Concurrent fixture additions, different evaluators, cache hits, and host load
  can overwhelm a small improvement. Record and control those variables.
- A benchmark on p620 competes with the desktop and install runners. No heavy
  run starts while install jobs are active; coordinate the quiet window first.
- Changed evaluation order can defer an error rather than eliminate cost.
  Evaluate and build the full check when verifying a candidate.
- This affects check execution, not installed hosts. No deployment is required.

## Verification

- The profiling report contains successful exit status, both derivation paths,
  usable evaluator statistics, peak RSS, and elapsed time for the actual
  expression. Explain every missing field instead of treating it as zero.
- Before/after comparisons meet the 15% RSS and 10% runtime targets above,
  with the same complete workload and reproducible command/settings.
- The eventual candidate preserves the exact case names, both-state results,
  mode distinctions, and runtime assertions; `checks.options` builds and runs
  successfully, not merely evaluates. Its approved implementation design must
  explain how this preservation is checked.
- Any new or changed coverage check must be demonstrated failing against the
  relevant defect and passing with the fix, following `tests/AGENTS.md` and
  repository rule 1. Benchmark numbers alone do not establish correctness.
- Run formatting and relevant static checks for the eventual code diff; no new
  `checks.*` entry, test framework, or CI workflow change is proposed here.
- Confirm the existing hosted options step still records RSS and time on the
  final change. A profile report alone does not close #747.

## Amendment — 2026-09-24: rescope the population, and why one at a time cannot work

**Status of this amendment: approved 2026-09-24.** The design gate in
`plan/2026-09-19-747-options-memory.md` step 6 required spec approval before an
implementation plan could be drafted; that approval is this line, and the plan
may now be written. Nothing is implemented by this amendment itself.

### What changed since the spec was approved

Four interventions were implemented and measured against the real check. All
four were null, and the reason they were null is now understood and is the
substance of this amendment.

| intervention | evaluator work removed | peak RSS |
|---|---|---|
| deduplicate scattered fixtures | −5.0% calls | 12.05 → 12.18 GB |
| deduplicate six identical **adjacent** fixtures | −2.4% calls | 12.44 → 12.52 GB |
| scope a single-use deeply-forced binding | 0 by construction | 12.46 → 12.46 GB |
| builder attribute set | n/a — retains 0.157 MB | not addressable |

Two measurements explain all four.

**The live set is 8.04 GB of a 12.56 GB peak.** Read from the collector's
post-collection `In-use heap`, not inferred from RSS, which overstates it by
1.56×. Every per-fixture figure in the earlier execution record was computed
from RSS and is inflated by about half.

**The live-heap profile climbs monotonically to the final collection.**
Eighteen collections, one non-monotonic step:

```
 1  0.00   4  0.47   7  1.30  10  2.15  13  3.29  16  5.78
 2  0.23   5  0.67   8  1.72  11  2.07  14  4.43  17  6.83
 3  0.32   6  0.93   9  1.80  12  2.62  15  4.83  18  8.04  <- peak
```

Nothing of consequence is released. A working remedy turns that tail into a
plateau; this is the signature of one that has not landed.

### The consequence, and it is the whole amendment

**The remedy is not additive.** Releasing one fixture out of ten leaves the
other nine pinning a monotonic climb — the released one becomes a dip, not a
lower peak. Every single-target experiment will therefore read null, which is
exactly what four of them did.

So the proposal is not "rescope a fixture". It is **rescope the population of
deeply-forced fixtures in one change**.

### Exact files and transformation

`tests/options.nix` only. No module, no option, no `checks.*` entry, no
workflow.

For each binding that is (a) declared in the top-level `let` and (b) forced to
`system.build.toplevel` or otherwise deeply walked, move the declaration into
an inner `let` at the binding's use site, so it becomes unreachable once that
case collapses to booleans.

The forcing sites, with the systems each materialises — `mvVm` is
`cfg: name: cfg.microvm.vms.${name}.config.config`, so each microvm binding
materialises a host **and** a nested guest:

| binding | line | uses | systems | addressable |
|---|---|---:|---:|---|
| `vm` | 1706 | 79 | 1 | **no** — rooted in `inputs.self` |
| `mvTemplateOk` | 2159 | — | 2 | already inner-`let` |
| `mvTemplateBad` | 2165 | — | ~1.5 | already inner-`let` |
| `mvInvariantSmall` | 2196 | 3 | 2 | yes |
| `mvInvariantBig` | 2211 | 3 | 2 | yes |
| `loaderOff` | 399 | 17 | 1 | yes, but 16 uses are narrow |
| `notImported` | 417 | 1 | 1 | yes — already tried alone, null |

≈10.5 systems against 8.04 GB live is **~0.77 GB per system**, consistent with
~1.09 GB for a full nixarchy desktop and lower for leaner guests and Mode A
hosts. **The arithmetic closes; nothing is unaccounted for.**

`vm` is flake-rooted: a flake output is one shared thunk `nix eval` holds for
the whole evaluation, and nothing in this file can release it. **The floor is
one system.** Any target must be stated against that floor rather than against
zero.

### Coverage proof

Corrected from the version this spec originally carried, which was wrong for
this class of change:

- `builtins.deepSeq report report` compared **byte for byte**, before and
  after, **in the same tree** — closures cannot be compared across commits
  (AGENTS.md §5).
- The check's own `broken` set must remain empty, i.e. the built check still
  passes. That requires building it, not only evaluating it.
- **Not** unchanged evaluator counters. This change alters where values are
  declared, not how many are computed, so the counters should barely move —
  but requiring them constant is the mistake the earlier spec made for a
  different experiment, where it would have admitted only a variant that
  optimised nothing.

### Verification, and it is not a peak number

**The tail shape, not the delta.** A remedy that lands turns the monotonic
climb into a plateau-plus-sawtooth. That is §1's "prove it landed" applied to a
fix rather than a bug, and it is far more sensitive than a peak inside a ~3%
RSS band.

Reported as live heap via `GC_PRINT_STATS`, which PR #943 adds to the CI step
and which costs nothing measurable.

### Risks, stated plainly

- **A single diff touching every heavy fixture in a 5,500-line check is hard to
  review.** That is the main argument against this shape, and the counter is
  that the alternative — one at a time — is measurably guaranteed to read null.
- **It may still land null.** If the climb continues after the change, the
  remedy did not take effect, and the tail shape will say so rather than
  leaving it to a 3% band.
- **Targeting the wrong bindings wastes a review.** The table above is derived
  from a source inventory plus the arithmetic closing; it has not been
  confirmed by per-binding measurement, because that needs one heavy run per
  binding and the plan permits one experiment at a time.
- **This is not obviously worth doing.** The check passes today at 74% of the
  ceiling, and #943 makes the failure readable if it ever stops passing. A
  reviewer may reasonably decide that is enough and that a large diff against a
  test file is not justified by a headroom problem that has not yet bitten.
  That judgement belongs to the approver and this amendment does not assume it.
