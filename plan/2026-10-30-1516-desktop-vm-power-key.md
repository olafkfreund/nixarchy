---
status: approved
issue: 1516
spec: spec/2026-10-30-1516-desktop-vm-power-key.md
coders:      # the owner asked for agy and codex on these issues
  1: agy
  2: agy
reviewers:   # read-only, on top of the fresh Opus review
  - codex
---

# Plan: nixarchy-desktop powers off on `nixarchy vm stop`, and a check sees it

Approved decisions (carried from the spec):

- In `modules/microvm/templates/nixarchy-desktop.nix`, keep
  `services.logind.settings.Login.HandlePowerKey = "poweroff"` at plain
  priority. It beats `modules/nixos.nix`'s `lib.mkDefault "ignore"`. No
  `mkForce`, and no change to `modules/nixos.nix`.
- Merge the file's three top-level `services.` assignments into one
  `services = { … }`, so statix's repeated-keys lint passes. Values stay the
  same, and so do the comments.
- `checks.microvm-template` asserts that the built guest's
  `etc/systemd/logind.conf` has the exact line `HandlePowerKey=poweroff`.
  That probe reads the rendered closure and adds no NixOS evaluation. It is
  not an option assertion in `checks.microvm-ai-mirror`.

Branch `fix/1516-desktop-vm-power-key` (PR #1517). Worktree
`/mnt/data/vmtest/nixarchy-1516`.

## Steps

1. `modules/microvm/templates/nixarchy-desktop.nix:40-54`. Replace
   `services.displayManager.autoLogin = { enable = true; user = "dev"; };`
   (40-43), `services.gnome.at-spi2-core.enable = true;` (50) and the
   commented `services.logind.settings.Login.HandlePowerKey = "poweroff";`
   (52-54) with one block at line 40:
   ```nix
   services = {
     displayManager.autoLogin = {
       enable = true;
       user = "dev";
     };
     gnome.at-spi2-core.enable = true;
     # nixarchy ignores the power key so it reaches Omarchy's power menu, but the
     # only press a VM gets is 'nixarchy vm stop', which waits for a shutdown (#1516).
     logind.settings.Login.HandlePowerKey = "poweroff";
   };
   ```
   `environment.sessionVariables` (45-48) stays where it is, after the block.
   → Verify with `nix run nixpkgs#statix -- check modules/microvm/templates/nixarchy-desktop.nix`
   (no repeated-keys warning), and `nix fmt` followed by `git diff --stat`
   (one file).
   Traps: an agent hook may reformat with nixpkgs-fmt, so run `nix fmt` and
   read the diff (§5). Agy's sandbox is read-only for commands, so it edits
   with its file tools.

2. `tests/microvm-template.nix`. After the `agent-claude` block ends (the
   `''}` at line 405, before `echo "== nixarchy vm: launch and locking =="`),
   insert:
   ```nix
   ${lib.optionalString (templates ? nixarchy-desktop) ''
     echo "== nixarchy-desktop: the power key powers off =="
     # nixosModules.nixarchy sets the power key to "ignore" for Omarchy's menu;
     # in the guest the only press is 'nixarchy vm stop', which then hangs (#1516).
     sys=$(readlink -f ${templates.nixarchy-desktop.kvm}/share/microvm/system)
     if ! grep -qx 'HandlePowerKey=poweroff' "$sys/etc/systemd/logind.conf"; then
       echo "nixarchy-desktop: logind does not power off on the power key: $(grep HandlePowerKey "$sys/etc/systemd/logind.conf" || echo unset)" >&2
       fail=1
     fi
   ''}
   ```
   → Verify that `nix eval --raw .#checks.x86_64-linux.microvm-template.drvPath`
   evaluates. The build is in Tests.
   Traps: `''${` is not needed here, because `${templates…}` must
   interpolate and `$sys` and `$(…)` are already literal in a `''` string
   (§5). Write no heredoc (§5). Use `grep -qx`, not a pipe, so the status is
   grep's own (§1). Build `checks.grep-q-pipefail` before pushing.

3. Commit steps 1 and 2 together, with a full-sentence subject (§8). Push,
   and update #1517's title and body to link intent, spec and plan, with
   `closes #1516` once.

## Tests

- `nix fmt -- --ci`, `nix run nixpkgs#statix -- check .` and
  `nix run nixpkgs#deadnix -- --fail .` are clean.
  `nix build .#checks.x86_64-linux.grep-q-pipefail` passes.
- §1 break proof, only if `gh run list` shows nothing in flight and
  `vm-host-free.sh` prints `free` for both `install` and `edge`, because the
  `nixarchy-desktop` runner isn't in p620's store:
  - Delete the `logind…` line and confirm it's gone in `git diff`.
  - Evaluate the drvPath, check the break is in it, then run
    `nix build '<drv>^*' -L`. It goes red with
    `nixarchy-desktop: logind does not power off on the power key: HandlePowerKey=ignore`.
  - `git checkout HEAD -- <file>` (HEAD, not the index, §5), build again, and
    see it pass.

  If the host isn't free, #1517's CI run is the passing proof, and the PR says
  the break wasn't run locally.
- #1517's CI is green, including `lint` and the generated-checks step that
  builds `microvm-template`.
- Reviews: a fresh Opus agent gets the plan path and `git diff origin/main`,
  and codex runs `review --base origin/main` read-only.

## Rollback

Revert the squash commit. The template goes back to the hanging `stop`
(SIGTERM qemu is the workaround), and the probe goes with it.
