---
status: draft
issue: 1722
spec: spec/2026-11-09-1722-cargo-system-libs.md
coders:
  1: codex  # the carry: short Nix whose every guard (hook, pname, present, empty) changes what users build
  2: coder  # an evaluation check with fixtures, in the shape the spec's table gives
  3: codex  # a pure review row and its report call; small logic where the unreadable case matters
  4: coder  # a pkgs/AGENTS.md section: prose
reviewers:
  - codex  # line by line against this plan
  - agy    # an independent read of the diff
---

# Plan: codex and omp build under nixpkgs' system-library cargo hook

## Decisions carried from the approved intent and spec

1. **The carry is `pkgs/cargo-system-libs.nix`**, a function
   `{ lib, prev }` returning `{ packages; status; }`, exactly the code in the
   spec's §1.
   - The hook test reads `prev.path + "/pkgs/build-support/rust/hooks/cargo-setup-hook.sh"`:
     `builtins.pathExists` and `lib.hasInfix "cargoUseSystemLibs"`.
   - `needs` lists the libraries upstream added. `codex` gets `aws-lc`,
     `oniguruma`, `sqlite` and `zstd` (NixOS/nixpkgs@16b463698a); `omp` gets
     `oniguruma` and `zstd` (NixOS/nixpkgs@43c51fe5d9). Each row carries
     that commit as a comment, and the attribute set carries a one-line
     `# Why: pkgs/AGENTS.md#cargo-system-libs-1722`.
   - A library counts as present when some `buildInputs` entry has its
     `pname`.
   - When the hook is absent or nothing is missing, the result is
     `prev.${n}` itself. Otherwise it is `overrideAttrs` appending only the
     missing libraries.
   - `present` skips names the nixpkgs does not have.
   - `status` is `inactive`, `needed` or `dead`.
2. **The overlay** (`flake.nix:975`): `final: _prev: {` becomes
   `final: prev: {`, and the closing `};` of that attribute set becomes
   `} // (import ./pkgs/cargo-system-libs.nix { inherit (prev) lib; inherit prev; }).packages;`.
   Nothing else in the overlay changes.
3. **`checks.cargo-system-libs`** (`tests/cargo-system-libs.nix`), an
   evaluation check, registered in `flake.nix` beside the other script
   checks with a `# See tests/cargo-system-libs.nix.` line.
   - Fixtures in `tests/cargo-system-libs/`:
     - `with-hook/pkgs/build-support/rust/hooks/cargo-setup-hook.sh`, whose
       text includes `cargoUseSystemLibs() {` and
       `preConfigureHooks+=(cargoUseSystemLibs)`;
     - `without-hook/pkgs/build-support/rust/hooks/cargo-setup-hook.sh`, a
       hook without that name;
     - `no-hook/` with only a `.keep` file.
   - Stand-ins are `pkgs.stdenvNoCC.mkDerivation { pname; version = "0";
     buildInputs; dontUnpack = true; installPhase = "touch $out"; }`, so
     `overrideAttrs` exists. Each library stand-in has its real `pname`
     (`aws-lc`, `oniguruma`, `sqlite`, `zstd`).
   - Cases A to F exactly as in the spec's table:
     - "Same `drvPath`" is `packages.X.drvPath == prev.X.drvPath`.
     - "Adds exactly" compares the sorted `pname`s of the overridden
       `buildInputs` with the stand-in's own plus the missing ones.
     - Case E's omp holds a stand-in with `pname = "zstd"` that is a
       different derivation from `prev.zstd` (another `version`).
   - The assertions are forced. The `runCommand`'s env carries
     `ok = builtins.deepSeq results "yes"`, so an assertion that fails stops
     evaluation of the check, with `lib.assertMsg`'s message naming the
     case.
4. **The review row** (`pkgs/review.sh`).
   - A pure function beside `blocked_row` (`:281-296`):

     ```bash
     # One cargo carry's row, from its status in pkgs/cargo-system-libs.nix. Pure.
     carry_row() {
       case "$2" in
         needed) ok "cargo carry: $1" "$2" "still needed" ;;
         inactive) ok "cargo carry: $1" "$2" "hook absent" ;;
         dead) finding "cargo carry: $1" "$2" "-" "nixpkgs carries the fix -- drop $1 from pkgs/cargo-system-libs.nix" ;;
         *) finding "cargo carry: $1" "${2:--}" "-" "carry status unread" ;;
       esac
     }
     ```

     `ok` takes three arguments and `finding` four (`:159-165`).
   - A `--carry-row) mode=carryrow ;;` line in the option `case` (`:39-45`),
     added to the usage text. Then
     `if [ "$mode" = carryrow ]; then carry_row "$2" "$3"; printf '%s' "$rows"; exit 0; fi`
     beside the `blockedrow` block (`:309-313`).
   - In the report, directly after the quickshell-override row (`:488-502`):

     ```bash
     # Why: pkgs/AGENTS.md#cargo-system-libs-1722
     carry=$(nix eval --impure --json --expr "let p = (builtins.getFlake \"git+file://$PWD\").inputs.nixpkgs.legacyPackages.x86_64-linux; in (import $PWD/pkgs/cargo-system-libs.nix { inherit (p) lib; prev = p; }).status" 2>/dev/null) || carry=""
     for n in codex omp; do
       st=$(jq -r --arg n "$n" '.[$n] // ""' <<<"$carry" 2>/dev/null) || st=""
       carry_row "$n" "$st"
     done
     ```

     - It reads nixarchy's pinned nixpkgs (the root `nixpkgs` input), never
       the registry.
     - The names are looped in bash, so a failed evaluation still gives each
       package a "carry status unread" finding (the #690 trap at
       `:168-170`).
     - `jq` and `nix` are already in the review package's `runtimeInputs`
       (`flake.nix:1454-1464`).
   - In `tests/review-pins.nix`, after the `blockedrow` cases (`:367`), a
     `carryrow` helper of the same shape, with five cases:

     | status | expected row |
     |---|---|
     | `needed` | `\| cargo carry: codex \| needed \| still needed \| ok \|` |
     | `inactive` | `\| cargo carry: codex \| inactive \| hook absent \| ok \|` |
     | `dead` | `\| cargo carry: codex \| dead \| - \| **nixpkgs carries the fix -- drop codex from pkgs/cargo-system-libs.nix** \|` |
     | `""` | `\| cargo carry: codex \| - \| - \| **carry status unread** \|` |
     | `garbage` | `\| cargo carry: codex \| garbage \| - \| **carry status unread** \|` |

