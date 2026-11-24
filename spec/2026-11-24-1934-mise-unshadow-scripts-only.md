---
status: approved
issue: 1934
intent: intent/2026-11-24-1934-mise-unshadow-scripts-only.md
---

# Spec: omarchy-mise-unshadow reads only scripts

## Design

In `pkgs/omarchy/nix-bin/omarchy-mise-unshadow`, the `elif grep ...` branch
first reads the file's first two bytes and only greps when they are `#!`.
`is_generated` is unchanged: it already stops at its 1024-byte size check.

## Alternatives rejected

- A size cap on the grep: a small compiled binary would still be read and could
  still be misreported, and any cap is arbitrary.
- `file --mime`: a new runtime dependency for a two-byte test.

## Risks

A hand-written launcher without a shebang that calls mise is no longer listed
(a shell still runs one, through its ENOEXEC fallback). Accepted: every form
Omarchy generated starts with `#!`, and the notice is advisory.

## Verification

`checks.mise-launchers` gains a fixture: a file with no shebang that contains
`mise use`, and the notice must not list it. It fails before the change (the
binary is listed) and passes after. The existing cases still pass.
