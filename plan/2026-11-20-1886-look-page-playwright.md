---
status: approved
issue: 1886
spec: spec/2026-11-20-1886-look-page-playwright.md
coders:
  1: claude   # three substitutions and a data row; smaller than a handoff
reviewers: []  # edge carry; edge's verify and main-pin jobs are the second read
---

# Plan: `omarchy agent look page` works without mise

Decisions carried from the spec: patch only when the script exists; upstream
block kept verbatim in a file; `playwright=${playwright-driver}`, require
`"$playwright"`, `${nodejs}/bin/node`; browser from PATH; drop the
mise-allow row.

## Steps

1. `pkgs/omarchy/look-page-playwright.upstream.sh` (new), `pkgs/omarchy/default.nix`
   (args: `nodejs`, `playwright-driver`; the guarded `substituteInPlace` next to
   the `omarchy-agent-local` patch), `data/mise-allow.nix` (drop the row)
   → verify: `.#omarchy` builds; `grep -c mise` on the built script is 0;
   `checks.mise-free` passes, and fails with only the row dropped.
   Traps: `''${` inside the Nix string; `nix fmt` then read `git diff --stat`.
2. Run the built script once against a `file://` page; record the output here.

## Tests

`nix build .#checks.x86_64-linux.mise-free` (red then green), `.#omarchy`,
the generated set under both pins as the carry already does.

## Rollback

Revert the commit; the mise-allow row comes back with it.

## Record

- Step 1, §1: with only the mise-allow row dropped, `checks.mise-free` failed
  (`tree/bin/omarchy-agent-look-page:66: playwright=$(mise where playwright 2>/dev/null)`
  and four more lines). With the patch, it passes. The built script has no
  `mise` (`grep -c mise` = 0) and runs `playwright-core-1.64.1` on `nodejs-24.22.2`.
- Step 2, on p620 against a `file://` page that logs one console error:
  `screenshot: …/look-DDzvCk.png`, `console errors:` / `deliberate error`,
  exit 1 (the script's documented exit for a page with errors). The
  screenshot shows the page.
