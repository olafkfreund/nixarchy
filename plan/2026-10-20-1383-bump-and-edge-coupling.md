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

## Deviations (PR A)

- **The draft PR is two steps.** `draft_body` computes the gate and body
  in shell; then create-pull-request runs. There is no `add-paths`,
  matching the existing ready PR step. With no gate known, the title
  says "an earlier step".
- **The generated list goes through `build-unless-proven.sh`**, not a
  per-check loop. `generated-checks.sh` prints **144** checks, not the
  ~26 the spec estimated, and 144 evaluations would not fit. That is the
  script build.yml's `omarchy` job uses for the same list: slices of 5,
  `--keep-going`, cache-proven checks skipped, continuing past a failed
  slice.
- **Step 3's measurement is by proxy.** build.yml's `omarchy` job builds
  the same `.#omarchy` plus the 144 checks through the same script on the
  same runner type in 25-28 min (four main runs, 2026-10-20). Prepare's
  timeout goes 45 → 75. The first real edge run after merge confirms it.
- **Step 4's proofs are a local harness, not throwaway-branch dispatches.**
  A real edge dispatch acts on the real `edge`/`edge-candidate` refs, so
  a passing proof would promote the edge channel from a test. The harness
  (`/mnt/data/vmtest/harness-1383.sh`) runs each changed `run:` block from
  the new workflow and from `main`'s, with stub `gh`/`nix`:
  - (b) `from_candidate` keeps `HAVE`; main's moves the pin (red);
  - (d) the report picks the rolling issue by title, not #1377; main's
    picks #1377 (red);
  - (c) refuses fewer than 5, names a failing build, and passes a green
    list;
  - (a) the draft body names the failed gate and its first error line.
- **(a) found a bug in the new code:** `gate=an earlier step` (unquoted)
  ran a command named `earlier` and died with 127, which would have
  killed the draft step and left the failed bump silent again. Quoted.

## Deviations (PR B)

- **The build body moved to `.github/scripts/edge-build.sh`, unchanged**,
  so `build` and `build2` run one script, not a copy-paste. #1393's
  capture line (`exec > >(tee …)`) goes there when the two meet.
- **`good` is its own step** before `pin2`. It reads `origin/edge`'s pin
  and sets `sha` only when that pin exists and differs from the red one;
  `pin` is untouched. `pin2` repeats `pin`'s two-copies-agree proof.
- **Step 7's proof is a local harness** (`/mnt/data/vmtest/harness-1383b.sh`),
  for the same reason as PR A: a real dispatch promotes the real edge. It
  runs the new run blocks against main's, with stub `gh`/`nix`:
  - (e) an older edge pin is the fallback; the same pin, or no `edge`,
    gives none; main has no fallback step at all (red);
  - (f) `pin2` moves the pin, and refuses a flake whose version literal
    did not move (red with that check removed);
  - (g) a promotion on the fallback comments "quattro red" and keeps the
    issue open; a normal promotion still closes it; main's closes it (red).
- **Timings are not measured.** Prepare goes to 90 minutes from PR A's
  proxy (one pass in 25-28 minutes); the first real fallback run confirms it.
