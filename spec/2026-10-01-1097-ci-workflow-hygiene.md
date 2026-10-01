---
status: draft
issue: 1097
intent: intent/2026-10-01-1097-ci-workflow-hygiene.md
---

# Spec: Make workflow coverage and runner trust enforceable

## Design

The owner approved all five findings. Every workflow change below is a CI-gate change under root `AGENTS.md` §11. After this spec is approved, the plan will produce a ready-to-apply branch that the owner reviews and merges. It will name each changed gate and include red and green evidence. No workflow edit occurs at this stage.

### Coverage gate: `.github/workflows/build.yml`

- Remove the second `nightly_only` assignment at line 375. The call to `.github/scripts/generated-checks.sh nightly-only` at line 353 remains the single source; `nightly.yml:372-382` uses that same helper's generated target set for its proof refresh. Preserve the six deliberate nightly exemptions and the generated check floor.
- At lines 398-406, count a claimed check only when an executable workflow line names it, never a comment. Confirm the workflow has an unfiltered top-level `pull_request:` trigger; reject both `paths:` and `paths-ignore:` under that trigger. A named check in a filtered workflow must remain `ungated`.
- At lines 432-465, read only actual `if:` keys, not comments, and keep the minimum-condition count. Review the allowlist when the fork conditions below are added. This guard must still reject a new unapproved skip condition; the fork refusal is an explicit, narrow security exception.
- The `build` jobs run on hosted runners (`build.yml:76,98,237,273,1191,1263,1636`). Do not add a fork restriction to those jobs merely because the issue mentions self-hosted CI.

### Required install and runner gate: `.github/workflows/install-check.yml`

