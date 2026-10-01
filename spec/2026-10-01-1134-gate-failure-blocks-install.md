---
status: approved
issue: 1134
intent: intent/2026-10-01-1134-gate-failure-blocks-install.md
---

# Spec: a failed gate turns every required check it guards red

## The measurement

The approved probe, PR #1144, ran a branch whose `install-check.yml` gate
ran `exit 1`. At 16:58 UTC on 2026-10-01, on head `ea0190a0`:

- `gate` concluded `failure`, and the required `install` concluded `skipped`;
- every other required check (`lint`, `omarchy`, `system`, `box`,
  `devenv-presets`) concluded `success`;
- `mergeable` was `MERGEABLE` and `mergeStateStatus` was **`UNSTABLE`**.

`UNSTABLE` means mergeable with a non-required check failing. **A skipped
required check does not block the merge.** #1134 is real, and the
comments at `install-check.yml:162` and `:304` are wrong. #187's probe
measured the `skipped` conclusion correctly; its merge consequence was
inferred and was wrong. The PR was closed unmerged and the branch deleted.

## Scope: three more jobs with the same defect

`build.yml` uses the same shape. `devenv-presets`, `system` and `box` are
required and `needs: gate` (`build gate`); `apps` does too, but is not
required. A failed `build gate` skips all of them, and a PR can merge with
only `lint` and `omarchy` green. The fix and the evidence are identical, so
both workflows are in scope. Leaving them would be §12's "search for the
behaviour" miss.

## Design

For each gated job that is a required check (`install` in
`install-check.yml`; `devenv-presets`, `system` and `box` in `build.yml`),
and for `apps`, for consistency:

1. **A job-level `if: ${{ !cancelled() }}`.** The job then runs when its
   gate fails, instead of being skipped. `!cancelled()` and not `always()`:
   a run someone cancels should not start four jobs only to fail them.

2. **A first step that fails a failed gate:**

   ```yaml
   - name: The gate did not succeed, so this check cannot pass
     if: needs.gate.result != 'success'
     run: |
       echo "::error::gate concluded '${{ needs.gate.result }}'; refusing to report this required check as passed (#1134)"
       exit 1
   ```

   Every existing step already conditions on `needs.gate.outputs.relevant`,
   which is empty when the gate failed. So no build step runs after a
   failed gate. The one that could, the "nothing here can affect" no-op
   (`relevant != 'true'`, which is true of empty), never gets there, because
   step 1 has already failed the job.

3. **`install`'s `runs-on` falls back** to a hosted runner when the gate did
   not succeed. Today it is `fromJSON(needs.gate.outputs.runner)`, which
   would fail to parse an empty output. It becomes
   `${{ needs.gate.result == 'success' && fromJSON(needs.gate.outputs.runner) || 'ubuntu-latest' }}`.
   The `concurrency` group already falls back to `install-noop-<ref>` when
   `relevant` is not `'true'`, so a failed gate never holds an install slot.
   The four `build.yml` jobs already run on `ubuntu-latest`.

4. **The coverage guard** (`build.yml`, `allowed_ifs`) gains exactly two
   lines: `${{ !cancelled() }}` and `needs.gate.result != 'success'`. The
   guard matches the literal text after `if:`, so the job-level form is
   written as `if: ${{ !cancelled() }}`, which YAML requires for a leading
   `!`. The allowlist line is written to match it.

5. **Comments.** `install-check.yml:162` and `:304`, and `build.yml:245`
   and `:1213`, which repeat the claim, are corrected. Each says a skipped
   required check *passes* (measured on #1144) and points at this design.
   The comments keep their real lesson: #187's path-filter problem was right.
   An absent check still blocks forever.

## Alternatives rejected

- **Leave it.** The probe shows a broken gate lets a PR merge untested.
- **`always()` instead of `!cancelled()`.** It starts jobs in a run a
  person cancelled.
- **A separate "aggregator" required job** that fails on any skipped
  dependency. That means a ruleset change (§11) plus a new required
  context, which is more moving parts for the same property.
- **Fix `install` only.** Three required `build.yml` checks would keep the
  identical hole.

## Risks

- **A required job now runs, and fails, on a gate failure.** That is the
  point. The failure message names the gate, not the job's own work.
- **The `!cancelled()` job would also run if an upstream `needs` were
  skipped for another reason.** `gate` has no `if:` and no `needs`, so it is
  never skipped. Step 1 treats `skipped` as not-success, so it fails loud
  either way.
- **The coverage guard learns two conditions.** Both are reviewed here, next
  to the reasoning, which is what the guard asks for.
- **This is a CI-gate change (§11).** I open the PR; you merge it.

## Verification

1. **Fails on a broken gate (§1).** A second throwaway probe PR, approved
   alongside this spec, applies the change *plus* `exit 1` in both gates.
   - Expected: `install`, `devenv-presets`, `system` and `box` conclude
     `failure`, not `skipped`, with the #1134 message, and
     `mergeStateStatus` is `BLOCKED`.
   - The PR is closed unmerged and the branch deleted.
2. **No change when the gate passes.** The real PR's own run:
   - `install` builds and passes, being install-relevant (it touches
     `install-check.yml`).
   - The `build.yml` jobs behave as on main.
   - The coverage guard passes.
3. **Static:** `actionlint` on both workflows reports no new findings
   (cheap tier).
4. **The probe's failing output, and #1144's `UNSTABLE`, go in the PR.**
