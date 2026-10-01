---
status: draft
issue: 1134
author: olafkfreund
---

# Intent: a failed install gate blocks the merge, proven rather than inferred

## Problem

`install` is a required status check on `main`, alongside `lint`, `omarchy`,
`system`, `devenv-presets` and `box`. It `needs: gate`, so if `gate` fails, an
API outage or a script error for example, `install` does not run and its
check-run concludes `skipped`.

Whether a `skipped` required check blocks the merge is **unmeasured**:

- `install-check.yml:162` and `:304` say it does: "`skipped` is not
  `success`, so the merge is blocked". #187's probe (commit `4e894c4`)
  measured only that a skipped job *reports* a check-run with conclusion
  `skipped`. The merge outcome was inferred from that.
- #1134, from the #1097 security review, cites GitHub's documentation: a
  job skipped by a condition reports as passing, and does not prevent a
  merge even when required. That is also not reproduced.

If the docs are right, a gate failure lets a pull request merge with **no
install check at all**, and the file's comments say the opposite, so nobody
would look. If #187's inference is right, #1134 is not a bug, and the
comments need only a citation.

## Proposed outcome

- The question is answered by measurement on this repository's actual
  ruleset. The answer, with the evidence, is recorded at the comment that
  makes the claim.
- **If skipped can merge:** a failed `gate` turns `install` **red**, not
  skipped. This is #1134's shape: `install` runs under `always()` and fails
  first when `needs.gate.result != 'success'`. Every other path keeps today's
  behaviour, including the steps-conditional green for irrelevant changes
  (#187).
- **If skipped blocks:** no workflow change. The comments cite the
  measurement, and #1134 closes as verified-not-a-bug.

## Affected users and systems

- `.github/workflows/install-check.yml`, the `install` job, and only if the
  measurement says so.
- The coverage guard in `build.yml`, which allowlists job `if:` shapes, and
  only if `install` gains one.
- Every pull request's merge gate, but no module, package or installed
  machine.

## Constraints

- **This is a CI-gate change (AGENTS.md §11).** The owner merges any
  workflow edit; I propose it.
- **The probe must not touch `main` or any other pull request.** It must not
  hold an install slot, and must never be merged.
- **Prove the check fails (§1):** whatever ships has to be shown turning a
  gate failure red on a real run.
- **No change to the rule set or repository settings** (§11).

## Open questions

1. **How to measure.** Recommended: a throwaway draft PR from a branch whose
   `install-check.yml` makes `gate`'s first step `exit 1`. Same-repo pull
   requests run the head's workflow file, so `install` reports `skipped`
   under the real ruleset. `gh pr view --json mergeStateStatus` then
   answers it: `BLOCKED` means skipped blocks; `CLEAN` or `UNSTABLE` means
   it would merge. Nothing attempts a merge.
   - The gate fails before slot assignment, so no install VM starts.
   - The PR is closed and the branch deleted afterwards.
   - This needs your go-ahead, because it pushes a modified workflow, even
     to a branch that is never merged.
2. **If you'd rather not probe:** apply #1134's fix anyway as
   belt-and-braces. It is a few lines and correct either way. The cost is a
   job-level `if: always()` that the coverage guard must learn.
