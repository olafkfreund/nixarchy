---
status: draft
issue: 1942
author: x
---

# Intent: a missed scheduled workflow is started by a watchdog

## Problem

GitHub's scheduler is best effort. On 2026-11-25 it fired none of this
repository's scheduled workflows: `nightly` (03:00), `omarchy` (04:00), `update`
(05:00), `review` (06:00), `omarchy-edge` (06:00) and `flake-update` (07:00) had
each run every day from 2026-11-13 to 2026-11-24, all are `active`, and
githubstatus.com listed no Actions incident. Nothing noticed: `review` is the
job that reports a workflow that has not run (`pkgs/review.sh`, the stale-run
rows), and `review` was one of the runs that did not happen. The owner found it
by asking why an issue had not closed, and every run was then started by hand.

## Proposed outcome

When a scheduled workflow has not started within a margin of its cron time, it
is started with `workflow_dispatch` by something that does not depend on
GitHub's scheduler, and the owner is told it happened. A day like 2026-11-25
then costs a delay of up to an hour, not a person.

## Affected users and systems

- This repository's scheduled workflows: `nightly`, `omarchy`, `update`,
  `review`, `omarchy-edge`, `flake-update`, `build` (Monday) and the three jobs
  of `weekly`.
- p620, which is on all day and already hosts the self-hosted runners, as the
  place the watchdog runs.
- No end user: nothing here ships in nixarchy.

## Constraints

- Must not start a run of a workflow that already has one queued or in
  progress. `omarchy-edge` shares one concurrency group, and a newer dispatch
  cancels the running one (CLAUDE.md §8).
- Must start the right `weekly` job: its jobs select on `github.event.schedule`
  or `inputs.job`.
- Must stay well inside the API rate limit the account hit twice this week
  (#1948).
- The script is tested like any other here, with a check that fails when the
  decision is wrong (§1).
- The workflow-dispatch rule is a CI-gate change in effect, so the owner merges
  it (§11).
- Must not print the environment or any token.

## Open questions

None. Placement (a timer on p620 versus a hosted alternative) is the spec's
decision.
