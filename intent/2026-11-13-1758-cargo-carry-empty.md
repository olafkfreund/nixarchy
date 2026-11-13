---
status: approved
issue: 1758
author: olafkfreund
---

# Intent: empty the cargo carry now nixpkgs carries both fixes

## Problem

The nightly review (#1758, 2026-11-13) reports both rows of
`pkgs/cargo-system-libs.nix` (#1722) as `dead`: nixpkgs' codex and omp now
link every system library the carry used to add. Measured here: `dead` for
both on `main`'s nixpkgs and on the open bump (#1770), `inactive` on
nixos-26.05 (no cargo hook). The review stays red until the rows go.

## Proposed outcome

The carry holds no rows, nothing nixarchy builds is overridden, and the
review shows no cargo-carry rows. The mechanism, its check and the CI job stay,
ready for the next package that breaks the same way.

## Affected users and systems

Nobody's closure changes: a `dead` row already returns `prev.<name>`.
`pkgs/cargo-system-libs.nix`, `tests/cargo-system-libs.nix`, `pkgs/review.sh`,
`pkgs/AGENTS.md`.

## Constraints

- No workflow edit: `build.yml`'s `carry` job is a required check (§11), and
  with no rows it already reports "no cargo carry is needed".
- `checks.cargo-system-libs` must keep proving the mechanism (§1), not pass
  vacuously on an empty table.
- An empty carry must not read as "carry status unread" in the review.

## Open questions

None. The owner pre-approved all changes for the open issues on 2026-11-12.
