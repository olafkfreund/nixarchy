---
status: approved
issue: 1097
author: olafkfreund
---

# Intent: Make CI coverage and runner trust match their claims

## Problem

All four findings in #1097 still hold on `origin/main`:

- `build.yml` gets `nightly_only` from `.github/scripts/generated-checks.sh`, then overwrites it with a second literal list. The guard can drift from the list the nightly uses.
- The coverage guard finds claimed checks by searching workflow text, including comments. It recognises a `pull_request` trigger but does not reject `paths:` filters, so a named check can appear covered without running on every pull request. Its condition scan also matches `if:` in comments.
- `omarchy.yml` pipes `check-menu-mapping.py` through `tee` without `pipefail`. Since the step also has `continue-on-error: true`, a Python crash can leave a successful step and a misleading bump decision list. The regular PR mapping check in `build.yml` remains fatal.
- `install-check.yml` chooses the self-hosted runner whenever an install-relevant change is found, including a fork pull request. There is no same-repository check in that workflow. Repository Actions settings approve first time fork contributors only; later fork contributions need no approval. `build.yml`, `install-check.yml`, and `nightly.yml` have no top-level token permissions declaration. `build.yml` itself currently uses hosted runners; the fork exposure is the install job.

The issue also reports `release.yml` interpolating the dispatch `inputs.tag` directly into two shell scripts. The owner includes this fifth release-security finding in scope.

## Proposed outcome

The coverage guard has one nightly-only source and cannot report coverage from comments, filtered pull-request triggers, or unreviewed skip conditions. A mapping-script crash appears as a failed advisory step rather than a clean mapping result. Fork code cannot execute on a self-hosted runner; a fork install check reports clearly that it was not run and blocks merge until a trusted path runs it. Workflow token scopes are explicit and as narrow as each job needs.

## Affected users and systems

Contributors and reviewers rely on the `build` coverage check and required `install` check. The Omarchy bump workflow creates decision lists for release adoption. The self-hosted KVM runner pool is on p620. Nightly and release jobs also use that pool, but do not accept `pull_request` events.

## Constraints

- This is a CI-gate change under root `AGENTS.md` §11. The owner applies the eventual patch: after approved intent and spec, the plan must deliver a ready-to-apply branch for owner review and merge, stating each gate it changes. No workflow implementation before plan approval.
- Preserve the required `install` check's fail-closed behavior. A fork restriction must not turn an untested install into a green required check.
- Preserve the deliberate nightly-only exemptions and the advisory mapping check on an upstream bump; the normal pull-request mapping check remains fatal.
- Prove every changed guard red against a representative break and green after restoration, as root `AGENTS.md` §1 requires. Do not run builds, push, or open a PR during the intent stage.
- Gates in scope for the future plan: `build.yml` check-coverage and conditional-skip guard; `install-check.yml` runner selection and required install result; `omarchy.yml` bump mapping advisory result; workflow token permissions in `build.yml`, `install-check.yml`, and `nightly.yml`; `release.yml` tag validation and publication.

## Open questions

The owner approved these answers; none remain for the intent gate:

- **Fork policy:** fail the required install check on hosted infrastructure before any self-hosted job starts. A maintainer tests install-relevant fork code from a trusted same-repository branch before merge. Requiring approval for all outside collaborators in repository Actions settings is complementary, not a replacement for the workflow guard.
- **Coverage guard:** retain the small shell guard, match only non-comment lines, reject `paths:`-filtered pull-request triggers, and keep the matcher floor.
- **Token scopes:** declare minimal explicit permissions. Build and install need read access; nightly build jobs get no write permission and the reporter gets its required issue-write permission. Verify exact job needs in the spec.
- **Fifth finding:** include the `release.yml` dispatch tag injection. Pass the tag through `env:` and validate it before release actions.
