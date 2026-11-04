---
status: draft
issue: 1602
author: x
---

# Intent: Edge's report says what happened, and a refused quattro commit is not an outage

## Problem

`omarchy-edge` has filed "The Omarchy edge channel is not publishing" 25 times
since 2026-10-15. The owner sees it constantly and reads it as a broken channel.
Over the same period edge published steadily: across 31 pins, the lag from a
quattro commit to its first edge publish was about 2.6 h at the median and
25.2 h at worst.

The 46 failure signatures recorded in those issues:

| Count | Signature | Did edge move? |
|---|---|---|
| 15 | quattro red, edge kept on its last good pin | yes |
| 15 | verify | no |
| 11 | prepare, other | no |
| 5 | merge conflict merging main | no |

Each is a signature, not a root cause. Run logs for many of the red runs now
return 404, so most `verify` causes can't be recovered.

Four separate defects sit underneath:

1. **A successful publish is reported as an outage.** When quattro is red and
   the fallback pin publishes, `report` still files or keeps the "not
   publishing" issue. The next clean promotion closes it, and the next refused
   commit files a new one, so normal upstream churn produces a stream of alarms.
2. **The signature hides the check.** `edge-build.sh` runs the generated checks
   as one `try`, so it can only say `generated-checks`. A missing ledger row,
   which needs a classification, reads the same as a real regression or a flaky
   test. Every reader has to open a 30,000-line log. Also, `prepare`'s `failed`
   output never reads `build2`, so a red fallback isn't named either.
3. **A flaky check can refuse a good commit.** #1601 failed only
   `restart-terminal-wrapped`, on `.kitty-wrapped did not get SIGUSR1`. Upstream's
   11 commits didn't touch that script, and the check passed about 17 minutes
   later on the fallback pin. The test starts its stand-ins in the background and
   signals them without waiting for them to exec. **That race is suspected, not
   proven:** 200 of 200 uncontended trials on p620 hit, and the contended trial's
   result goes in the spec.
4. **A waiting carry can be deleted.** A run that doesn't start from the candidate
   force-pushes `edge-candidate`, and any carry waiting there is gone with no
   message (CLAUDE.md §8, #1578). Today the only protection is remembering.

## Proposed outcome

- "The Omarchy edge channel is not publishing" is filed only when edge really
  didn't publish. If you see it, something needs doing.
- A quattro commit held back while edge still publishes stays visible in a
  separate, calm form. It names the refused commit and the check that refused it.
  If it stays held too long, it escalates, so an unadopted upstream can't stall in
  silence.
- Every report names the failing check, for the first attempt and the fallback.
- `restart-terminal-wrapped` no longer fails on process start-up timing, if the
  race is confirmed.
- A carry waiting on `edge-candidate` is not silently deleted.

## What this does not fix

"For good" is not achievable for everything, and the report shouldn't pretend
otherwise. These stay as real alerts, and they're about 31 of the 46 signatures:

- **`verify` failures (15):** a real regression, or p620 being busy or switched.
  Their causes are unknown because the logs are gone. Named checks will finally
  measure them, and a later issue can act on that.
- **Merge conflicts (5):** edge carries touching what `main` also changes.
- **Other `prepare` failures (11):** builds, runner limits, an unknown count word.

**The classification work itself remains.** Quattro moves several times a day,
and a new script, package or menu row still needs someone to decide what it means
on NixOS. This change makes that work visible and correctly labelled; it doesn't
remove it. Edge stays one pin behind until the row lands.

## Affected users and systems

- The owner and agents, who read these issues.
- `.github/workflows/omarchy-edge.yml`, `.github/scripts/edge-build.sh`, and
  `tests/restart-terminal-wrapped.nix`.
- Edge users see no change: what can reach `edge` stays exactly the same.

## Constraints

- **No gate gets weaker.** An unclassified upstream script, package or menu row
  never reaches edge. Soft-failing classification checks was considered and
  rejected by codex, agy and me.
- Promotion stays fast-forward only, through `edge-promote.sh`.
- `report` must still fail loudly if it can't read or write the issue (§4), and
  an unknown failure must never be labelled a harmless classification gap.
- This edits a workflow, so under §11 it's a CI change: approving the plan and
  merging is the owner's decision, not an agent's.
- Every check I add has to be shown failing first (§1).

## Open questions

1. **Where does the held-commit state live?** I recommend a second rolling issue,
   "Omarchy quattro is held back", which is quiet, deduplicated, and closed once
   the commit lands, with its title changing after 24 h held. The alternative is
   the job summary alone until 24 h, which makes less noise, but nobody reads a
   summary.
2. **Should the fallback also cover `readme-counts`?** Today a count word the
   script doesn't know stops the run after quattro builds, with no fallback. I
   recommend including it, since it's small and it removes one way for a real
   outage to happen.
3. **Should `verify` fall back too?** Today a quattro that passes `prepare` and
   fails a VM check blocks `main` from reaching edge. A fallback costs a second
   round of VM time on p620. I recommend not now: first measure how often it
   happens, using the named checks.
4. **Should rows be proposed automatically?** A failed ledger check could print
   candidate rows. I recommend a separate issue, since it's useful but it isn't
   what makes the alarm wrong.