- Keep the existing `pull_request:` trigger at `:65`. The owner applies the repository Actions setting **Require approval for all outside collaborators**. [GitHub documents](https://docs.github.com/en/actions/reference/security/securely-using-pull_request_target) that `pull_request` uses fork-controlled workflow code, so a fork can edit **any** workflow to request a self-hosted runner. The repository approval setting is the security boundary; this in-workflow guard is defense in depth. Moving only `install-check.yml` to `pull_request_target` would leave every other workflow edit route open and would add privileged-checkout, concurrency and slot risks.
- The hosted `gate` job (`:106-184`) uses the **base repository's base-ref** copy of `.github/scripts/pr-touches-build.sh` for fork PRs, never the fork copy. It reads the PR's changed-file list through the API and compares `github.event.pull_request.head.repo.full_name` with `github.repository`. Keep the script's existing `pull_request` event contract. An API error or unknown relevance fails safe as relevant. The gate must remain hosted. Same-repository PRs and pushes retain the current relevance policy.
- The gate's runner output is `ubuntu-latest` for every fork. A fork with `relevant=true` gets an early hosted refusal in the required `install` job (`:186-303`), before checkout or any step that could execute PR code. Its conclusion is failure, with a clear message that a maintainer must test from a trusted same-repository branch. A fork with `relevant=false` gets the existing green `Nothing here can affect an install` no-op (`:311-315`), just like an irrelevant same-repository PR. The install, cache and proof steps must not run for either fork case. Keep `name: install`, since branch protection requires that context.
- The existing PR merge checkout, workflow concurrency and two-slot calculation remain. The fork refusal precedes the install checkout; a fork never receives a self-hosted runner output from the guarded workflow.
- Repository Actions setting `approval_policy=first_time_contributors` was read on 2026-10-01. The owner changes it to “Require approval for all outside collaborators” before relying on this patch. Workflow edits from forks can bypass an in-workflow condition, so the setting must be reviewed as part of the security outcome; it is not implemented by this branch.

### Bump mapping advisory gate: `.github/workflows/omarchy.yml`

- At lines 287-316, preserve `continue-on-error: true` for an unmapped upstream row, but set `pipefail` before `check-menu-mapping.py ... | tee /tmp/mapping.txt`. A Python error must make the mapping step's **outcome** failed (its Actions conclusion may still be success) and retain its output for diagnosis. In the downstream decision list (`:318-355`), keep the existing unmapped-row checklist when output contains `does not map`; if the step failed without that diagnostic, say the mapping check failed and require inspection instead of claiming every row is mapped. The normal PR gate at `build.yml:1012-1020` remains fatal and unchanged.

### Workflow token permissions

- `build.yml:1-76`: declare `contents: read` for checkout, `pull-requests: read` for the changed-files API, and `issues: read` for roadmap/milestone reads. It has no issue or repository write operation; cachix uses its separate secret.
- `install-check.yml:1-103`: declare `contents: read` for checkout and `pull-requests: read` for the changed-files API. Its cachix push uses `CACHIX_AUTH_TOKEN`, not a GitHub write permission.
- `nightly.yml:1-43,574-612`: declare top-level `contents: read` for checkout jobs. Keep the existing reporter job's `issues: write`; its job-level permission replaces the top-level scope and it has no checkout. No other job gets an issue-write token.

### Release tag trust gate: `.github/workflows/release.yml`

- At lines 103-106 and 183-195, pass `${{ inputs.tag || github.ref_name }}` through a step `env:` value and read it as a quoted shell variable. Validate the tag before it is used by git, written to `$GITHUB_OUTPUT`, or used for publishing: the existing release format is `v<major>.<minor>.<patch>-<revision>` (current tags follow it). A malformed or injected value fails early. The `actions/checkout` `ref:` expression at line 77 is an action input, not shell source; retain its tag-versus-ref behavior.
- Preserve the existing behind-main, vendored-version, asset and publication checks. The tag on a push and the explicit tag on manual dispatch must use the same validated value.

### Documentation

- Update `docs/internals/workflows.md` where it says the install runs on every pull request and describes its runner, to explain fork refusal and the trusted-branch path. The root and `docs/AGENTS.md` rules apply. No site navigation change is needed.

## Alternatives rejected

- A new YAML parser or rewritten coverage system: the owner chose a bounded correction to the existing shell guard. Its matcher floor and explicit trigger rejection make the narrowed text scan reviewable.
- A green hosted no-op for **install-relevant** forks: it would satisfy the required `install` context without testing an install. The owner keeps the existing no-op for irrelevant fork changes, with relevance computed by the base branch's script.
- Moving only `install-check.yml` to `pull_request_target`: a fork can edit another workflow to request the same runner. That event also introduces privileged-checkout and changed ref/slot behavior without closing the whole-repository hole.
- The current first-time-contributor approval setting: returning outside contributors can run fork-authored workflow code without fresh approval.
- Making the upstream bump mapping step fatal: ordinary unmapped rows need a decision list, while the PR mapping gate prevents merging them unmapped.
- Broad token defaults: each workflow or reporter needs only the listed read or issue-write scopes.
- Hand-maintained nightly exemptions or a second mapping checker: both recreate the drift this issue reports.

## Risks

- A fork PR that changes only irrelevant documentation gets an untested green `install` no-op, as same-repository PRs already do. If a fork exploits the base branch's denylist or file classification, the guarded workflow may produce an untested green; the owner still reviews the change. An install-relevant fork stays red until a maintainer tests it from a trusted branch.
- This workflow guard cannot guarantee that **no fork reaches p620**: `pull_request` runs fork-controlled workflow YAML, and a fork can change any workflow to request self-hosted labels. [GitHub warns](https://docs.github.com/en/actions/how-tos/manage-runners/self-hosted-runners/add-runners) that public forks can run dangerous code on self-hosted runners. The owner-applied all-outside-collaborators approval setting is the repository-wide boundary; approval itself must include review of workflow changes. The branch cannot verify or enforce that external setting.
- The existing coverage guard is text based. Shell matching of YAML indentation, multiline conditions and trigger blocks can still drift. The red proofs below must include comments, `paths:`, `paths-ignore:`, and a new skip condition; a matcher that sees no conditions must fail.
- Narrow GitHub token scopes may expose a previously implicit permission dependency. Verify issue, PR-file and milestone reads in a real Actions run after owner application; retain `issues: write` only on the nightly reporter.
- Tag format validation may reject a future prerelease naming scheme. That requires an explicit release-format decision instead of weakening shell injection protection.
- CI cannot fully emulate GitHub's runner assignment and required-check conclusion offline. A real fork run after owner application must confirm the hosted refusal and no self-hosted allocation.

## Verification

At implementation, before the owner applies the branch:

1. Run `actionlint` on every changed workflow and `git diff --check`. These check syntax and whitespace only; they do not prove GitHub scheduling or security behavior.
2. Extract or invoke the coverage guard against controlled workflow fixtures. Show a red result for a claimed check named only in a comment, one named only under `pull_request.paths` and `paths-ignore`, a comment containing `if:`, an unapproved real `if:`, and a missing condition set. Restore valid fixtures and show green. Confirm changing the single `nightly-only` list changes the build guard's answer.
3. Run the install gate logic with mock same-repository PR, install-relevant fork PR, irrelevant fork PR, push and API-failure values. Show a fork uses the base branch script, routes to hosted, fails for relevant changes before PR checkout, and succeeds as a no-op for irrelevant changes. Show same-repository relevant routing and two-slot assignment unchanged. A static workflow check must assert the `pull_request` trigger remains, the refusal precedes checkout, and the guarded workflow emits no self-hosted labels for forks. This does not prove safety against fork-authored workflow YAML.
4. Run the mapping pipeline with a Python command that exits nonzero but prints output. Capture red step outcome with output retained and a decision list that says the check failed, then green outcome and the mapped message for a successful command. A controlled `does not map` failure must still produce the row checklist. The normal PR mapping check stays fatal.
5. Use a local shell probe for a normal release tag and a hostile value containing shell syntax. Show invalid input rejected before any git or release action and ordinary push/dispatch values accepted. Do not publish a release as a test.
6. Inspect effective permission declarations, then after owner application confirm read APIs and the nightly reporter work in Actions. The owner verifies the repository approval policy is “Require approval for all outside collaborators” before approving any fork workflow run. Check a real install-relevant fork PR concludes `install` failure on a hosted runner, an irrelevant fork PR gets the hosted no-op, and a same-repository PR retains its normal required result. Record those run links for owner review. Do not treat the guard's test as proof against a fork-authored workflow change.

No Nix build, workflow run, push, PR, or implementation is part of this spec stage.
