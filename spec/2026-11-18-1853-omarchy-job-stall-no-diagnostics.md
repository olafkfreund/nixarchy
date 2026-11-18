---
status: approved
issue: 1853
intent: intent/2026-11-18-1853-omarchy-job-stall-no-diagnostics.md
---

# Spec: a stalled `omarchy` step leaves its evidence, and step 28 is bounded

Revised after Codex review (rev 2). Changes are listed at the end.

## Design

**One new script, `.github/scripts/stall-watch.sh`, with two modes sharing one
snapshot function.** It never decides a job's conclusion except in `run` mode.

### Mode `run`: bound one command (step 28)

`stall-watch.sh run <seconds> <log> -- <cmd...>` runs `cmd` in its own process
group, teeing to `<log>`, and exits with `cmd`'s status (pipefail; `$?` of `tee`
would hide it, CLAUDE.md section 1). The effective deadline is
`min(<seconds>, remaining job budget - reserve)`, where remaining budget is
`60 min - (now - JOB_T0)` and the reserve is 5 minutes for snapshot, kill and
reporting (finding 3: the 60-minute cap at `build.yml:308` covers every earlier
step, so a fixed 25 minutes can lose to the cap if step 28 starts late).
`JOB_T0` is written to `$GITHUB_ENV` by the watch step below; if it is unset the
script uses the plain `<seconds>` and says so in the snapshot header. Runner
setup before the first step is not counted, which the reserve absorbs.

At the deadline it: (1) takes the snapshot, (2) writes it to
`$GITHUB_STEP_SUMMARY` and emits `::error title=omarchy-stall::...`, (3) kills
the process group (TERM, KILL after 10 s), (4) reports to #1853 (below), (5)
exits 124. Order matters: evidence first, kill second, network last, so a hung
report cannot cost the evidence or the cleanup.

### Mode `watch`: job-wide evidence (finding 1)

