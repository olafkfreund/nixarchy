---
status: approved
issue: 1549
spec: spec/2026-11-02-1549-microvm-tmpfiles-order.md
---

# Plan: a declarative sandbox's directories get the modes nixarchy declares

## Approved decisions

- **The cause.** Upstream microvm.nix `c60daaef` (pulled in by #1547)
  writes `/var/lib/microvms/<vm>/share` at `:0775` into
  `10-microvm.conf`. When two tmpfiles.d files name the same path, the one
  that sorts first wins, so upstream beats our
  `10-nixarchy-microvm.conf`. Upstream's `<vm>` entry at `0775` has always
  beaten ours too.
- **The fix.** Rename our settings key to `09-nixarchy-microvm`, so all
  three entries win: `<vm>` at `0750`, `share/` at `0770` and `policy/` at
  `0750`. Owner-approved: all three, not only `share/`.
- **Tests.** `checks.microvm-boot` asserts all three modes. A new
  evaluation-only `checks.microvm-tmpfiles-order` fails if any earlier
  tmpfiles settings key declares one of our paths. It runs on PRs through
  the "Build every check no other job claims" step, with no workflow edit.
- **The lesson** goes in `modules/AGENTS.md`.
- **Rejected:** moving only `share/`; an absolute share source; `mkForce`;
  patching upstream.

## Steps

1. **`tests/microvm-tmpfiles-order.nix` (new) and `flake.nix` (the checks
   attrset, beside `graphics-mesa-clash` ~line 2707).**
   - Takes `{ pkgs, reference }`.
   - Builds `host = reference.extendModules { modules = [ { programs.nixarchy.services.microvm = { enable = true; user = null; machines.sandbox.template = "shell"; }; } ]; }`.
   - Reads `host.config.systemd.tmpfiles.settings`. For each path under the
     key matching `*-nixarchy-microvm`, it collects every other key that
     sorts lexically before ours and declares the same path.
   - Non-empty result: `throw` naming the key and path. Otherwise a
     `runCommand` that touches `$out`.
   - Register it as `microvm-tmpfiles-order = import ./tests/microvm-tmpfiles-order.nix { pkgs = pkgsFor.${system}; reference = self.nixosConfigurations.reference; };`.
   - Verify: `git add` the new file (§5), then run it at the CURRENT key
     `10-…`. It must fail and name `/var/lib/microvms/sandbox`, `/share`
     and `/policy`. Capture that output for the PR (§1).
   - Traps: an eval check in a worktree sees only tracked files (§5). Use
     `flock /mnt/data/vmtest/codex-build.lock` (§6, cheap tier). If
     `reference` does not import the microvm host module, the
     `extendModules` errors at eval; then set `microvm.host.enable` the way
     `tests/microvm-boot.nix` gets it.
2. **`modules/services/microvm.nix:225`.** Rename the key
   `"10-nixarchy-microvm"` to `"09-nixarchy-microvm"`. Add one line above
   it: `# 09: tmpfiles applies the lexically first file; upstream's 10-microvm declares these paths 0775 (#1549).`
   - Verify: the step-1 check now passes. Also grep the tree for other
     readers of the old name: `grep -rn '10-nixarchy-microvm' .`. Any hit
     is updated in this step.
   - Traps: run `nix fmt` and read `git diff --stat`, because the hook may
     reformat with nixpkgs-fmt (§5).
3. **`tests/microvm-boot.nix:137-138`.** Replace the share-only `stat`
   with one over all three paths:
   ```python
   modes = machine.succeed("stat -c '%n %U:%G %a' /var/lib/microvms/sandbox /var/lib/microvms/sandbox/share /var/lib/microvms/sandbox/policy").strip().splitlines()
   ```
   Assert it equals the expected three lines. The message keeps `#1076`
   for `share/` and names #1549.
   - Verify: `nix build` of the test driver (`…microvm-boot.driver`, cheap,
     type-checks the script). The VM run happens once CI is idle (§6
     tier 3), or by dispatching `nightly.yml`. On `main` it is already red,
     which is §1's failing half.
   - Traps: this is a Nix `''` string, so no `${` in the Python (§5).
4. **`modules/AGENTS.md`.** Append a short section, "Two tmpfiles.d files
   naming one path: the first file wins". Cover the rule, this incident,
   and that `checks.microvm-tmpfiles-order` guards it.
   - Verify: `nix fmt -- --ci`, statix, deadnix.

## Tests

- `checks.microvm-tmpfiles-order`: red at `10-`, green at `09-` (§1
  output in the PR).
- The `microvm-boot` driver builds. `checks.microvm-boot` passes on the
  branch, run locally when CI is idle or via the nightly.
- `checks.options-microvm` is still green: the key rename changes no
  option.

## Rollback

Revert the PR. Hosts go back to upstream's `0775` modes at their next
tmpfiles run.
