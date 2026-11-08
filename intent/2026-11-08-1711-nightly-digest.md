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
  comment, names each failed **job and step**, says whether it failed or was
  cancelled (a timeout reads as cancelled), and, where the failure was a
  derivation, carries a bounded excerpt of its error. Not every nightly
  failure is a derivation: the ISO size and budget steps fail outside
  `nix build` (`nightly.yml:171-190`).
- A job that timed out is still reported by name and step, even though
  nothing inside it ran after the timeout.
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
- Bounded size: an issue comment has a 65,536-character limit. Each digest
  is already capped (`failure-digest.sh:67-70,89-94`), and the whole issue
  text needs a cap of its own when several jobs fail at once.
- Not a CI-gate change (§11): no trigger, required check or timeout moves.
- `failure-digest.sh`'s output for `build.yml` and edge is unchanged.

## What the reviews established (Codex, agy)

- `failure-digest.sh` cannot read a GitHub job log as it stands: it matches
  `^error: Cannot build` at line start (`:27`), and a job log prefixes every
  line with a timestamp.
- Its excerpt comes from `nix log "$drv"` (`:70`), which answers only where
  the store is. The install jobs run on self-hosted runners that share p620's
  store; `report` runs on a hosted `ubuntu-26.04` runner with no checkout and
  only `issues: write`.
- p620's store keeps each check's build log after the run is deleted, which
  is how #1604's 2026-11-08 failure was recovered.

## Open questions

1. **Where is the digest built?** Three candidates:
   - inside each failing job, which a timeout may never reach;
   - in `report`, from `gh api` job logs, which needs the parser widened,
     `actions: read` and a checkout, and still has no `nix log`;
   - on a self-hosted runner after the failed jobs, from `nix log` of each
     failed check's derivation in p620's store.

   Recommendation: the third, because it is the only one that reaches a
   timed-out job's log and needs no change to the parser. The spec must
   first measure what `nix log` holds for a build killed by a job timeout.
   Job and step names come from the run's job list in every case.
2. **How much excerpt?** Recommendation: what `failure-digest.sh` prints
   today for each root failure, plus a cap on the whole issue text.