`stall-watch.sh watch <seconds>` sleeps, then takes the same snapshot once and
posts it. It is started as a native **background step** (`background: true`,
GitHub Actions workflow syntax: "Runs a step asynchronously so the job continues
to the next step without waiting for it to finish"; at most 10 per job) placed
as the first step of the `omarchy` job, with `<seconds>` = 45 minutes after
`JOB_T0` (15 minutes before the cap: room to report). Whichever step is stuck at
that moment, in step 28 or step 12 or anything else, the snapshot shows it. A
`cancel` step with `if: always()` at the end of the job terminates it (SIGTERM
per the docs) so a healthy run is not held open. A healthy slow run (step 12
alone can take 32 minutes, intent) that is still going at minute 45 produces a
snapshot too; that is extra evidence, not a failure, and the watch never fails
the job.

What I have **not** verified, and a human must see on a throwaway run before
merge: that a background step's output reaches the live log and summary while
later steps run; that a still-running background step does not hold the job
open when `cancel` is skipped; and that a `cancel` step is accepted on a
required job. If any fails, `watch` is dropped and decision 2 reverts to
step 28 only, stated plainly in the PR.

### Snapshot contents, and what it can and cannot tell (finding 2)

Inside `::group::omarchy-stall`, each section `timeout 10 ... || true` and
labelled, so a missing tool is a missing section: process forest
(`ps -eo pid,ppid,etime,stat,wchan:20,args --forest`); `/proc/locks` (lines
with `->` mark a blocked waiter, with pids, so a blocked lock request is
identifiable, not inferred from a generic futex `wchan`); `ss -tnpi` (the `-i`
fields `bytes_received`, `lastrcv` and `lastsnd` say whether an established
socket moved data recently or is idle; an established socket alone proves
nothing); for each `nix`/`nix-daemon` process, `ls -l /proc/<pid>/fd`;
`df -h /nix`, `free -m`; the nix-daemon journal tail; mtime-sorted tail of
`/nix/var/log/nix/drvs` (a builder log still growing means a build); the last
30 lines of `<log>`.

The mapping to the intent's question is a **reading rule, not a proof**:
- lock: a `/proc/locks` blocked entry whose waiter pid belongs to the nix tree;
- download: a socket owned by the nix tree whose `lastrcv` is recent or whose
  `bytes_received` is non-zero, with no builder process; an idle socket
  (`lastrcv` large, no growth) is reported as "idle connection", not as download;
- build: a builder child with a growing log;
- otherwise: "unclassified", which is itself the answer the snapshot gives.
The script prints these three tests' raw inputs, not a verdict. I could not
confirm from the retained evidence which of these two stalls was which (intent:
neither raw job log was read); cases F and G below demonstrate only that the
inputs differ between a lock wait, an active socket and an idle one.

### Wiring

`build.yml:1228` step 28 calls `stall-watch.sh run 1500 ...` in place of the bare
`nix build` at `build.yml:1231`; the Python heredoc and the `nix-instantiate`
stay (finding 1: the `nix-instantiate` is covered by `watch`, not by the bound).
The first step of the job starts the `watch` background step and writes
`JOB_T0`. Step 28 now fails at 25 minutes (or earlier if budget is short) as a
`failure`, so `if: failure()` steps run and `build.yml:1296` "Failure digest"
runs on a stall for the first time (documented: `failure()` is true after an
earlier step failed; a job timeout reports `cancelled` and kills the tree first,
so nothing can be added after the cap; I could not verify whether `always()`
steps get time after a job timeout and the design does not depend on it).

### Reporting to #1853 (findings 4, 7)

`gh issue comment` runs under `timeout 20`, after the kill, and its failure is
`::warning::could not record stall on #1853` plus `exit` unchanged, never a
changed conclusion or a skipped cleanup. The comment starts with the literal
marker `omarchy-stall` and the run URL. Precedent is `failure-digest.sh`
(always exits 0, `failure-digest.sh:1-13`), not `edge-report.sh`, which says a
failed `gh` there **must** fail its job (`edge-report.sh:5`); the diagnostic
here is the opposite case. The comments are the **successfully recorded**
recurrences (`gh issue view 1853 --comments | grep omarchy-stall`); a recurrence
whose post failed or was skipped still has the log, summary and `::error`
annotation, and a `::warning` line says the post did not land. It is not
claimed to be a complete count.

The `nightly.yml:506-515` sampler is the nearest precedent and is deliberately
not copied: a sampler loop is killed with the job and orphans its own `sleep`
(`nightly.yml:511`). One snapshot at one moment is enough.

## Decisions for approval

**Resolved at approval (owner, 2026-11-18):** decisions 1-4 as recommended, and decision 6 the **smaller** size: `run` mode only, no `watch`, no post to #1853, no permission change. The design sections on `watch` and reporting stay below as the recorded larger option.


1. **Diagnostics are required, not only a shorter stall.** Recommend yes. A bound
   alone leaves the next recurrence as unexplained as these two.
2. **Scope.** The intent's outcome says a stall "in step 28 or any other step
   costs minutes rather than the job's whole cap". This spec delivers:
   (a) evidence for a stall in **any** step (`watch`, minute 45, if the
   unverified points above hold), and (b) a **bound** for step 28 only.
   **A stall in any other step is still cancelled at the cap (60 minutes), with
   evidence but without the saved minutes.** Bounding other steps needs a
   per-step measurement (step 12 alone varies 12 to 32 minutes) that does not
   exist. This is a narrowing of the approved intent's outcome; approving this
   spec approves it, and if you want every step bounded now, say so and the
   spec is revised instead, with the numbers chosen on data.
3. **Step 28 deadline: 1500 s, capped by remaining budget minus 5 minutes.**
   The only slow-but-healthy sample is 15m19s (intent, re-run of 44257184740),
   normal about 1.5 min. 25 leaves 10 minutes over the worst healthy sample.
   Alternatives: 20 (more false cancels on a cold bump), 40 (saves little).
   A timeout change: section 11 applies, a human merges.
4. **No automatic re-run.** A re-run is retry-until-green (section 10); both
   stalled runs' re-runs passed and the recurrence stayed uninvestigated. The
   stall stays red with its evidence.
5. **Post the snapshot to #1853.** Needs `issues: write` on the `omarchy` job
   (workflow default `issues: read`, `build.yml:3-6`) and `GH_TOKEN`/`STALL_ISSUE`
   env. A fork's pull request has a read-only token: the post is skipped with the
   warning, and its evidence lives in the log and summary only. **That is an
   exception to the intent's constraint** that evidence outlive the deleted run
   (intent, Constraints) and is accepted here because a fork cannot be given
   write access. A permissions change to a required job: section 11.

6. **Size: the full design above, or the smaller one.** The lead's
   recommendation is the **smaller** one: `run` mode only (step 28 bounded,
   snapshot to the log, `$GITHUB_STEP_SUMMARY` and an `::error` annotation, then
   the kill), cases A-D, F, G and breaks 1-4 and 7. It drops `watch` (it rests on
   three unverified background-step behaviours, on a required job) and the post
   to #1853 (it widens a required job's permissions to `issues: write`). What it
   gives up: evidence for a stall outside step 28 (both stalls so far were in step
   28), and evidence that outlives a deleted run. The owner then copies the
   summary into #1853 by hand, which is how #1853 itself was filed. Either size
   keeps decisions 1-4; the larger can follow once a recurrence outside step 28,
   or a lost run, shows it is needed.

## Alternatives rejected

- **`timeout-minutes: 25` on the step, nothing else.** Shorter stall, no hook at
  the kill, the digest reads only `build-unless-proven.sh`'s log. Violates 1.
- **`if: always()` / `cancelled()` step after the job cap.** Evidence already
  killed; whether it runs is unverified.
- **Nightly-style sampler loop.** See above.
- **Wrapping all 29 steps in `run` mode.** Unmeasured bounds would cancel healthy
  runs. `watch` gives their evidence without a bound.
- **Teaching `failure-digest.sh` to read the step-28 log.** A stall has no
  `error: Cannot build` record.
- **`timeout(1)` on the nix command.** Kills, captures nothing.

## Risks

- **False cancel on a cold store** past 25 minutes: visible as `omarchy-stall`
  with a healthy-looking tree; mitigated by the evidence and by tuning.
- **Snapshot tools missing or needing root on the hosted runner** (`ss`,
  `journalctl -u nix-daemon`, unit name and `sudo` not verified). Per-section
  `|| true` gives a partial snapshot, never a hang.
- **The diagnostic hanging:** each section under `timeout 10`, reporting under
  `timeout 20`, the whole dump bounded; kill precedes reporting.
- **Background-step behaviour** (above) is unverified and decides whether `watch`
  ships.
- **Does not explain the 11-16 stall's cause** (`substituter
  'https://nixarchy.cachix.org' is disabled` preceded it; link to 11-18
  unestablished). This records the next one.
- **Unclaimed area:** `nightly.yml` and `omarchy-edge.yml` may build the same
  step; not checked. Not touched.
- Workflow edit, new step and permission change are CI-gate changes (section 11).

## Coexistence

Not user-facing configuration: CI scripts and workflow steps only; no option,
default or `environment.systemPackages` entry changes.

## Verification

**New check `tests/stall-watch.nix`** (`checks.<system>.stall-watch`, registered
beside `failure-digest` at `flake.nix:2501`). A `runCommand`, no VM, stubbed `gh`
(which records its args and, in case E, hangs or fails). It needs no workflow
edit (section 4): `generated-checks.sh` builds unclaimed checks; confirm in the
run log.

Cases (each varies the variable under test; split fields start non-empty):

- A. `run`, `cmd` = `sleep 600`, deadline 2 s: exit 124; output contains the
  unique snapshot header `== process forest ==` and, inside it, `sleep 600`; the
  `sleep` pid is gone (`kill -0` fails); stub `gh` recorded one call with `1853`
  and the marker.
- B. `run`, `cmd` = `true`: exit 0, no `== process forest ==`, `gh` not called.
- C. `run`, `cmd` = `sh -c 'exit 3'`: exit 3 passes through, no snapshot.
- D. A snapshot tool (`ss`) absent from PATH: still exit 124, other sections
  printed.
- E. `gh` stub hangs (sleeps 600): script still exits 124 within the `timeout 20`
  bound plus slack, process group already killed; second sub-case `gh` exits 1:
  exit 124, a `::warning` line.
- F. Lock wait: a helper holds `flock` on a file, a second process blocks on it;
  `run` with that as the command prints a `/proc/locks` section containing a `->`
  waiter line with the second pid. (If the sandbox has no `/proc/locks`, the case
  says so and is skipped loudly, not silently.)
- G. Socket activity: a local listener plus a client sending bytes, versus one
  idle; the `ss -tnpi` section shows differing `lastrcv`/`bytes` for the two.
  F and G demonstrate that the snapshot can tell the three waits apart; they do
  not prove a verdict on a real runner.
- H. `watch 2`: prints one snapshot and posts once; a `TERM` before the deadline
  produces nothing and exits 0.
- I. Wiring: `grep` that `build.yml` step 28 invokes `stall-watch.sh run` and
  that the job's first step starts `watch` (static, in the same `runCommand`).

**Break proof (section 1), to run and capture for the PR** (tree committed
first; `git diff` confirms each break landed; restore with
`git checkout HEAD -- <path>`, section 5):

1. Delete the snapshot function body. Expect A to fail with
   `A: no '== process forest ==' in output` (not the marker string alone: the
   `::error` annotation also carries `omarchy-stall`).
2. Change the deadline branch to `exit 0`. Expect `A: exit 0, wanted 124`.
3. Capture status with `set +o pipefail` then `$?` after `tee` (pipefail must be
   off, with it on `$?` still returns the left side's 3, verified here). Expect
   `C: exit 0, wanted 3`.
4. Remove the process-group kill. Expect `A: sleep 600 still running`.
5. Remove the `timeout 20` on `gh`. Expect E to exceed its bound.
6. Remove the `stall-watch.sh run` call from `build.yml` step 28. Expect I to
   fail with `I: step 28 does not call stall-watch.sh`. Same for the `watch` step.
7. Drop the `/proc/locks` section. Expect F to fail.

Each is build, watch it red, restore, watch it green.

**Tiers (section 6).** `stall-watch`: cheap `runCommand`, one at a time under
`flock /mnt/data/vmtest/codex-build.lock`. Before the push: every target
`generated-checks.sh` prints, `nix fmt -- --ci`, statix, deadnix, `shellcheck`,
`checks.grep-q-pipefail`. No VM or package-tier build.

**Not provable locally, stated in the PR:** that the hosted runner has `ss`,
journal access and `issues: write`; that background-step output and `cancel`
behave as assumed; that a real stall produces the expected snapshot. A human
exercises the first two with a throwaway `workflow_dispatch` run whose step is
`sleep`; the third waits for a recurrence. The PR says the capture was seen
firing in the test, not on a runner.

## Revision log (rev 2, Codex review)

Finding 1: added `watch` mode and made the narrowing of the intent explicit in
decision 2. 2: snapshot reworded as inputs plus reading rule, cases F, G added.
3: deadline capped by remaining job budget with reserve. 4: `gh` bounded, post
after kill, precedent corrected to `failure-digest.sh`. 5: break 3 corrected,
unique snapshot header, wiring break and case I. 6: background steps evaluated
and adopted for `watch`, with unverified points listed. 7: comments described as
recorded recurrences; fork exception stated.
