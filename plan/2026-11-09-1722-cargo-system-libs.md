---
status: approved
issue: 1722
spec: spec/2026-11-09-1722-cargo-system-libs.md
coders:
  1: codex  # the carry: short Nix whose every guard (hook, pname, present, empty) changes what users build
  2: codex  # two one-line consumer edits where plain pkgs bypasses the overlay; small and easy to get subtly wrong
  3: coder  # an evaluation check with fixtures, in the shape the spec's table gives
  4: codex  # a pure review row and its report call; small logic where the unreadable case matters
  5: coder  # a pkgs/AGENTS.md section: prose
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
   `final: prev: {`, and the closing `};` of that attribute set (`:1338`; nothing in it defines `codex` or `omp`) becomes
   `} // (import ./pkgs/cargo-system-libs.nix { inherit (prev) lib; inherit prev; }).packages;`.
   Nothing else in the overlay changes.
   - **Deviation (implementation, 2026-11-09).** Written as planned, the
     `} // …` (and any `… // {` head) makes nixfmt re-indent the whole
     overlay body: 712 lines of noise (CLAUDE.md §5). Instead, the attrset is
     renamed `overlays.nixarchy`, with its body byte-identical, and
     `overlays.default = lib.composeExtensions self.overlays.nixarchy (_final: prev: (import ./pkgs/cargo-system-libs.nix { … }).packages);`.
     - `overlays.default` means what the plan said: the overlay plus the
       carry, with the carry seeing `prev`.
     - The cost is one new flake output, `overlays.nixarchy`. Nothing
       enumerates `overlays`: a grep of `tests/`, `.github/` and
       `docs/internals/flake.md` finds no reader.
