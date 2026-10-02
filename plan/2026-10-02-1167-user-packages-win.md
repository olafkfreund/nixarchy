---
status: draft
issue: 1167
spec: spec/2026-10-02-1167-user-packages-win.md
---

# Plan: a user's own package wins over the one nixarchy brings

## Approved decisions (self-contained)

- **Every package nixarchy adds to `environment.systemPackages` unasked gets
  `lib.lowPrio`** (priority 10), so a user's package at the default (5) wins
  any binary they share.
  - Shape: `map lib.lowPrio (…)` over each module's contribution, as
    `modules/home.nix:1011` does for #809.
  - Measured: it changes nothing between nixarchy and NixOS (the only overlap
    is `coreutils` (10) against `coreutils-full` (13)), and nothing among
    nixarchy's own packages (0 shared binaries).
  - nixpkgs-set priorities (`neovim`/`fastfetch` at 4, `libreoffice` at −10)
    are overwritten to 10, so the user's own copy wins: intended.
- **The user's own app picks keep normal priority** (owner's answer 2), that
  is, the packages `programs.nixarchy.apps.<name>.enable` installs.
- **`checks.user-packages-win` (new, evaluation only):** every
  nixarchy-contributed system package outside the app picks must have
  `meta.priority >= 10`. It names any offender.
- **The end-to-end proof is #1164's `checks.coexistence`
  `systempkg-own-ffmpeg`:** red on `main` (run 37074375513), and green after
  #1164 rebases on this. #1167 merges first.

## A correction to the spec (deviation, recorded)

The spec named `modules/apps.nix:1205` as "the app selection". It is not: that
block adds nixarchy's own tools (`nixarchy-doctor`, `-verify`, `-explain`) and
the default agent's package. Those are unasked, so **they get `lowPrio`**.
The app picks are elsewhere in `apps.nix`; step 1 finds them and leaves them
alone.

## Repo traps

- **Work only in `/mnt/data/vmtest/wt-1167`;** never touch `~/.config/nixos`.
- **`lowPrio` on a list:** wrap the *elements*, `map lib.lowPrio [ … ]`, never
  `lib.mkDefault` on the list (AGENTS.md §7: `mkDefault` on a merging type
  drops the whole contribution once the user adds an element).
- **`lib.optional`/`optionals` results are lists:** wrap after building them.
- **After `.nix` edits:** `nix fmt`, then `git diff --stat` (the formatter
  hook); then statix and deadnix.
- **Evaluation is cheap** (under `flock /mnt/data/vmtest/codex-build.lock`).
  `checks.options` and VM checks run in CI only (§6).

## Steps

1. **Find every unasked contribution, and the app picks.**
   - Run `grep -rn 'systemPackages' modules/`. For each hit, classify it:
     - *unasked*: nixarchy decided, e.g. `nixos.nix`'s `cfg.package` and
       `runtimeDeps` (`:1290-1296` onwards), `boxes.nix:114`, `local-ai.nix:407`
       and `apps.nix:1205`;
     - *the user's pick*: the per-app `enable` path in `apps.nix`; find where
       `programs.nixarchy.apps.<name>` packages reach `systemPackages`.
   - Write the classification into the PR body, as a table.

2. **Wrap the unasked contributions: `modules/nixos.nix`, `modules/apps.nix`
   (its tools block only), `modules/services/boxes.nix`, `modules/local-ai.nix`.**
   - Use `map lib.lowPrio (…)` around each unasked list, with one comment
     line at each site: `# lowPrio: a user's own copy wins any binary it shares (#1167, as #809).`
   - **Verify (cheap):**
     - the reference toplevel `drvPath` evaluates;
     - the spec's measurement script, re-run, shows nixarchy's entries at
       priority 10 except the app picks;
     - `coreutils` still beats `coreutils-full`: 10 against 13, unchanged.

3. **The check: `tests/user-packages-win.nix` (new), plus `flake.nix`'s entry**
   beside `graphics-glibc`.
   - **Arguments:** `{ pkgs, reference, lib }`.
   - **"nixarchy's entries"** are the outPaths in
     `reference.config.environment.systemPackages` that are absent from
     `reference.extendModules { modules = [ { programs.nixarchy.enable = lib.mkForce false; } ]; }`.
   - **"The app picks"** are the outPaths absent from a variant where every
     `programs.nixarchy.apps.*.enable` is false. Find the cleanest way to
     express "no apps", and pin it here.
   - **Offenders:** nixarchy entries that are not app picks and have
     `(p.meta.priority or 5) < 10`. The `runCommand` prints them and fails;
     otherwise it prints the count checked.
   - **Verify:** build it (cheap).
   - **§1:** in a `git worktree add --detach` scratch tree, remove the wrap
     from `boxes.nix`. It must be red, naming `distrobox`. Show `grep` that
     the removal landed, then remove the scratch tree.

4. **The PR, and #1164.**
   - Run `nix fmt -- --ci`, statix and deadnix. Check
     `git merge-base origin/main HEAD`.
   - **The PR body:**
     - links intent, spec and plan;
     - the classification table, the measurement and the check's red;
     - uses `closes #1167`;
     - says which steps the coder did.
   - **After it merges, rebase #1164** (`feat/1164-coexistence-fixtures`) onto
     `main` and push. CI's `system` job must show
     `systempkg-own-ffmpeg: ok`.
   - **Then the #1164 staged reds (its plan's step 5):**
     - a probe that drops the wrap at nixarchy's `ffmpeg` site must turn
       `systempkg-own-ffmpeg` red again;
     - the graphics probe.

     #1164 then opens its PR.

## Tests

| step | command | expected |
|---|---|---|
| 2 | evaluate the reference toplevel; re-run the priority measurement | evaluates; nixarchy's entries at 10, except the app picks |
| 3 | `checks.user-packages-win` | green; red with `boxes.nix` unwrapped, naming `distrobox` |
| 4 | CI on the #1167 PR, then #1164 rebased | green; `systempkg-own-ffmpeg: ok` |

## Rollback

Revert the squash commit. nixarchy's packages go back to beating the user's
on a tie.
