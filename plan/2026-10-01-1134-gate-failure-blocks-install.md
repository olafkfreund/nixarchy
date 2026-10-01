---
status: approved
issue: 1134
spec: spec/2026-10-01-1134-gate-failure-blocks-install.md
---

# Plan: a failed gate turns every required check it guards red

## Approved decisions, carried from the spec

- **Measured on #1144:** a gate failure left the required `install`
  `skipped`, and the PR `MERGEABLE`/`UNSTABLE`. A skipped required check
  does not block a merge.
- **In scope:** `install` (`install-check.yml`), and `devenv-presets`,
  `system`, `box` and `apps` (`build.yml`). All of them `needs: gate`.
- **Each of those jobs gets:**
  - a job-level `if: ${{ !cancelled() }}`. Not `always()`, so a run someone
    cancels doesn't start jobs;
  - a first step, identical in every job:

    ```yaml
          - name: The gate did not succeed, so this check cannot pass
            if: needs.gate.result != 'success'
            run: |
              echo "::error::gate concluded '${{ needs.gate.result }}'; refusing to report this required check as passed (#1134)"
              exit 1
    ```

- **`install`'s `runs-on`** becomes
  `${{ needs.gate.result == 'success' && fromJSON(needs.gate.outputs.runner) || 'ubuntu-latest' }}`.
  The concurrency group already falls back to `install-noop-<ref>`.
- **The coverage guard's `allowed_ifs`** gains exactly two lines:
  `${{ !cancelled() }}` and `needs.gate.result != 'success'`.
- **The comments repeating "`skipped` is not `success`, so the merge is
  blocked"** are corrected, citing #1144. #187's path-filter lesson (an
  absent check blocks forever) stays.
- **Rejected:** leaving it; `always()`; an aggregator job (a ruleset
  change); fixing `install` alone.
- **§11:** I open the PR; the owner merges it.

## Model split

Two files, but five steps that edit them, so per the managed policy this
goes to one `coder` agent, step by step via `SendMessage`. Review is by a
fresh Opus agent, given only this plan and `git diff`. I run steps 6–8
myself, because they need the owner-approved probe and the PR.

## Steps

1. **`install-check.yml`, the `install` job** (header at about line 203,
   `runs-on` at 320, `steps:` at 328):
   - add `if: ${{ !cancelled() }}` after `needs: gate`;
   - replace `runs-on` with the fallback form;
   - insert the gate-result step as the first step.

   → verify: `actionlint .github/workflows/install-check.yml` shows no new
   findings.

2. **`build.yml`, the jobs `devenv-presets` (241), `apps` (1209), `system`
   (1281) and `box` (1654).** In each:
   - add `if: ${{ !cancelled() }}` after `needs: gate`;
   - insert the gate-result step as the first step.

   `system` keeps its own `concurrency` block untouched.

   → verify: `actionlint .github/workflows/build.yml` shows no new findings.

3. **`build.yml`, the `allowed_ifs`** (about line 448). Append the two
   allowed conditions, each on its own line, in the same indentation. Run the
   guard's loop by hand (bash) over both files, with no rogue conditions.

   → verify: the extracted guard loop prints no `rogue`, and fails if one
   line is removed from the allowlist (§1).

4. **Comments in `install-check.yml`:**
   - `:162`: the gate's contract comment. A failed gate now makes `install`
     fail via its first step, not skip.
   - `:304–311`: the "No `if:` on this job" block. It keeps the #187
     measurement that skipped *reports* as skipped. It now says that this
     does **not** block a merge (#1144), and that this is why the job runs
     under `!cancelled()` and fails a failed gate itself.

   → verify: reading the diff.

5. **Comments in `build.yml`:** the same correction at the four copies of
   the claim (about lines 245, 1213, 1324 and 1658). One or two lines each,
   pointing at `install-check.yml`'s block for the measurement.

   → verify: `grep -n "so a required" .github/workflows/build.yml` shows no
   copy of the old claim.

6. **Probe (owner-approved with the spec).** A throwaway branch
   `probe/1134-fix`, from this branch, adds `exit 1` as the first step of
   both gates. Open it as a non-draft PR titled "PROBE … do not merge".
   - Wait for the checks.
   - Record: `install`, `devenv-presets`, `system` and `box` conclude
     `failure` with the #1134 message, and `mergeStateStatus` is `BLOCKED`.
   - Close the PR unmerged and delete the branch.

   No install VM starts, because the slot falls back to noop.

7. **Real PR.** Push `fix/1134-gate-failure-blocks-install` and open the PR,
   linking all three artifacts and including:
   - #1144's `UNSTABLE` result;
   - step 6's failing output;
   - the note that §11 means the owner merges.

   → verify: on its own run, `install` builds and passes, the `build.yml`
   jobs pass, and the coverage guard passes.

8. **Write back (AGENTS.md "write back what cost you an hour").** In the same
   PR, add one bullet to AGENTS.md §4: "a skipped required check passes the
   merge gate". It cites #1144, and notes that #187 measured the conclusion
   but inferred the consequence. This is §4's own subject: a check that
   cannot run reads as one that passes.

## Tests

- `actionlint` on both workflows, run as cheap tier under the build lock:
  no findings beyond those on main.
- The guard loop, run by hand under bash: clean as written, and red with one
  allowlist line removed.
- Step 6's probe is the end-to-end failing proof, and step 7's run is the
  passing one.

## Rollback

Revert the squash commit. Both workflows return to skip-on-gate-failure,
and the measured hole with them.

## Deviations recorded during implementation

- **Step 3: the escape.** A literal `${{ !cancelled() }}` inside the guard's
  `run:` script is evaluated by GitHub, and `cancelled()` is not allowed
  there; actionlint flagged it. The allowlist line is written as
  `${{ '${{' }} !cancelled() }}`, GitHub's documented literal escape. It
  renders to the text the guard extracts. If it rendered any other way, the
  guard would go red, not green.
- **actionlint deadlocks on `build.yml` locally** when shellcheck is
  enabled. Every lint here ran as `timeout 120 actionlint -shellcheck=`.
  The new `run:` scripts are two trivial lines.
- **Review (fresh Opus) corrections, comments only:**
  - The `install` comment no longer claims `needs:` is the only skip path.
  - The four `build.yml` copies are cut to three lines each.
  - The guard's description of its allowlist names the #1134 pair.
- **Step 6 measures one more case.** A run cancelled while `gate` is still
  running never starts the gated jobs under `!cancelled()`, just as before.
  The probe cancels one run mid-gate and records what `install` reports,
  so the PR states whether that path is a hole. If it is, that is a
  follow-up issue, not this PR, because the plan chose `!cancelled()` over
  `always()` deliberately.