2b. **The consumers the overlay does not reach** (revision, 2026-11-09:
   Codex's read of this plan; owner: implement now, not wait).
   - **Why they are missed.** The overlay sits only in `pkgsFor`
     (`flake.nix:398`). nixarchy sets `nixpkgs.overlays` nowhere else
     (`modules/services/default.nix:45-50`), so a machine's `pkgs.codex`,
     including `nixosConfigurations.vm.pkgs.codex`, never sees decision 2.
   - **Three places install Codex from plain `pkgs`:**
     - **`modules/apps.nix`, top-level `let`.** Bind once (not per app,
       because `appModule` runs once per app):
       `carried = (import ../pkgs/cargo-system-libs.nix { inherit lib; prev = pkgs; }).packages;`.
     - **`modules/apps.nix`, the `package` option's default** (`:80-87`). Its
       last branch, `pkgs.${app.attr}` (`data/apps.nix:433` gives Codex
       `attr = "codex"`), becomes `carried.${app.attr} or pkgs.${app.attr}`.
       `defaultText` stays `pkgs.${app.attr}`: it is what a user would write,
       and the carry is the identity wherever it is not needed. Evaluating
       the carry in the docs would leak it into `checks.options` (agy). The
       option's `description` gains one clause: "with nixarchy's cargo
       carry applied while nixpkgs needs it (#1722)" (Codex).
     - **`modules/apps.nix:1673`, `defaultAgent`'s package map.**
       `inherit (pkgs) codex opencode crush;` becomes
       `inherit (pkgs) opencode crush;` plus
       `codex = carried.codex or pkgs.codex;` (Codex, agy).
     - **`modules/microvm/templates/agent-claude.nix:35`.** `pkgs.codex`
       becomes
       `(import ../../../pkgs/cargo-system-libs.nix { inherit lib; prev = pkgs; }).packages.codex or pkgs.codex`.
       `lib` is already an argument there.
   - **omp:** the only consumer is `tests/agent-no-node.nix`, through
     `pkgsFor` (the overlay). At implementation time, re-run
     `grep -rnw 'omp\|codex' modules/ data/ pkgs/ installer/ tests/ flake.nix`,
     not just `modules/ data/` (agy). Any new plain-`pkgs` site joins this
     list as a plan deviation. `modules/nixos.nix:693` is documentation.
   - **What proves it** is step 6: the packages a machine actually installs,
     not an option's value (Codex). Plus a break showing that this decision,
     not the overlay, is what fixes them (agy).
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
   - Every fixture `prev` in cases A to E holds both `codex` and `omp` and
     all four library stand-ins; only case F omits `omp`. Then each break
     fails on its named case's assertion, not on a missing attribute
     somewhere else (agy review).
   - The sorted `pname` comparison keeps duplicates
     (`lib.sort lib.lessThan (map (d: d.pname) …)`, never `lib.unique`).
     Otherwise breaks 2 and 3, which add a second `zstd`, would pass case E.
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
     `if [ "$mode" = carryrow ]; then carry_row "$2" "${3-}"; printf '%s' "$rows"; exit 0; fi`
     (`${3-}`: the wrapper sets `nounset`, and an empty status is a tested
     case)
     beside the `blockedrow` block (`:309-313`).
   - In the report, directly after the quickshell-override row (`:488-502`):

     ```bash
     # Why: pkgs/AGENTS.md#cargo-system-libs-1722
     if [ -f pkgs/cargo-system-libs.nix ]; then
     carry=$(nix eval --impure --json --expr "let p = (builtins.getFlake \"git+file://$PWD\").inputs.nixpkgs.legacyPackages.x86_64-linux; in (import $PWD/pkgs/cargo-system-libs.nix { inherit (p) lib; prev = p; }).status" 2>/dev/null) || carry=""
     for n in codex omp; do
       st=$(jq -r --arg n "$n" '.[$n] // ""' <<<"$carry" 2>/dev/null) || st=""
       carry_row "$n" "$st"
     done
     fi
     ```

     - The `if [ -f … ]` gate works as the quickshell row's `grep` gate
       does: deleting the carry file retires the row without leaving
       "status unread" findings behind (agy review). Indent the block body
       as the surrounding report code is indented.
     - The names in `for n in codex omp` are the keys of `needs`. Dropping a
       row from `needs` also drops that name here, and drops its
       `review-pins` cases if they name it (the cases use `codex` only).

     - It reads nixarchy's pinned nixpkgs (the root `nixpkgs` input), never
       the registry.
     - The names are looped in bash, so a failed evaluation still gives each
       package a "carry status unread" finding (the #690 trap at
       `:168-170`).
     - `jq` and `nix` are already in the review package's `runtimeInputs`
       (`flake.nix:1454-1464`).
   - In `tests/review-pins.nix`, after the last `blockedrow` case (`:370`) and before the `fail` gate (`:372`), a
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
   - how to drop one:
     - when the review shows `dead`, delete the row from `needs` and the
       name from `review.sh`'s `for n in …` loop;
     - once `needs` is empty, delete the file, the overlay line, decision 2b's
       three consumer edits, the `review.sh` block (its `if [ -f … ]` gate keeps a forgotten block
       silent), and `checks.cargo-system-libs` with its fixtures.

## Steps

1. **`pkgs/cargo-system-libs.nix` and `flake.nix`'s overlay**: decisions 1
   and 2 (Codex).
   - Verify: `git add pkgs/cargo-system-libs.nix` (§5), then under
     `flock /mnt/data/vmtest/codex-build.lock`, on `main`'s pin:
     - the carry's `status` reports `inactive` for both packages;
     - `packages.codex.drvPath` equals `pkgs.codex.drvPath`, and likewise for
       `omp`, through
       `nix eval --impure --expr 'let p = (builtins.getFlake "git+file://$PWD").inputs.nixpkgs.legacyPackages.x86_64-linux; c = import ./pkgs/cargo-system-libs.nix { inherit (p) lib; prev = p; }; in …'`.

     That is the carry itself, not `vm.pkgs`, which the overlay never
     reaches (Codex review).
   - Traps: `nix fmt`, then `git diff --stat` (§5 formatter hook). Do not
     rename anything else in the overlay. `prev` is now used, so deadnix
     stays quiet.
2. **The two consumers**: decision 2b (Codex).
   - Verify: under the lock, on `main`'s pin (no hook), in this one tree
     (§5), with and without the edit. These are unchanged:
     - `nixosConfigurations.vm`'s `config.programs.nixarchy` Codex app
       package drvPath;
     - its `environment.systemPackages` with `defaultAgent = "codex"`;
     - `packages.x86_64-linux.microvm-agent-claude`'s drvPath.
   - Traps: the relative import paths differ per file. `nix fmt`, then
     `git diff --stat`.
3. **`tests/cargo-system-libs.nix`, its fixtures and its `flake.nix`
   entry**: decision 3 (coder).
   - Verify: `git add` the new files, then build
     `.#checks.x86_64-linux.cargo-system-libs` under the lock.
   - Traps: no `${` inside a `''` string except interpolation; fixture
     directories are referenced as paths (`./cargo-system-libs/with-hook`),
     so they must be tracked.
4. **`pkgs/review.sh` and `tests/review-pins.nix`**: decision 4 (Codex).
   - Verify: build `.#checks.x86_64-linux.review-pins` under the lock; and
     `bash pkgs/review.sh --carry-row codex dead` prints the finding row.
   - Traps: `checks.grep-q-pipefail` (no `| grep -q` under pipefail);
     `writeShellApplication` adds `errexit`, so the `|| carry=""` and
     `|| st=""` fallbacks must stay (`pkgs/AGENTS.md`).
5. **`pkgs/AGENTS.md`**: decision 5 (coder). The section also names
   decision 2b's three consumer sites, and how each kind of removal treats
   them (agy):
   - **Removing one row** from `needs` leaves the consumers alone: the
     dropped key is absent from `.packages`, so `or pkgs.*` falls back.
   - **Full retirement** (the file deleted) must also revert the three
     consumer sites, or every machine fails to evaluate on a missing file.
   - Verify: `grep -c '<a id="cargo-system-libs-1722">' pkgs/AGENTS.md`
     prints 1, matching the two `# Why:` pointers.
6. **Run, prove, commit, PR** (session).
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
     - That bump branch was deleted after #1721 closed. Make a detached
       worktree of this branch instead, run `nix flake update nixpkgs` in
       it, and commit the lock.
     - The proof that this nixpkgs needs the carry is the carry's own
       `status`, evaluated on the locked nixpkgs: `needed` for `codex` and
       `omp`. That reads the hook and the packages' `buildInputs`
       themselves. A GitHub compare status is not proof: a diverged
       revision could carry an equivalent fix (Codex). If either reads
       `dead` or `inactive`, stop: the bump no longer needs the carry for
       that package.
     - When both `vm-host-free.sh install` and `edge` print `free`, build
       there:
       - the carried `codex` and `omp` (the `--expr` from step 1, on the
         bumped pin);
       - `checks.x86_64-linux.agent-no-node`, which builds omp through
         `pkgsFor` and its overlay.
     - Then build `vm-toplevel` and `reference-toplevel`. Any other package
       failing with a `*-sys` crate's "not found" is added as a `needs` row
       and recorded here as a deviation.
     - Then the consumers (decision 2b), on that bumped worktree. Read what
       is actually installed, not an option's value (Codex):
       - every derivation named `codex-*` in `nixosConfigurations.vm`'s
         `environment.systemPackages`, evaluated twice: with the Codex app
         enabled, and with `defaultAgent = "codex"`;
       - every `codex-*` derivation in the closure of
         `packages.x86_64-linux.microvm-agent-claude`'s drvPath
         (`nix-store -qR`).

       Each must equal the carried `codex.drvPath`, and be built.
     - **Break (agy):** revert decision 2b alone, keeping the overlay, in a
       commit in the scratch worktree. The consumer comparison must then
       fail, naming the uncarried `codex`.
     - **Negative controls:** with the carry removed (a commit in the
       scratch worktree), `codex` fails as in #1722 (`zstd-sys`), and so
       does `omp` (`oniguruma-sys` or `zstd-sys`) (agy).
   - **The review row, through the packaged binary.** `nix run
     .#review -- --carry-row codex dead` prints the finding, and
     `nix run .#review -- --report` shows both packages `inactive`
     (`main`'s pin lacks the hook). This runs `writeShellApplication`'s
     `errexit` wrapper, not just the source script (`pkgs/AGENTS.md`; Codex
     review). If the attribute is not `.#review`, the plan records the one
     that is.
   - One commit per step. The PR says `Closes #1722`, links the three
     artifacts, and names what ran locally. Then "@codex review". Merge
     commit.
   - **After merge:** dispatch `flake update`
     (`gh workflow run flake-update.yml -R olafkfreund/nixarchy --ref main`).
     The new bump PR's `build` and `install check` are the end-to-end
     proof. Close #1722 when that PR is green. (#1721 is already closed.)
     Stop the channel watcher (`brr6mbh0o`); it is no longer the path.

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
