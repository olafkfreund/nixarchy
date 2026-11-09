---
status: draft
issue: 1722
intent: intent/2026-11-09-1722-cargo-system-libs.md
---

# Spec: codex and omp build under nixpkgs' system-library cargo hook

## Design

### 1. The carry: `pkgs/cargo-system-libs.nix`

A function `{ lib, prev }` that returns two attribute sets:

- `packages`: the overridden packages, merged into `overlays.default`;
- `status`: one word per package, read by the nightly review.

```nix
{ lib, prev }:
let
  hookFile = prev.path + "/pkgs/build-support/rust/hooks/cargo-setup-hook.sh";
  hasHook = builtins.pathExists hookFile && lib.hasInfix "cargoUseSystemLibs" (builtins.readFile hookFile);
  # The libraries upstream added; drop a row when nixpkgs carries the fix.
  needs = {
    codex = [ "aws-lc" "oniguruma" "sqlite" "zstd" ];   # NixOS/nixpkgs@16b463698a
    omp = [ "oniguruma" "zstd" ];                          # NixOS/nixpkgs@43c51fe5d9
  };
  present = lib.filterAttrs (n: _: prev ? ${n}) needs;
  missing = n: libs:
    let have = map (d: d.pname or null) (prev.${n}.buildInputs or [ ]);
    in lib.filter (l: !(lib.elem prev.${l}.pname have)) libs;
in
{
  packages = lib.mapAttrs (n: libs:
    let m = missing n libs; in
    if !hasHook || m == [ ] then prev.${n}
    else prev.${n}.overrideAttrs (old: {
      buildInputs = (old.buildInputs or [ ]) ++ map (l: prev.${l}) m;
    })) present;
  status = lib.mapAttrs (n: libs:
    if !hasHook then "inactive"
    else if missing n libs == [ ] then "dead"
    else "needed") present;
}
```

- **Which nixpkgs.** `prev.path` is the nixpkgs the overlay is applied to:
  nixarchy's pin, `nixpkgs-stable` for the stable VM, or a Mode A user's
  own. Reading its hook source is plain evaluation of a fetched tree, not
  import-from-derivation.
- **What counts as present** is matched by `pname`, not by derivation
  equality. Upstream may list `zstd` or `zstd.dev`; both have pname `zstd`.
- **Nothing to add returns `prev.${n}` itself**, with no `overrideAttrs`.
  So on `main` (no hook) and on any nixpkgs with upstream's fix, the
  derivation is the same object and its `drvPath` cannot differ.
  - The property is equal `drvPath`s. An `overrideAttrs` that appends an
    empty list would give the same `drvPath`, so the `m == [ ]` half of
    the guard only saves work. Case B tests the property, not that half
    (agy review).
- **Only what is missing is added**, so a partial upstream fix (one library
  added, another not) still builds, with no duplicate inputs.
- **`present`** skips a package the nixpkgs does not have (an older
  `nixpkgs-stable`), rather than failing to evaluate.

### 2. The overlay

`flake.nix:975`: `overlays.default = final: _prev: { … }` becomes
`final: prev: { … } // (import ./pkgs/cargo-system-libs.nix { inherit (prev) lib; inherit prev; }).packages`.

- Built on `prev`, so a user overlay applied after nixarchy's still
  overrides codex or omp on top (Mode A, CLAUDE.md §14).
- Everything that takes `codex` through `callPackage` (codex-acp, nixi, the
  agent lists) gets the carried one through `final`.

### 3. Telling us it is dead: a nightly review row

`pkgs/review.sh`, beside the quickshell-override row (`:488-502`), which is
the precedent: a carried override that nothing checked "would have outlived
its reason silently".

- It evaluates `status` against **nixarchy's own pinned nixpkgs**: the
  flake's root `nixpkgs` input, through `nix eval --impure --json --expr`,
  with `prev` set to
  `(builtins.getFlake "git+file://$PWD").inputs.nixpkgs.legacyPackages.x86_64-linux`.
  - The package set, not the flake. Given the flake, `prev ? codex` is
    false, and the result is `{}` with exit 0 (agy review).
  - The shell loops over the expected names (`codex omp`) and reads each
    one's status from the JSON. A missing name or a failed evaluation then
    still produces a row for each, never zero rows (the #690 trap at
    `pkgs/review.sh:168-170`). That is the
  nixpkgs the carry is applied to on `main`. The registry's nixpkgs can be
  newer, and would report a carry dead while nixarchy's pin still needs it
  (Codex review).
- The row itself is a pure function, `carry_row NAME STATUS`, with a
  `--carry-row` mode. This is the shape `blocked_row` and `--blocked-row`
  already have (`:281-296`, `:44`), which `tests/review-pins.nix:354`
  exercises. Per package:
  - `needed` → `ok`, "still needed";
  - `inactive` → `ok`, "hook absent";
  - `dead` → `finding`, "nixpkgs carries the fix -- drop <name> from
    pkgs/cargo-system-libs.nix";
  - anything else, including an empty answer from a failed evaluation →
    `finding`, "carry status unread". A query that breaks must not leave
    the carry in place silently (Codex review). That differs from the
    quickshell row, which reads unreadable as `ok`.
