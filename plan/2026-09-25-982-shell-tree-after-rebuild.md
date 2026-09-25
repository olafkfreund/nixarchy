---
status: approved
issue: 982
spec: spec/2026-09-25-982-shell-tree-after-rebuild.md
---

# Plan: relaunch on the generation's tree

## The approved decisions, carried over

1. **Read the tree from `/run/current-system/etc/set-environment`**, not from
   the user manager. Measured: `sessionVariables` reach a login shell through
   that file and never reach a RUNNING user manager, so
   `systemctl --user show-environment` answers with the login-time value -- the
   same stale path Hyprland holds. p620 showed `s3jlsx59...` there against
   `rp5i87d4...` in the user manager.
2. **Only the LAUNCH changes.** The kill keeps the session value, because the
   running shell registered under the login-time path and killing by the new
   one would find nothing and leave two shells.
3. **Fall back to today's behaviour** when the generated file has no
   `OMARCHY_PATH`. Parsing it is reading a format, not an API.
4. **`--replace-fail`**, so a bump that rewords the `exec_cmd` line fails the
   build rather than silently restoring the old behaviour.

## Steps

1. **`pkgs/omarchy/default.nix`** -- `substituteInPlace` on
   `omarchy-restart-shell`'s `hyprctl dispatch` line, replacing it with a block
   that resolves the current tree and prefixes `env OMARCHY_PATH=<tree>` when it
   resolves. **Check the build phase's size first**: #948's guard was refused
   with `Argument list too long` after 48 added lines, so this one is written
   short and its effect on that budget is measured rather than assumed.
   → verify by step 3.
2. **`pkgs/AGENTS.md`** -- a line beside #963's, naming this as another patch to
   an upstream script and why it is not sent upstream (on Arch the path is
   stable, so there is no bug there).
   → verify by reading it back.
3. **`tests/shell-restart-tree.nix`** -- a `runCommand` with a fake
   `/run/current-system/etc/set-environment` and a stub `hyprctl` recording its
   argv. A PATH stub works here: the script is upstream's and unwrapped.

   | case | assert |
   |---|---|
   | generated file names a tree | the exec string carries **that** tree |
   | generated file has no OMARCHY_PATH | the exec string is unchanged from today's |

   **Section 1:** both seen failing with the `env` prefix removed.
4. **`tests/AGENTS.md`** -- the hole: that the relaunched shell actually reads
   the new tree needs a session that has rebuilt since login, which no check
   here has.

## Tests

| command | expected |
|---|---|
| `nix build .#checks.x86_64-linux.shell-restart-tree` | passes; two cases |
| `nix build .#omarchy` | builds -- and does not hit the argument limit |
| `nix build .#checks.x86_64-linux.shell-ipc-resolve` | still passes; same file, #963's patch |
| `nix fmt -- --ci`, statix, deadnix | clean |

## Rollback

`git revert`. The shipped script is upstream's again and a restart returns to
relaunching on the login-time tree. No state, no user file.
