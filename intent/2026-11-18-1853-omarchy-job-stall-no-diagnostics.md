---
status: draft
issue: 1853
author: x
---

# Intent: a stalled `omarchy` job leaves no evidence of why it stalled

## Problem

The `omarchy` job in `build.yml` has stalled twice in three days, each time in the same step, "Verify the generated menu defaults and app template" (step 28), and each time the only outcome was the job's 60-minute cap. When it happens, the log ends mid-build and the job reports `cancelled`, which reads like an eviction (AGENTS.md section 6). Nothing in the job records what the stall was waiting on.

What was observed:

- Run 44257184740 (PR #1850, nixpkgs bump), attempt 1, job 134641907308. Step 28 started 07:47:52Z. The last log line was `building '/nix/store/rj1jgvibblpnq5n9k6lkdq2p7ymb38f3-activate.drv'...` at 07:48:24Z. The step was cancelled at 08:14:26Z, and the job's 60 minutes ran out at 08:14:13Z. Annotations: "The job has exceeded the maximum execution time of 1h0m0s" and "The operation was canceled." The last log line, its timestamp and the cleanup's killed orphans (`nix` pid 47718, `crashpad_handler` pid 47722) come from the issue text: the raw job log was not read for this intent.
- Run 43967612175 (push to `main`, merge of #1815, 2026-11-16), attempt 1, job 133651426840. Step 28 started 22:24:46Z and was cancelled at 23:12:26Z, about 48 minutes in. It has the same two annotations, and #1853 does not mention it. Its log differs: inside step 28 it prints `error: substituter 'https://nixarchy.cachix.org' is disabled` and `… is required, but there is no substituter that can build it` (22:26), then nothing until the cancel, where the 11-18 log ends at `building activate.drv`. So the same step failed to finish twice; a common cause is not established.
- The step normally takes about 1.5 minutes (two 2026-11-17 samples, from the issue; not re-derived). The re-run of 44257184740 did pass, but its step 28 took 15m19s (08:48:37Z to 09:03:56Z), which is not the "normal time" the issue describes. The same attempt's step 12, "Build every check no other job claims", took 12 minutes, against 32 minutes in the stalled attempt.
- The two stalled jobs show the same step-12 warnings about oversized proof paths (runtime-profile, nixi, doctor-plugins). Those warnings are not a cause. They are noted so nobody has to chase them again.

The job has no way to tell a slow step from a hung one, and no way to capture state at the moment it is killed:

- Step 28 and 23 of the job's other named steps carry no `timeout-minutes`. Only the 5-minute cachix push has one (`build.yml:363`). The job-level 60 (`build.yml:308`) is the only bound, so a hang in a 1.5-minute step consumes up to the whole remaining budget.
- Step 29, "Failure digest", is `if: failure()` (`build.yml:1296-1300`). A timeout cancels the job, `failure()` is false, and the step shows as `skipped` in both runs. The digest only ever reads the nix build log that `build-unless-proven.sh` keeps, and step 28 does not write to that log.
- Step 28 is the only step in the job that runs a plain `nix build … toplevel` outside `build-unless-proven.sh`, which is why it is both unbounded and invisible to the failure digest.
- No workflow runs `ps`, `pstree`, or a handler on `cancelled()`. A grep of `.github/` for `ps aux`, `pstree`, `trap ... TERM`, `timeout -s` and `--foreground` found nothing. The existing `if: always()` and `if: failure() || cancelled()` steps (`omarchy.yml:633`, `nightly.yml:73`) do reporting, not process capture.
- The only existing timeout handling is a per-step `timeout-minutes: 5` on cachix pushes (#883) and the narrative in section 6. Nothing captures process state on a timeout. The nearest precedent is `nightly.yml:506`: periodic resource output from a background sampler, cleaned up by an `EXIT` trap.

Candidate causes named in #1853 (a stalled download, a daemon lock held by the orphan, or an earlier step leaving a process holding the store) remain unconfirmed. This intent could not tell them apart from the retained evidence.

## Proposed outcome

When the `omarchy` job stalls, the person reading it can tell from the run itself, without a re-run, whether nix was waiting on a lock, a download, a build, or something else, and which process tree held it. A stall in step 28 or any other step costs minutes rather than the job's whole cap, and the failure is identifiable as a stall rather than as an eviction. A recurrence is recognised as a recurrence: it is findable by one query, and tied back to this issue.

## Affected users and systems

- Anyone merging through `build.yml`. The `omarchy` job is a required check. A stall blocks the merge, and the cancelled conclusion silently disables auto-merge (section 6). Both observed stalls hit an unrelated change: a nixpkgs bump, and a `main` push.
- The owner and agents triaging a cancelled `omarchy` job. They currently cannot tell a stall from a queue eviction without reading annotations by hand.
- Hosted `ubuntu-26.04` runners. Each stall costs a full runner-hour, and the re-run costs more.
- `nightly.yml` and `omarchy-edge.yml` may build the same steps; whether they share the exposure was not checked.

## Constraints

- Changing workflow timeouts or required checks is a CI-gate change that needs a human merge (CLAUDE.md section 11). This intent only proposes; it does not authorise one.
- A diagnostic must not change a job's conclusion, and must not itself hang. `failure-digest.sh` is the model: it always exits 0.
- Hosted runners are one-shot. Evidence must outlive the runner, and because the owner deletes runs it must also outlive the run: `AGENTS.md:1373` copies evidence into an issue for that reason (section 13).
- A timeout reports `cancelled` with no failed step (section 6). Any change must keep the stall distinguishable from an eviction, whose annotation reads "Canceling since a higher priority waiting request".
- Whatever is added has to be checked against a forced stall, per section 1. A diagnostic that has never been seen firing is a green light.
- Both stalls' cleanups killed a `nix` and a `crashpad_handler` four pids apart (47718/47722, 17482/17486). Neither log records parents or start times, so where the `crashpad_handler` came from is unexplained.

## Open questions

1. Are diagnostics required, or is a shorter stall enough? The title's problem is the missing evidence, so a bound alone would leave it.
2. Scope: step 28 only, or every step of the `omarchy` job?
3. How much delay against how many false cancellations is acceptable? Step 28 normally takes about 1.5 minutes, but its re-run took 15 and step 12 varies from 12 to 32 minutes, so a tight bound will cancel slow-but-healthy runs on a cold-store nixpkgs bump.
4. Should a timed-out `omarchy` job re-run itself once, or stay red so the stall stays visible? `cancelled` disables auto-merge.

For investigation, not decisions: whether the two stalls share a cause (cache, lock or something else), and where the `crashpad_handler` comes from.