- A finding is a row in the review issue, never a red check. The bump is a
  bot's PR and cannot delete the carry, so a failing check would stall
  nixpkgs, exactly as this issue does.

### 4. A check that can fail: `checks.cargo-system-libs`

`tests/cargo-system-libs.nix`, an evaluation check. It calls the file with
fixture `prev` sets and asserts with `lib.assertMsg`; the derivation it
builds is trivial.

Fixtures (`tests/cargo-system-libs/`):

- `with-hook/pkgs/build-support/rust/hooks/cargo-setup-hook.sh` holds a
  line naming `cargoUseSystemLibs`;
- `without-hook/…/cargo-setup-hook.sh` exists without it;
- stand-in packages are `stdenvNoCC.mkDerivation`s, so `overrideAttrs`
  exists. Each library has a `pname`.

| case | `prev` | expect |
|---|---|---|
| A | with hook; codex lacks all four | override adds exactly `aws-lc oniguruma sqlite zstd`; `status.codex == "needed"` |
| B | with hook; codex has all four | `packages.codex` is `prev.codex` (same `drvPath`); `"dead"` |
| C | without hook; codex lacks all | same `drvPath` as `prev.codex`; `"inactive"` |
| D | no hook file at all | same as C (`pathExists` false) |
| E | with hook; omp has `zstd.dev`-style pname `zstd` only | adds only `oniguruma` |
| F | with hook; no `omp` in `prev` | `packages ? omp` is false |

## Alternatives rejected

- **`dontCargoUseSystemLibs = true`.** It vendors libraries upstream now
  links from the system, which upstream's fix does not do.
- **Waiting for the channel.** The owner wants the bump working now, and no
  one can say when `nixos-unstable` advances.
- **Pinning codex and omp from a newer nixpkgs.** It adds a second nixpkgs
  instance to the closure (buildEnv refuses two builds of one version, as
  `flake.nix`'s doctor note says), and drags in that nixpkgs' Rust.
- **Committing the fix to the bump branch.** The branch is regenerated each
  night from `main`, so the fix has to be on `main`.
- **A retirement check in `checks.*`** that fails once a carry is dead. The
  bump that brings upstream's fix would go red until a human deletes the
  row (the intent's constraint).

## Risks

- **Another Rust package in the closure breaks the same way.** The failed
  runs show only codex and omp, but they may have stopped short. The
  verification builds the bump's closures with the carry. Any other failure
  of this kind gets a row here, recorded as a plan deviation.
- **A nixpkgs that renames `aws-lc` or `oniguruma`.** `prev.${l}` then fails
  to evaluate, loudly, in the bump. The fix is a row edit.
- **Mode A on an unusual nixpkgs** (no `path` attribute). `prev.path` exists
  on every nixpkgs instance. If it ever did not, evaluation would fail
  loudly, not silently change a package.
- **The review row's `getFlake "nixpkgs"`** is the registry's nixpkgs, the
  same source the quickshell row already trusts.

## Verification

1. **`checks.cargo-system-libs`** passes. §1 breaks, each shown failing:
   1. drop the `!hasHook ||` guard → case C fails (an override without the
      hook);
   2. match by derivation equality instead of `pname` → case E fails;
   3. add all of `libs`, not only the missing → case E fails (duplicate
      zstd);
   4. drop `present` → case F fails to evaluate.
2. **No change on `main`.** `nix eval --raw .#nixosConfigurations.vm.pkgs.codex.drvPath`
   (and `omp`) are equal with and without the overlay line, both evaluated
   in the same tree (§5: compare in one tree, not across commits).
3. **The bump builds.** Make a worktree of the bump branch
   (`update/nixpkgs-42577556388`) and cherry-pick the change onto it. With
   the package-tier gate free, build `codex` and `omp` there. Without the
   cherry-pick, the same builds fail with the errors in #1722.
4. **The bump's closures.** In that worktree, build `vm-toplevel` and
   `reference-toplevel` (package tier), and the cheap tier of checks.
   Anything else that fails under the hook is added as a row.
5. **The review row.**
   - `checks.review-pins` gains `--carry-row` cases: `needed` and
     `inactive` give `ok`, while `dead`, an empty status and `garbage` each
     give a finding.
   - §1 break: map `dead` to `ok`, and the `dead` case fails.
   - Then `pkgs/review.sh --report` on the branch shows codex and omp as
     `inactive`: `main`'s pinned nixpkgs lacks the hook.
6. Cheap tier: `nix fmt -- --ci`, statix, deadnix, `checks.review-pins`,
   `test-registration`, `grep-q-pipefail`.
7. **After merge:** dispatch the `flake update` workflow so a new bump PR
   opens from the fixed `main`. Its `build` and `install check` going green
   is the end-to-end proof, and that PR closes #1721's role.
