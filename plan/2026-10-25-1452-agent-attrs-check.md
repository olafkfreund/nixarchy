---
status: approved
issue: 1452
spec: spec/2026-10-25-1452-agent-attrs-check.md
---

# Plan: checks.agent-attrs

Approved decisions:
- Parse `attr_for()` at evaluation.
- Collect failures, and fail in a `runCommand`, never by throwing.
- Refuse fewer than 5 arms.
- `pkgs = pkgsFor.${system}`.

## Steps

1. `tests/agent-attrs.nix` (new): as the spec says. Check that it passes
   on `main`.
2. `flake.nix`, after `stale-scripts`: `agent-attrs = import
   ./tests/agent-attrs.nix { pkgs = pkgsFor.${system}; };`.
3. §1 break: `codex) echo amp`. The check fails and names codex. Restore with
   `git checkout HEAD --`.

Traps:
- §5: `git add` the new file before evaluating.
- §5: `tryEval` does not catch a missing attribute, so test with `?` first.
- §5: a heredoc in an indented Nix string reindents the file, so use printf.

## Deviations

- Step 3 found a hole in step 1's parse. Splitting on `attr_for() {` also
  matched `elsewhere_attr_for() {`, so a renamed header parsed that
  function's three arms. A removed header would have thrown at evaluation
  (`elemAt 1`). The split is now anchored to a line start and guarded, and
  both cases fail the build with `parsed 0 arms`.
- The breaks run: `codex) echo amp` fails with "codex: pkgs.amp installs
  amp, not codex". `grok-cli-nonexistent` fails with "grok: no
  pkgs.grok-cli-nonexistent". A renamed or removed header fails with
  "parsed 0 arms". Restored, it reports "9 attr_for arms resolve".

## Tests

`nix build .#checks.x86_64-linux.agent-attrs`, `nix fmt -- --ci`, statix and
deadnix.

## Rollback

Revert the commit.
