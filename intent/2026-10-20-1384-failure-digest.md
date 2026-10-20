---
status: approved
issue: 1384
author: olafkfreund
---

# Intent: a failed CI job ends with the failing check's name and its real error

## Problem

On 2026-10-20 the owner pasted failed-job log tails into the conversation
**eight times** asking "is this fixed?" or "what is this?". In none of
them did the pasted tail show the actual failure:

- **#1378's `session`**: the last 25 lines were the nixi plugin's QML
  warnings. The assertion ("the shell logged QML type errors this boot")
  was hundreds of lines up.
- **#1375's `omarchy` job**: the tail was proof pushes for checks that
  *passed* ("pushing the proof of try-preflight …"), then
  `exit code 1`. The `etc-overlay` failure was far above.
- **The `system` job**: "system-build concluded 'failure'; refusing to
  report system as passed" reads as a second, separate error. It is only
  the aggregator repeating its child's failure.
- **The edge run**: "omarchy failed / menu-verbs failed / menu-actions
  failed / bin-ledger failed / panel-loaders failed" was one cause
  (`.#omarchy` would not build) reported as five, because the four
  checks depend on it.

Each one took a log dig to answer. The information exists; it is just
never where a person looks: the last lines and the job summary.

## Proposed outcome

- **Every failed CI job ends its log**, in the last lines a person sees,
  and puts in its step summary:
  - each failed check or derivation by name;
  - its first real error: the `error:`, `AssertionError` or `FAILED`
    line, with a few lines of context;
  - for cascades, "N checks failed only because X failed".
- The aggregating `system` job names the check that failed, rather than
  "system-build concluded 'failure'".
- **The same digest classifies install-job failures**: an assertion, a
  guest deadline, a job timeout, an eviction or a runner restart. That is
  the first step #1365 and #1260 asked for.

## Affected users and systems

- The owner and any agent reading CI.
- `.github/workflows/build.yml` (the `omarchy`, `system-build`,
  `system-checks` and `system` jobs), `install-check.yml`,
  `omarchy-edge.yml`; a new shared script under `.github/scripts/`.

## Constraints

- **No status changes.** The digest only reads logs and writes text.
  Every job still passes or fails exactly as now. Touching `build.yml` is
  still §11, so the owner merges.
- **Reuse what exists.** `.github/scripts/copilot-handoff.sh` already
  extracts failing-log excerpts (`--log-failed`, error regexes). Reuse
  its patterns rather than inventing a second set.
- **The digest must never be the failure.** If it errors, the job's real
  status stands and the digest says it could not read the log. That is
  §4: a step that cannot run must not read as a pass.
- **§1:** a fixture log for each case above must produce the right
  digest: a buried assertion, passing proofs after a failure, a cascade,
  and a timeout. Each fixture is red without the feature.

## Open questions

- **Where does the digest read from?** I propose the `nix build` output
  the job already captures, plus `nix log` for each failed derivation,
  within the job. Fetching `--log-failed` from the API afterwards is
  slower and needs a token.
- **#1382 (report all drift in one build).** I propose parking it: the
  digest makes each failure cheap to read, which is most of what #1382
  wanted, and it prevents no failure on its own.

## Decisions (owner, 2026-10-20)

- The digest reads the job's own build output and `nix log` of failed derivations, within the job.
- #1382 is parked.
