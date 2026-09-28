---
status: approved
issue: 1036
spec: spec/2026-09-28-1036-omatheme-default.md
---

# Plan: Keep the default omatheme integration current and verified

Nixarchy already owns the default omatheme plugin manifest and imports the
runtime module. This change refreshes the pinned dependency from `42b64ed` to
the merged omatheme revision `45b15e4389893c17d494557338addab2d15681f7`, then
verifies that the existing integration still evaluates and preserves all
default and opt-out behavior.

## Steps

1. `flake.nix`: update the pinned `nixarchy-omatheme` input to
   `45b15e4389893c17d494557338addab2d15681f7` → verify the URL is immutable.
2. `flake.lock`: refresh the lock entry using the flake tooling → verify the
   locked revision and nar hash match the requested input.
3. `tests/options.nix` or the smallest existing test location: add only the
   compatibility assertion needed to prove the consumed module and
   `omarchroma-plugin` output remain available → verify the assertion passes.
4. Run the repository checks → verify default, Mode A, Mode B, Stylix,
   non-Stylix, and opt-out fixtures remain passing.
5. Review the final diff and commit the implementation → verify no changes
   touch the user's NixOS configuration directory and the browser target is
   still opt-in.

## Tests

- `nix flake check --all-systems --no-build`
- The repository's existing option/plugin test commands, if not covered by
  the flake check.
- A focused evaluation of the NixOS module and plugin package outputs if the
  compatibility assertion requires it.

Expected result: all checks pass and the pinned default plugin exposes the
runtime features from the selected omatheme revision without enabling browser
state writes by default.

## Rollback

Revert the implementation commit, or restore the previous immutable input and
lock entry at `42b64ed98e76a8c7582b2755b304e21a50ba58b1`. Existing users can
also disable the runtime engine or default plugin using the already documented
options.
