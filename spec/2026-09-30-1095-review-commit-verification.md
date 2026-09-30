---
status: draft
issue: 1095
intent: intent/2026-09-30-1095-review-commit-verification.md
---

# Spec: Fail closed when the review cannot read an install-check run

## Design

`pkgs/review.sh:557-575` gathers main's commits and install-check runs before
`main_install_verdict` (`pkgs/review.sh:62-100`) chooses the newest commit
that needed installation. A failed jobs request currently emits no row. Since
the commit loop continues, a later successful request can make the collector
return success and let an older commit appear verified
(`pkgs/review.sh:578-594`).

For each matching run, capture the jobs API result before printing a row.
When `gh api .../jobs` fails, discard any partial response and emit a row
for that SHA with an explicit read-error marker. Keep processing the remaining
runs for the same SHA. Make `main_install_verdict` choose a witnessed successful
install over a read error for the same SHA, and otherwise classify that SHA as
unreadable before considering any older commit. Preserve the existing
gate-success result for commits known not to affect an install. Render the
unreadable verdict in the main-install table as **could not read**, a finding
rather than a verification (`pkgs/review.sh:578-594`).

Extend the cheap fixture check in `tests/review-pins.nix:151-196` to exercise
the actual `main_install_runs` function with a stubbed `gh` command. The
fixture presents a newer commit whose jobs request fails and an older one
whose install succeeded; it must return the newer SHA as unreadable. A second
fixture presents a failed request and a successful install for the same SHA;
it must return that SHA as verified. Use the real verdict function through
the existing `--main-install-verdict` mode, so the collector and classifier
are checked together. Extract only the collector function from the script
for the stubbed call; running the full review would also query unrelated
upstream repositories.

## Alternatives rejected

- Let the jobs failure bubble up only from the pipeline. The loop can replace
  its failing status with a later successful iteration; the failed SHA also
  disappears from the classifier's input.
- Treat a failed request as an ordinary unverified install. The API has not
  established whether an install ran, so **could not read** is more accurate.
- Reject the whole SHA when one rerun is unreadable. A separate successful
  install for that SHA is sufficient evidence, as the owner decided.
- Call the live GitHub API in the check. That would be network-dependent and
  cannot reliably create a failed request on demand.

## Risks

- A transient GitHub error creates a visible finding until the next review;
  this is deliberate because verification is unknown at that moment.
- A jobs response that succeeds but lacks the expected install job is outside
  this failed-request case. The existing null-field behavior remains in place.
- The check's function extraction depends on the function's Bash boundaries.
  If the collector is moved, the check should fail visibly rather than test
  an empty stub.

## Verification

1. In `tests/review-pins.nix`, assert the two stubbed outcomes above and
   assert the collector emits an explicit read-error row for the failed
   request.
2. Break-proof with a copy of `pkgs/review.sh` saved outside the check's source
   path, then temporarily remove the jobs-error row: `checks.review-pins`
   must fail because it reaches the older verified SHA. Restore the copy and
   show the check green. Use `cp` for save and restore, never `git checkout`;
   capture the red output for the PR.
3. Run `nix fmt -- --ci`, `nix run nixpkgs#statix -- check .`, and
   `nix run nixpkgs#deadnix -- --fail .`. Build only the cheap
   `checks.x86_64-linux.review-pins` check; no VM or `checks.options` run is
   needed. The build follows the shared build lock if other agents are
   building.
