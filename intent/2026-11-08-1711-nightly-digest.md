---
status: draft
issue: 1711
author: x
---

# Intent: a nightly failure report says why, without its run

## Problem

When the nightly fails, its `report` job (`.github/workflows/nightly.yml`,
around line 700) opens or comments on one issue. The body is
`The nightly $what: $RUN`, and every later night adds
`Still failing ($what): $RUN`. Nothing in either says which check failed or
how.

So the reason lives only in the run, and runs do not last. The owner deletes
failed runs from the Actions view by hand, and this repository's own cleanups
do too (2026-11-08). #1604's 2026-11-08 failure was found only by reading
p620's raw nix build log, which exists only because the runners share p620's
store. The link in the issue went 404.

`build.yml` and `omarchy-edge.yml` already solved this: they run
`.github/scripts/failure-digest.sh` after a failed build, and edge puts the
bounded excerpt in its issue text (CLAUDE.md §13, #1602). The nightly never
gained the same.

## Proposed outcome

- Every nightly failure report, the opening body and each "still failing"
  comment, names each failed check and carries a bounded excerpt of its
  error, enough to tell a timeout from an assertion and to name the step.
- That stays true when the run is deleted.
- A night whose digest cannot be built still reports the failure, saying the
  digest is missing, never less than today.

## Affected users and systems

- `.github/workflows/nightly.yml`: the `report` job, and possibly each
  self-hosted install job.
- `.github/scripts/failure-digest.sh` and `failure-excerpt.sh`, reused, with
  no change to their output for their current callers.
- Whoever reads the nightly issues: the owner, agents, and the review's
  board.

## Constraints

- The report must never fail or go silent because the digest failed:
  `failure-digest.sh` already always exits 0, and that property is kept.
- No secret, token or environment dump in the excerpt. The issue is public.
- Bounded size: an issue comment has a 65,536-character limit, and the
  digest exists to be short.
- Not a CI-gate change (§11): no trigger, required check or timeout moves.
- `failure-digest.sh`'s output for `build.yml` and edge is unchanged.

## Open questions

1. **Where is the digest built?** In each failing job, from its own build
   log (as `build.yml` does), passed to `report` as a job output or an
   artifact; or in `report`, which fetches the failed jobs' logs with
   `gh api` and digests them. Recommendation: the spec to choose, after
   checking which logs exist for a timed-out VM job. A timeout kills the
   job, so a step inside it may never run.
2. **How much excerpt?** Recommendation: what `failure-digest.sh` prints
   today for each root failure, capped per check, since its bounds were set
   for exactly this reader.
