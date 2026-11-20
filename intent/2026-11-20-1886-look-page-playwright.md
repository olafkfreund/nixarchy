---
status: draft
issue: 1886
author: x
---

# Intent: `omarchy agent look page` works without mise

## Problem

Quattro's `omarchy-agent-look-page` screenshots a page an agent built and reports
its console errors. It gets Node and Playwright from mise on first use. nixarchy
ships no mise, so on the edge channel the command always exits 1 ("Playwright
isn't installed and couldn't be"). `data/mise-allow.nix` records the gap so
`checks.mise-free` passes; nothing fixes it.

## Proposed outcome

On edge, `omarchy agent look page index.html` produces a screenshot and the
console-error report, as on Arch, with Node and Playwright from nixpkgs.

## Affected users and systems

Edge-channel users and the coding agents that use the `omarchy-make-*` skills.
Main's tag pin has no such script and is unaffected.

## Constraints

- Mode A untouched; main's closure unchanged (the patch is guarded on the
  script existing, as the other quattro-only patches are).
- No mise, no download at run time.

## Open questions

None.
