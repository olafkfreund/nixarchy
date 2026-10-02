---
status: draft
issue: 1163
spec: spec/2026-10-02-1163-mesa-extrapackages.md
---

# Plan: nixarchy's driver Mesa never collides with a user's own Mesa

## Approved decisions (self-contained)

- **An assertion, owner's choice (a).** Fail evaluation when nixarchy's driver
  Mesa is in effect *and* `hardware.graphics.extraPackages`, or
  `extraPackages32` with `enable32Bit`, holds a *different* Mesa, matched by
  `pname`/`lib.getName == "mesa"`.
  - The message names both store paths, says why (#1158 glibc), and gives
    the two fixes: remove the user's `mesa`, or set
    `hardware.graphics.package` (or `package32`) themselves.
  - It never fires when the user listed the identical Mesa, or set the
    package themselves.
- **`checks.graphics-mesa-clash`** is evaluation-only, using five fixtures and
  a fake one-file `mesa`. It is red on `main` (the colliding fixtures show no
  assertion).
  - Building merged environments in general is #1164's job, not this one's
    (the departure the owner approved with the spec).
- **No edits to user lists, no `mkForce`, Mode A inert.**
- **Nothing on the owner's hosts:** no edits, builds or switches in
  `~/.config/nixos`.

## Repo traps

- **Work only in `/mnt/data/vmtest/wt-1163`** (branch
  `fix/1163-mesa-extrapackages`).
- **A scratch tree is `git worktree add --detach`, never `cp -a`:** a copy
  shares the index (AGENTS.md §5, from #1158).
- **After `.nix` edits:** `nix fmt`, then `git diff --stat`; then statix and
  deadnix, with their exit status.
- **Cheap tier:** evaluation checks, one at a time under
  `flock /mnt/data/vmtest/codex-build.lock`. **Nothing here builds Mesa:** the
  fake is never realised, and the real Mesa is only evaluated.
- **`--impure`:** strip `NIXPKGS_ALLOW_UNFREE` before any `--impure`
  evaluation (§1).
- **No heredoc inside Nix indented strings** (§5).

## Steps

1. **The assertion: `modules/nixos.nix`.**
   - Add two entries to the `assertions` list that opens at
     `config = lib.mkIf cfg.enable { assertions = [` (`:840-841`), one for the
     64-bit side and one for the 32-bit side.
   - Put the shared `let` (`g`, `isMesa`, `ours`, `ours32`, `clash`, `clash64`,
     `clash32`) in the file's top-level `let`, beside `hyprPkgs` (`:14`). Or
     put it in each assertion's own `let`, if that reads better and statix
     agrees.
   - The messages follow the spec's D1 wording. Interpolate:
     - `${lib.getName p}-${p.version or "?"}` and `${p}` for the user's
       entry (the first clash is enough; mention a count if there are more);
     - `${ours}` for nixarchy's;
     - `#1163`, and the `docs/internals/flake.md#hyprlands-mesa-follows-its-own-nixpkgs`
       pointer.
   - A comment of at most 3 lines: why it fires only for a *different* Mesa,
     and only while nixarchy's package is in effect.
   - **Verify (cheap):** `nix eval .#nixosConfigurations.reference.config.assertions --apply 'as: builtins.length (builtins.filter (a: !a.assertion) as)'`
     prints `0`.

2. **The check: `tests/graphics-mesa-clash.nix` (new), plus the `flake.nix`
   entry** beside `graphics-glibc` (`flake.nix:2447`).
   - **Arguments:** `{ pkgs, reference }`, where
     `reference = self.nixosConfigurations.reference`.
   - **Fixtures:** `reference.extendModules { modules = [ { … } ]; }`:
     - **A:** `hardware.graphics.extraPackages = [ fakeMesa ]` → the 64-bit
       #1163 assertion fails, and its message contains `extraPackages` and
       `hardware.graphics.package`;
     - **B:** `hardware.graphics.enable32Bit = true; extraPackages32 = [ fakeMesa32 ]`
       → the 32-bit one fails;
     - **C:** `extraPackages = [ <reference's own hardware.graphics.package> ]`
       → no #1163 failure;
     - **D:** `hardware.graphics.package = fakeMesa; extraPackages = [ fakeMesa ]`
       → none;
     - **E:** the reference as-is → none.
   - **`fakeMesa`** is
     `pkgs.runCommand "mesa-fake" { pname = "mesa"; version = "0-fake"; } "mkdir -p $out/share/glvnd/egl_vendor.d; echo '{}' > $out/share/glvnd/egl_vendor.d/50_mesa.json"`.
     `fakeMesa32` is the same with another name, so their paths differ. It is
     never built: only `outPath` is read.
   - **"#1163 assertion fails"** means a failing entry in `config.assertions`
     whose message contains `#1163`. Read `config.assertions` only, never
     `system.build.toplevel`.
   - **The build:** compute every verdict in Nix, then a `runCommand` that
     prints one line per fixture (`A: expected fail, got fail`) and exits 1 on
     any mismatch. Escape the strings with `lib.escapeShellArg`.
   - **Verify (cheap):**
     `nix build .#checks.x86_64-linux.graphics-mesa-clash --no-link -L` is
     green.
   - **§1:** in a `git worktree add --detach` scratch tree at this branch,
     remove step 1's two assertions, and build the check. It must be red with
     A and B reporting "got none". Capture the output, remove the scratch
     worktree, and prove the removal landed (`grep`) before trusting the red.

3. **The p620-shaped proof (evaluation only, in a scratch worktree).**
   - In a `git worktree add --detach` scratch tree, evaluate an `--impure`
     expression, after `env -u NIXPKGS_ALLOW_UNFREE`:
     `reference.extendModules` with
     `hardware.graphics.extraPackages = [ (import <#1154's nixpkgs c59305b> { system = "x86_64-linux"; }).mesa ]`.
     Fetch it as `builtins.fetchTree` of `github:NixOS/nixpkgs/c59305bab2…`;
     take the full rev from `git show origin/update/nixpkgs-36977907934:flake.lock`
     if the branch still exists, or else from the #1154 PR body or this plan's
     history.
   - Print the failing assertion message. It must name
     `/nix/store/v8v8s62p…-mesa-26.2.3` and nixarchy's
     `/nix/store/1vkzwrp4…-mesa-26.2.3`.
   - Evaluate only; build nothing. Remove the scratch worktree. Keep the
     output for the PR.

4. **Docs.**
   - **`docs/internals/flake.md`:** in the
     `hyprlands-mesa-follows-its-own-nixpkgs` section, one paragraph on the
     `buildEnv` collision and the `50_mesa.json` line, the assertion, and the
     two ways out.
   - **`modules/AGENTS.md`:** the `hardware.graphics` entry mentions the
     assertion and #1163.
   - **`docs/manual/`:** if a page covers graphics or GPU drivers
     (`grep -ril 'hardware.graphics\|gpu' docs/manual`), one line there.
   - **Verify:** `checks.doc-options` (cheap).

5. **The PR.**
   - Run `nix fmt -- --ci`, statix and deadnix. Check
     `git merge-base origin/main HEAD`.
   - **The body:**
     - links intent, spec and plan;
     - pastes step 2's red and green output and step 3's message;
     - uses `closes #1163`;
     - contains no skip-CI marker;
     - says which steps the coder did;
     - notes that #1164 is the general hardening.
   - **Owner's hosts:** the PR states what a config with its own `mesa` must
     do, and touches none of them.

## Tests

| step | command | expected |
|---|---|---|
| 1 | `nix eval` failing-assertion count on reference | 0 |
| 2 | `checks.graphics-mesa-clash` | green; red with step 1 removed (A and B "got none") |
| 3 | scratch `--impure` evaluation | the assertion message with the real v8v8 and 1vkz paths |
| 4 | `checks.doc-options` | green |
| 5 | CI on the PR | green, including `checks.options` and `checks.graphics-glibc` |

## Rollback

Revert the squash commit. Configurations with their own `mesa` go back to the
`buildEnv` collision.
