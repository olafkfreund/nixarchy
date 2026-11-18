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
- Run 43967612175 (push to `main`, merge of #1815, 2026-11-16), attempt 1, job 133651426840. Step 28 started 22:24:46Z and was cancelled at 23:12:26Z, about 48 minutes in. It has the same two annotations. This recurrence is not mentioned in #1853. Nobody noticed it, because the run was never re-run and the issue text calls the stall unreproducible.
- The step normally takes about 1.5 minutes (two 2026-11-17 samples, from the issue; not re-derived). The re-run of 44257184740 did pass, but its step 28 took 15m19s (08:48:37Z to 09:03:56Z), which is not the "normal time" the issue describes. The same attempt's step 12, "Build every check no other job claims", took 12 minutes, against 32 minutes in the stalled attempt.
- The two stalled jobs show the same step-12 warnings about oversized proof paths (runtime-profile, nixi, doctor-plugins). Those warnings are not a cause. They are noted so nobody has to chase them again.

The job has no way to tell a slow step from a hung one, and no way to capture state at the moment it is killed:

- Step 28 and 23 of the job's other named steps carry no `timeout-minutes`. Only the 5-minute cachix push has one (`build.yml:363`). The job-level 60 (`build.yml:308`) is the only bound, so a hang in a 1.5-minute step consumes up to the whole remaining budget.
- Step 29, "Failure digest", is `if: failure()` (`build.yml:1296-1300`). A timeout cancels the job, `failure()` is false, and the step shows as `skipped` in both runs. The digest only ever reads the nix build log that `build-unless-proven.sh` keeps, and step 28 does not write to that log.
- Step 28 is the only step in the job that runs a plain `nix build … toplevel` outside `build-unless-proven.sh`, which is why it is both unbounded and invisible to the failure digest.
- No workflow runs `ps`, `pstree`, or a handler on `cancelled()`. A grep of `.github/` for `ps aux`, `pstree`, `trap ... TERM`, `timeout -s` and `--foreground` found nothing. The existing `if: always()` and `if: failure() || cancelled()` steps (`omarchy.yml:633`, `nightly.yml:73`) do reporting, not process capture.
- The only existing timeout handling is a per-step `timeout-minutes: 5` on cachix pushes (#883) and the narrative in section 6. There is no pattern to reuse.

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
- Hosted runners are one-shot. Evidence must be written to the log or the step summary, because the runner is gone afterwards and the owner deletes old runs (section 13).
- A timeout reports `cancelled` with no failed step (section 6). Any change must keep the stall distinguishable from an eviction, whose annotation reads "Canceling since a higher priority waiting request".
- Whatever is added has to be checked against a forced stall, per section 1. A diagnostic that has never been seen firing is a green light.
- The `crashpad_handler` pid was 47722 and the `nix` pid 47718, four apart. That suggests both started inside the same nix process tree rather than in an earlier step, but this is inference, not evidence.

## Open questions

1. How much of the cap may a hung step spend? The two stalls reached step 28 with different budgets left (33.5 and 12.5 minutes into the job). Step 28 normally takes about 1.5 minutes, but its re-run took 15 minutes and step 12 varies from 12 to 32 minutes. A per-step limit that fits the slow case still leaves a long stall, and a tight one will cancel slow-but-healthy runs on a cold-store nixpkgs bump. Which does the owner prefer?
2. Is a diagnostic on timeout wanted at all, or is shortening the stall enough? A diagnostic costs a new step shape that nothing in `.github/` has yet.
3. Should a timed-out `omarchy` job re-run itself once, or stay red so the stall stays visible? A re-run passed here, and `cancelled` disables auto-merge.
4. Does this stall belong with the cache-substitution and lock hypotheses already in sections 4 and 6 (the 522 and `stalled-download-timeout = 60` history), or is it a separate class? That depends on evidence nobody can now retrieve for the two stalls.
5. Is the second stall (run 43967612175) enough to treat this as recurring? If so, should #1853 be amended to record it, and should the other cancelled `omarchy` jobs over a longer window be audited? Only the last 60 `build.yml` runs were scanned.
6. Does the `crashpad_handler` matter? Nothing in `.github/` or `flake.nix` visibly launches Chromium or Electron in this job. If it comes from a sandboxed check build, it points at that check. If it comes from the host, it points at the runner image. Is that worth chasing before there is any capture?
