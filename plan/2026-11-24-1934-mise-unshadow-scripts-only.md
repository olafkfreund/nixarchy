---
status: draft
issue: 1934
spec: spec/2026-11-24-1934-mise-unshadow-scripts-only.md
reviewers:
  - codex # a second read of a two-line shell change and its fixture
---

# Plan: omarchy-mise-unshadow reads only scripts

Approved decisions: grep for `mise` only in files whose first two bytes are
`#!`; `is_generated` is unchanged; a no-shebang fixture containing `mise use`
must not appear in the notice.

## Steps

1. `tests/mise-launchers.nix`, beside the `personal`/`activation` fixtures: add
   `$bin/compiled`, a file with no shebang containing `mise use`, and assert the
   notice does not name it → `nix build .#checks.x86_64-linux.mise-launchers`
   fails (§1 proof). Traps: a `''` string, so no heredoc (§5).
2. `pkgs/omarchy/nix-bin/omarchy-mise-unshadow`, the `elif grep` branch: read
   two bytes with `read -r -n2` and require `#!` before grepping → the same
   check passes.

## Tests

`checks.mise-launchers` red then green; every generated check; `nix fmt -- --ci`.

## Rollback

Revert the commit.
