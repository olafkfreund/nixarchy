---
status: approved
issue: 1383
spec: spec/2026-10-20-1383-bump-and-edge-coupling.md
---

# Plan: a failed Omarchy bump is visible, and edge carries main without waiting on quattro

Approved decisions, carried from the spec (line numbers on `main` b16561ff):

1. **omarchy.yml: draft PR on a failed bump.**
   - Ids: `bump` (:70), `build` (:113), `session` (:386); `counts` (:410)
     exists.
   - The build and session gates write to `$RUNNER_TEMP/gate.log` with
     `set -o pipefail; … 2>&1 | tee -a`.
   - A new step before :441 runs create-pull-request@v8 with the same
     token and branch, `draft: true`, and
     `if: failure() && steps.bump.outcome == 'success'`. Its body is the
     failed gate, the first `error` lines (`sed -n '1,40p'`), and the
     checklist from :571.
   - :518 runs `gh pr ready "$pr" || true` before `gh pr merge --auto`
     (v8's `draft: true` applies only on create).
2. **omarchy-edge.yml, `pin` (:165):** with `from_candidate` and a 40-hex
   `HAVE`, `sha=$HAVE`; otherwise the API call.
3. **omarchy-edge.yml: same-run fallback.**
   - `build` gets `continue-on-error`.
   - `pin2`/`build2` run on `origin/edge`'s pin when build failed and that
     pin differs.
   - `candidate`'s `if:` requires one build to succeed, and the job fails
     if neither did.
   - A `fallback` output; `report` files "new quattro is red".
   - Timeout 45 → 90, measured first.
4. **omarchy-edge.yml (:239):** the check list from `generated-checks.sh`.
   Capture then split, refuse fewer than 5, and keep the per-check `try`.
5. **`report` (:462):** select the rolling issue by its title.

**Two PRs, lower risk first** (owner approved specs with this split
offered). **PR A** is items 1, 2, 4 and 5. **PR B** is item 3, opened
after PR A merges and its runtime is measured. Both are §11, so you merge
them, with no auto-merge. The `coder` agent does the YAML edits for each;
the lead proves and ships.

## Steps

**PR A** (branch `ci/1383-bump-and-edge-coupling`)

1. **Coder: omarchy.yml (item 1).** → verify: `actionlint`.
   Traps:
   - the draft step's body must not include :472-478's "already proved"
     text;
   - `tee` only with pipefail in that step;
   - `$RUNNER_TEMP`, never the checkout.
2. **Coder: omarchy-edge.yml (items 2, 4 and 5).** → verify: `actionlint`;
   `bash -n` on extracted `run:` blocks.
3. **Lead: measure** item 4's runtime. On a hosted-equivalent: time
   `generated-checks.sh` plus the per-check loop on an edge candidate
   locally (cheap tier, under the lock), and compare with prepare's
   45-minute limit. If it does not fit, raise the timeout in PR A and
   record why.
4. **Lead: prove** on a throwaway branch through `workflow_dispatch`
   (§11-safe: the branch is dropped):
   - (a) a deliberately unbuildable bump opens a draft PR naming `build`;
   - (b) `from_candidate` keeps an older pin (summary line equals `HAVE`);
   - (c) a candidate missing one overlay row fails at `etc-overlay`;
   - (d) an unrelated open `omarchy-edge` issue survives a promotion.

   Record each run link.
5. **Lead: ship PR A** (`Refs #1383`).

**PR B** (after PR A merges)

6. **Coder: item 3.** → verify: `actionlint`.
7. **Lead: prove** with a broken carry patch on a scratch candidate: the
   run promotes `main` on the last good quattro, and `report` files the
   quattro failure. With both broken, nothing is pushed. Record the
   timings for the timeout.
8. **Lead: ship PR B** (`Closes #1383`).

## Tests

`actionlint` clean; the four PR A proof runs and the PR B fallback runs,
linked in each PR.

## Rollback

Revert PR B, then PR A, independently. Edge goes back to always moving
quattro and the hand-kept list.
