---
status: draft
issue: 1109
intent: intent/2026-09-30-1109-config-repo-git-hint.md
---

# Spec: Print Git commands that respect repository ownership

## Design

At the closing guidance in `pkgs/omarchy/nix-bin/nixarchy-config-repo:827-836`, select the Git command prefix using the same `[ -w "$FLAKE/.git" ]` condition as `wgit` at `:87-93`. Print plain `git add`, `git commit`, and `git push` when the user can write `.git`; print the existing `sudo git` commands otherwise. Keep the three manual commands, the menu backup text, and the `--drift` behavior unchanged. This is display logic only; the script's actual Git writes already go through `wgit`.

Extend `tests/config-repo-ownership.nix:1-116`, already wired as `checks.config-repo-ownership` in `flake.nix:2294-2297`, to assert the closing hint in both cases. The writable fixture should display plain commands and no `sudo git`. For the legacy fixture, make `.git` non-writable as well as the flake directory; let its sudo stub temporarily permit writes to both so the existing setup completes, then assert the hint displays `sudo git`. Assert the commands for add/commit and push, rather than relying on a single matching word. This tests the script's output, not a duplicate of its condition.

## Alternatives rejected

- Test `$FLAKE` instead of `$FLAKE/.git`: the former may be writable while the metadata is not; it would disagree with `wgit` and suggest a command that fails.
- Replace the manual commands with `--drift`: the owner chose to preserve the manual and menu workflows.
- Add a new check: the existing ownership check already runs the same script in both relevant ownership states.

## Risks

- A legacy fixture with only the flake directory made non-writable would still take the plain Git path, so the test must vary `.git` writability too.
- The suggested manual commands do not run during the check. The check proves what the user sees, while the existing setup assertions cover the script's own Git operations.

## Verification

Run `nix build .#checks.x86_64-linux.config-repo-ownership --print-build-logs` after staging the changed files. In the writable fixture, expect a line confirming plain Git guidance; in the non-writable fixture, expect a line confirming `sudo git` guidance, alongside the existing ownership assertions.

Prove the new assertions fail: copy `pkgs/omarchy/nix-bin/nixarchy-config-repo` aside outside the worktree, temporarily restore the unconditional `sudo git` closing hint, and run the check. It must fail on the writable fixture with an explicit diagnostic. Restore the saved file with `cp` (never `git checkout`) and rerun the check to green. No VM or `checks.options` run is needed.
