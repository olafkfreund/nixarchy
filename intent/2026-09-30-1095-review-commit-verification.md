---
status: draft
issue: 1095
author: olafkfreund
---

# Intent: Do not report an older install as verification when GitHub cannot read a newer run

## Problem

The issue's outcome claim holds. `pkgs/review.sh:559-561` checks failures when
listing main's commits and install runs, but the per-run jobs request at
`pkgs/review.sh:567-573` is piped through `sed`. If that `gh api` call fails,
the pipeline emits no row. The failed pipeline status does not stop the outer
commit loop, and a later successful iteration can make the function return
success. The affected commit then has no row
in the input to `main_install_verdict` (`pkgs/review.sh:62-100`), which can
reach an older successful install and report it as verified. The existing
fixture cases in `tests/review-pins.nix:151-196` test verdicts from complete
rows; none exercises a failed jobs request.

The issue's description is imprecise about the mechanism: the request is not
itself inside a command substitution at lines 567-573. The whole
`main_install_runs` call is captured at line 578, and a later loop iteration
can replace the failed iteration's exit status before that call reports it.

## Proposed outcome

When GitHub cannot read a jobs response for a main install-check run, the
review says that verification could not be established. It never presents an
older successful install as proof for the affected newer commit. A fixture
proves the failed-request path, with a red run against the old behavior.

## Affected users and systems

Maintainers reading `nix run .#review` or its nightly rolling issue, and the
main-install portion of `pkgs/review.sh` and its cheap fixture check.

## Constraints

- Preserve the existing distinction between a gate that judged a commit
  irrelevant and an install job that actually succeeded.
- Keep ordinary findings as report output; inability to read GitHub remains
  a visible failure or finding, not a clean verification result.
- No workflow or CI-gate edit is needed for the expected script and fixture
  change. A future need to edit `.github/workflows/` requires a human under
  root `AGENTS.md` section 11.
- No Nix builds in the intent stage. Any later check must be shown failing
  with the bug restored and passing with the fix.

## Open questions

1. On a failed per-run jobs request, should the main-install row say
   **could not read** or **unverified** for that SHA? Recommend **could not
   read**: an API failure does not tell us whether installation happened,
   and the existing row already uses that wording for list failures.
2. Should one unreadable run prevent a verdict if another run for the same
   SHA shows a successful install? Recommend allowing the successful run to
   verify that SHA; a separate failed rerun cannot undo a witnessed success.