5. **`pkgs/AGENTS.md`**, a section `<a id="cargo-system-libs-1722"></a>`
   headed `## Rust packages under nixpkgs' system-library hook (#1722)`, in
   6-10 lines:
   - what the hook does, and which packages are carried, with upstream's
     commits;
   - why the carry is gated (no rebuild on a nixpkgs without the hook or
     with the fix);
   - how to add a row when another package breaks the same way;
   - how to drop one: when the review shows `dead`, delete the row, and
     delete the file and the overlay line once `needs` is empty.

## Steps

1. **`pkgs/cargo-system-libs.nix` and `flake.nix`'s overlay**: decisions 1
   and 2 (Codex).
   - Verify: `git add pkgs/cargo-system-libs.nix` (§5), then under
     `flock /mnt/data/vmtest/codex-build.lock`:
     `nix eval --raw .#nixosConfigurations.vm.pkgs.codex.drvPath` and the
     same for `omp`. Each must equal the value on `main` (the worktree at
     `/mnt/code/Source-home/nixarchy`, at `3c56f888`). Comparing across
     commits is sound here: neither derivation contains the flake source.
   - Traps: `nix fmt`, then `git diff --stat` (§5 formatter hook). Do not
     rename anything else in the overlay. `prev` is now used, so deadnix
     stays quiet.
2. **`tests/cargo-system-libs.nix`, its fixtures and its `flake.nix`
   entry**: decision 3 (coder).
   - Verify: `git add` the new files, then build
     `.#checks.x86_64-linux.cargo-system-libs` under the lock.
   - Traps: no `${` inside a `''` string except interpolation; fixture
     directories are referenced as paths (`./cargo-system-libs/with-hook`),
     so they must be tracked.
3. **`pkgs/review.sh` and `tests/review-pins.nix`**: decision 4 (Codex).
   - Verify: build `.#checks.x86_64-linux.review-pins` under the lock; and
     `bash pkgs/review.sh --carry-row codex dead` prints the finding row.
   - Traps: `checks.grep-q-pipefail` (no `| grep -q` under pipefail);
     `writeShellApplication` adds `errexit`, so the `|| carry=""` and
     `|| st=""` fallbacks must stay (`pkgs/AGENTS.md`).
4. **`pkgs/AGENTS.md`**: decision 5 (coder).
   - Verify: `grep -c '<a id="cargo-system-libs-1722">' pkgs/AGENTS.md`
     prints 1, matching the two `# Why:` pointers.
5. **Run, prove, commit, PR** (session).
   - Cheap tier: `cargo-system-libs`, `review-pins`, `grep-q-pipefail`,
     `test-registration`, `nix fmt -- --ci`, statix, deadnix.
   - §1 breaks on `checks.cargo-system-libs`, each shown failing:
     1. drop `!hasHook ||` → case C;
     2. match by derivation equality instead of `pname` → case E;
     3. append all of `libs`, not only the missing → case E;
     4. drop `present` → case F fails to evaluate.

     And on `checks.review-pins`: map `dead` to `ok` → the `dead` case.
   - **No change on `main`**: step 1's `drvPath` equality, shown in the PR.
   - **The bump builds.**
     - Make a detached worktree of `origin/update/nixpkgs-42577556388` and
       cherry-pick the branch's code commits onto it.
     - When both `vm-host-free.sh install` and `edge` print `free`, build
       `codex` and `omp` there
       (`.#nixosConfigurations.vm.pkgs.{codex,omp}`).
     - Then build `vm-toplevel` and `reference-toplevel`. Any other package
       failing with a `*-sys` crate's "not found" is added as a `needs` row
       and recorded here as a deviation.
     - Negative control: the same `codex` build in that worktree without
       the cherry-pick fails as in #1722.
   - **The review row:** `pkgs/review.sh --report` on the branch shows
     both packages `inactive` (`main`'s pin lacks the hook).
   - One commit per step. The PR says `Closes #1722`, links the three
     artifacts, and names what ran locally. Then "@codex review". Merge
     commit.
   - **After merge:** dispatch `flake update`
     (`gh workflow run flake-update.yml -R olafkfreund/nixarchy --ref main`).
     The new bump PR's `build` and `install check` are the end-to-end
     proof. Close #1721 as superseded once that PR is open.

## Tests

| check | tier | expect |
|---|---|---|
| `cargo-system-libs` | cheap (eval) | passes; breaks 1-4 fail it |
| `review-pins` | cheap | passes; `dead`→`ok` fails it |
| `drvPath` of codex and omp on `main` | eval | equal with and without the change |
| codex, omp on the bump with the carry | package | build |
| codex on the bump without the carry | package | fails (`zstd-sys`) |
| `vm-toplevel`, `reference-toplevel` on the bump | package | build |

## Rollback

Revert the PR. `main` is unchanged by it, and the bump goes back to failing
on codex and omp until the channel brings upstream's fixes.
