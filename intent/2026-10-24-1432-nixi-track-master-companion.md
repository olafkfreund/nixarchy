---
status: draft
issue: 1432
author: olafkfreund
---

# Intent: Track nixi master and ship the snowflake companion

## Problem

nixarchy's `nixi` input is pinned to a commit in the URL
(`github:olafkfreund/nixi-nixarchy/<rev>`). Because of that, `nix flake update` can't
move it. Only a hand edit of `flake.nix` can. The pin is at `5ae2ca4` (2026-10-20).
Everything merged in nixi since then hasn't reached any machine, p620 included:

- #98 (#96): Guide refuses secret reads through the shell.
- #99 (#94): the `services.nixi.companion` option.
- #100 (#95): voice session control.
- #101 (#97): Codex Guide secret reads.
- #104 (#102): opencode cancelled reads and the stall guard.
- #105 (#103): the settings write race.
- #107 (#106): YOLO during a switch to Guide.

The snowflake companion (`olafkfreund/nixoarchy-snowflake`, package `nixi-companion`) isn't
a flake input in nixarchy or in the user's config. nixi's `services.nixi.companion.package`
defaults to `null`, so the companion can't be turned on anywhere today.

## Proposed outcome

- nixarchy's `nixi` input follows nixi's `master` branch. Running `nix flake update` (or
  `nix flake update nixarchy` in a config that uses nixarchy) brings in nixi's latest master.
  The lock still records the exact commit, so builds stay reproducible between updates.
- The companion ships with nixarchy:
  - a nixarchy user can turn it on without adding a flake input of their own;
  - it stays off by default.
- On p620, after a rebuild:
  - the companion is enabled and configured, starting from a key binding and driving the agent only through nixi's bridge;
  - nixi is at current master (`39af9e3` or later).

## Affected users and systems

- **nixarchy:**
  - `flake.nix`: the `nixi` input, a new companion input, and the comments explaining both;
  - `flake.lock`;
  - wherever nixarchy sets `services.nixi.*` (`modules/home.nix`);
  - the docs.
- **The user's config (`~/.config/nixos`):**
  - p620's `hosts/p620/nixos/nixarchy.nix`;
  - `flake.lock`.
- **Every nixarchy user:** the next update brings the nixi changes above. The companion adds
  nothing to the closure unless it is enabled.

## Constraints

- **This reverses a decision documented in `flake.nix`** ("Pinned to a COMMIT … never track a
  branch"). The user decided to track the branch. The comment must be rewritten to say so and
  why, not left contradicting the code.
- The companion talks to the agent only through nixi's bridge (nixi #94). Nothing may start
  `claude -p` or bypass Guide/Mechanic.
- Keep `inputs.nixpkgs.follows` for nixi, and add it for the companion, so the closure
  doesn't gain a second nixpkgs.
- nixarchy's CI must stay green: `nix flake check` and the VM eval at `flake.nix` ~2653.
- Don't rebuild p620 without the user's go-ahead.

## Open questions

1. **Should the companion track a branch too?** The fork has no CI, so tracking `main` means any
   push lands on the next update untested. The alternative is a pinned commit. Recommendation:
   track `main`, like nixi, since both have the same maintainer and it matches your "update
   brings the latest" goal.
2. **Where does the companion package come from?** Options:
   - (a) nixarchy adds the fork as an input and defaults `services.nixi.companion.package`, so
     users only set `enable`;
   - (b) only p620's config adds the input.
   Recommendation: (a), since you asked for it to be "part of" nixarchy.
3. **On p620, which keys should start `nixi-companion` and `nixi-companion listen`?** Or does it
   autostart with the session?
