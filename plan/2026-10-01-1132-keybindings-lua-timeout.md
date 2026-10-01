---
status: draft
issue: 1132
spec: spec/2026-10-01-1132-keybindings-lua-timeout.md
---

# Plan: Bound the keybindings menu's Lua scan

The pinned Omarchy 4.0.4 keybindings command runs the user's
`~/.config/hypr/hyprland.lua` through a stub API in a process substitution.
An endless user loop leaves Lua consuming CPU and can stall each menu open.
Patch the one `lua <<'LUA'` invocation to `timeout 3 lua <<'LUA'` in the
copied upstream script. Timeout closes the pipe; existing Hyprland and static
bindings continue, as does the current no-Lua path. This repository does not
post the patch upstream or change a user's config. `coreutils` is **already**
in `pkgs/omarchy/default.nix`'s runtime dependencies and installed through
`modules/nixos.nix`; the issue's missing-dependency claim was false. Omarchy's
bins are symlinks, not `writeShellApplication`, so the check must invoke
ShellCheck explicitly.

## Steps

1. `tests/keybindings-lua-timeout.nix` (new) and `flake.nix:1759-1911`:
   register a cheap uniform check using `pkgs.omarchy` (the **built** package).
   Give `omarchy-menu-keybindings --print` a temporary HOME, a looping
   `hyprland.lua` (`while true do end`), real Lua, and minimal `hyprctl` and
   `xkbcli` stubs. A Lua wrapper records its PID before `exec` of real Lua.
   Bound the menu with an outer watchdog (longer than three seconds), assert
   it returns promptly, still prints a static binding, and leaves no recorded
   Lua PID alive. Add a normal terminating Lua config that produces a
   Lua-derived binding, and a missing-Lua case. The fixture's EXIT trap kills
   **only** its recorded PID on failure; never `pkill` by name. Run ShellCheck
   explicitly on the built script -> verify by `git add` of the new check,
   `nix eval .#checks.x86_64-linux --apply builtins.attrNames` containing
   `keybindings-lua-timeout`, then a **red** locked
   `nix build .#checks.x86_64-linux.keybindings-lua-timeout --no-link
   --print-build-logs` against the unpatched package. The red must name the
   outer timeout of the looping scan, not a missing tool or broken stub.
   Capture the output outside the worktree. Traps: the check depends on the
   built Omarchy package, so apply the CI-idle/host-load gate below; a flake
   ignores untracked new files; preserve the build's exit status, never pipe
   it through `tail`.

2. `pkgs/omarchy/default.nix:410-435` and `data/bin-ledger.nix`: add one
   `substituteInPlace --replace-fail` that changes exactly the vendored
   keybindings script's `lua <<'LUA'` to `timeout 3 lua <<'LUA'`. In the
   **same commit**, add its `patch` ledger row explaining the bound, because
   the script now differs from upstream. Do not add `coreutils` twice ->
   verify by `nix fmt`, `git diff --stat`, a green locked
   `nix build .#checks.x86_64-linux.keybindings-lua-timeout --no-link
   --print-build-logs`, and green `checks.bin-ledger`. The check's normal Lua
   case must still print its supplemental binding, the looping case must
   return with static bindings, and its recorded Lua PID must be gone.
   Traps: `default.nix` has one long indented `installPhase`; keep the patch
   short and anchored, and inspect the format diff for unrelated reflow.

3. `pkgs/omarchy/default.nix`: prove the finished check can fail after the
   fix. `cp pkgs/omarchy/default.nix
   /mnt/data/vmtest/1132-omarchy-default.good`; temporarily remove only
   the keybindings timeout substitution, inspect `git diff` to prove the
   break landed, and rerun `checks.keybindings-lua-timeout` **red** under the
   shared lock. Its failure must be the bounded watchdog/PID case. Restore
   with `cp /mnt/data/vmtest/1132-omarchy-default.good
   pkgs/omarchy/default.nix`, run `nix fmt`, inspect `git diff --stat`, and
   rerun the check **green**. Never use `git checkout` for a break proof;
   never leave the broken file in a commit. The two distinct Omarchy outputs
   should be cached from Steps 1 and 2, so this is a check run, not a new
   source variation. Keep red and green logs outside the repo.

4. `flake.nix`, `tests/keybindings-lua-timeout.nix`,
   `pkgs/omarchy/default.nix`, and `data/bin-ledger.nix`: verify registration,
   patch, runtime dependency and ledger stay consistent -> verify by
   `nix fmt -- --ci`, `nix run nixpkgs#statix -- check .`,
   `nix run nixpkgs#deadnix -- --fail .`, `git diff --check`, and scans for
   `| grep -q` and writes to `omarchy/shell.json` in the diff. No VM test is
   needed. Put the Step 1/3 red lines and Step 2/3 green lines in the PR body.
   Traps: no workflow edit; do not commit generated logs.

## Tests

- Before each Omarchy package build, require
  `gh run list --limit 8 --json status -q '[.[]|select(.status!="completed")]|length'`
  to print 0, no p620 system build (`pgrep -af
  'nixosConfigurations.p620|nh os build'` filtered to real build commands),
  and one-minute load below 12. Run one Nix build at a time under
  `flock /mnt/data/vmtest/codex-build.lock`.
- The registered built-package check is red against the unbounded producer,
  green with the three-second bound, red with a copy-aside removal, and green
  after restoration. The harness must not leave a spinning Lua process after
  either red. `checks.bin-ledger` is green with its new patch row.
- Stage new files before flake evaluation/build; run `nix fmt` after each
  `.nix` edit and inspect `git diff --stat`. Require the static gates in Step
  4. No local VM run.

## Rollback

Revert the implementation commits for the Omarchy substitution, its ledger
row, the registered check and its fixture. That restores upstream's unbounded
scan, so only use it if the bound proves incompatible and a measured
replacement is ready. The change writes no user configuration. Delete the
copy-aside file after the red output is in the PR.
