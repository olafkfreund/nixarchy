---
status: approved
issue: 1109
author: olafkfreund
---

# Intent: Show Git commands with the right ownership

## Problem

The issue holds up. `nixarchy-config-repo` always ends by suggesting `sudo git add`, `sudo git commit`, and `sudo git push` (`pkgs/omarchy/nix-bin/nixarchy-config-repo:830-832`). On a user-owned repository, running those commands as root can leave root-owned objects or refs in `.git`, preventing later user Git writes. The same script's `wgit` helper already avoids that outcome (`:81-93`).

One detail in the issue needs precision: `wgit` checks whether `$FLAKE/.git` is writable, not merely whether `$FLAKE` is writable. That is the directory Git writes during these operations.

## Proposed outcome

After setup, the displayed manual Git commands use plain `git` when the user can write the repository metadata, and suggest `sudo git` only for a legacy repository whose metadata requires it. The menu backup path remains available.

## Affected users and systems

People who run `nixarchy config repo` on either current user-owned flake repositories or older root-owned repositories. The closing guidance is in the packaged `nixarchy-config-repo` command; it does not change Git operations performed by the command itself.

## Constraints

- Match the existing `wgit` ownership decision so the guidance agrees with the script's behavior.
- Preserve working guidance for legacy repositories and the existing menu backup option.
- Prove both writable and non-writable repository cases in a check that fails when the unconditional `sudo` hint returns.
- This round is intent only: no builds, implementation edits, PR, or push. Do not touch the criticals PR's files.

## Open questions

- **Owner answer:** use `$FLAKE/.git` writability, exactly as `wgit` does, even if `$FLAKE` itself is writable. Git updates metadata there, and the guidance must agree with the helper.
- **Owner answer:** preserve the manual Git workflow and menu text; change only the privilege prefix, without replacing the commands with `--drift` guidance.
