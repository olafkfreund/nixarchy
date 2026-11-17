---
status: approved
issue: 1809
spec: spec/2026-11-16-1809-home-selection.md
coders:
  # The owner's rule: codex or agy write the code; agent-run agy cannot reach /mnt/data worktrees.
  1: codex  # template, /etc entry, seeding: small
  2: codex  # nixarchy-apply: selection, valid_user, generated function form — tricky
  3: codex  # --home in the three writers — tricky scope logic
  4: codex  # tests/home-selection.nix — script cases
  5: codex  # evaluation of the generated file with two users
  6: codex  # writer-lock rows, options-files cases, coexistence fixtures
reviewers:
  - codex  # reads the diff natively
  - agy    # independent model; given the diff inline
---

# Plan: a Home Manager selection file, and writers that can target it

## Approved decisions (from the spec)

- **Template.** `homeTemplate` is:

  ```nix
  { pkgs, pkgsOther, ... }:
  {
    home.packages = with pkgs; [  #@pkgs-begin
    ];  #@pkgs-end
  }
  ```

  The `}` is at column 0, and there is no `?` default on `pkgsOther`. It is
  exported as `/etc/nixarchy/home-template.nix` and seeded only when
  `osConfig.home-manager.useGlobalPkgs or false`.
- **`nixarchy-apply`:**
  - **Source:** the home source is `$pinned/home.nix` when pinned, else
    `$srcdir/home.nix`. Every decision tests that selected file.
  - **User:** `user=$(id -un)`, checked by `valid_user` against
    `^[a-z_][a-z0-9_-]*[$]?$`. On a mismatch it exits 1 before copying.
  - **Copying:** `home` joins the copy loop, but not `$imports`.
  - **Generated file:** with home copied, it is
    `{ config, options, lib, ... }:` plus:
    - `configuredElsewhere`, over
      `options.home-manager.users.definitionsWithLocations`, ignoring
      `__curPos.file`;
    - the home import, with the scoped `_module.args.pkgsOther` (null when
      no other channel);
    - three assertions: `useGlobalPkgs`, `isNormalUser` and
      `configuredElsewhere`.

    Without home, the file is byte-identical to today's.
- **Writers.** `--home` on `pkg-add`, `pkg-remove` and `opt-remove` sets
  `file=…/home.nix` and `scope=home`:
  - a baked `homeScope` (from `config.home-manager.useGlobalPkgs`), and
    exit 1 when it is 0;
  - a missing `home.nix`: exit 1;
  - `pkg-add --home`:
    - curated names refused as today;
    - `ensure_block` writes `home.packages`;
    - no unfree scaffold, and the system hint is printed instead;
    - no `nixarchy-search`, both with no names and with unresolved names.
  - The removers' own pickers list only `home.nix`.
- **`pkgsOther`:** only through the generated file. `apps.nix`'s config and
  `extraSpecialArgs` are untouched.

Every handoff prompt says: "Do not commit, deploy or restart, and do not
build. The lead builds. Report the changed files and any deviation."

## Steps

1. **Template, `/etc` and seeding.**
   - `modules/apps.nix`: `homeTemplate` beside `appsTemplate` (:389), and
     `environment.etc."nixarchy/home-template.nix"` beside the others
     (:1637-1640).
   - `modules/home.nix:1408`: add `home` to the seed loop when
     `osConfig.home-manager.useGlobalPkgs or false`. Build the loop's word
     list in Nix.
   - Verify: `options-files`, and an evaluation that `/etc` has the file.
2. **`nixarchy-apply`** (`modules/apps.nix`, the script from :4320):
   - **Source and user:** before the copy loop (:4670), two named functions
     that step 4 extracts:
     - `select_home_src`: prints `$pinned/home.nix` when pinned, else
       `$srcdir/home.nix` when it exists, else nothing;
     - `valid_user`.

     Every later home decision (copy, generated import, assertions) tests
     only `select_home_src`'s result. The string `$srcdir/home.nix` appears
     in the script exactly once, inside that function;
   - **Copy loop:** `apps services advanced flatsnap home`, with `home`
     skipped when building `$imports`;
   - **Generated file:** the function form when home was copied, written
     with `printf` lines (§5: no heredoc inside the Nix string), and today's
     text otherwise;
   - **Header comment:** the generated file's header lists `home.nix` among
     the user's files.
   - Verify: `apply-imports`, `apply-staging`, `apply-detach-interface`,
     `app-selection`, then step 4's cases.
   - Traps:
     - `''${` for a shell `${`;
     - the user name is written inside a Nix string literal, but only after
       `valid_user`;
     - `__curPos.file` must be the generated file's own path at evaluation.
       Step 5 checks it really excludes this file's definition.
3. **`--home` in the writers** (`modules/apps.nix`):
   - **`pkg-add`:** the flag in its `case` (:2995-3004);
   - **`pkg-remove` and `opt-remove`:** a first-argument check before their
     loops (:2632, :2828);
   - **`homeScope`:** baked into all three;
   - **`pkg-add` paths:** `ensure_block`'s target attribute
     (:3110-3117), `offer_unfree_grant` skipped with the hint (:3349-3407),
     and both `nixarchy-search` paths refused (:3055-3058, :3315-3336).
   - Verify: `writer-lock`, `app-selection`, `options-files`, then step 4.
   - Traps: #1789's lock and in-place writes stay exactly as they are; only
     `file` changes.
4. **`tests/home-selection.nix`** (new, cheap, registered in
   `uniformChecks`): the spec's cases 1-11. In particular:
   - **case 4** runs under a PTY with `script`, as
     `tests/app-selection.nix:166-184` does, with a recording
     `nixarchy-search` stub;
   - **case 5** uses scripts built with `allowUnfree = false` and no
     predicate. Build a second evaluation of the writer with that config,
     the way the options tests vary it;
   - **case 7** builds the scripts with `homeScope = 0`, through a fixture
     configuration with `useGlobalPkgs = false`;
   - **case 10** is behavioural, at the function level, plus one static
     guard. A timed race cannot fail; see
     `tests/apply-detach-interface.nix:103-118`.
     - **Function:** extract `select_home_src`. With `$pinned/home.nix`
       present and `$srcdir/home.nix` deleted, it prints the pinned path.
       With neither, it prints nothing.
     - **Static guard:** `grep -c '\$srcdir/home.nix'` on the built script
       is exactly 1. So no later decision tests the live file, which is the
       gap a function test alone cannot see.
     - **§1:** making the function prefer the live file fails the first
       part. Adding a second `[ -f "$srcdir/home.nix" ]` test elsewhere
       fails the guard. This refines the spec's case 10 (recorded as a
       deviation when committed);
   - **case 11** extracts `valid_user` from the built script.
   - Verify: the check passes, then one named break per case.
5. **Evaluation of the generated file**, revised and approved by the owner
   on 2026-11-16. The original in-sandbox evaluator could not work:
   `builtins.getFlake` writes to the store (`fchmodat2 … Operation not
   permitted`), and importing nixarchy's modules without it needs every
   flake input evaluated.
   - **One template, in Nix.** The home part of the generated file is a
     single Nix-side template, `homeAppsTemplate` in `modules/apps.nix`: a
     string with `@USER@` and `@IMPORTS@` placeholders, holding the
     function header, `configuredElsewhere`, the scoped
     `_module.args.pkgsOther` import and the three assertions.
     - It is shipped to the apply script as a file.
     - `nixarchy-apply` only substitutes the validated user and its
       `$imports` into it, with no other text assembled in shell.
     - Without `home.nix`, apply writes today's plain file, unchanged.
   - **Evaluated at flake evaluation time** (`tests/options.nix`, which
     evaluates fixture configurations without import-from-derivation):
     - the template rendered for `alice` with `builtins.toFile`, which
       writes at evaluation time and is not IFD, is imported into fixture
       configurations;
     - they have two normal users, `alice` and `bob`, with their own Home
       Manager configurations, and `useGlobalPkgs = true`;
     - a fixture `home.nix` holds a `hello` row, plus a `pkgsOther.hello`
       variant.

     It asserts the spec's five cases from `config.assertions` (the failed
     messages) and `home-manager.users.<u>.home.packages`:
     - `alice` gets `hello`, and `bob` does not;
     - `useGlobalPkgs = false` gives the first message;
     - the user not defined gives the second;
     - `alice` without her own Home Manager configuration gives the third;
     - with the other channel set, the `pkgsOther` row evaluates. Unset,
       forcing it fails as a null access.
   - **The generator is proven in the build.** Case 8 renders the same
     template for the build's user and imports, with the same
     substitution, and `cmp`s it with apply's real generated
     `nixarchy-apps.nix`.
   - **§1:**
     - drop each assertion in turn, and its options case fails;
     - drop the `configuredElsewhere` file filter, and the
       no-own-configuration case fails;
     - change one byte of apply's substitution, and case 8's `cmp` fails.
   **Deviations found implementing step 5** (lead):
   - **"User not defined":** Home Manager's own lookup of
     `config.users.users.<user>.name` throws before any assertion is read.
     That is still a pre-switch failure, but with Home Manager's message.
     The fixture tests the realistic case instead: `alice` as a system user,
     so nixarchy's `isNormalUser` message fires.
   - **"No configuration of her own":** without a `home.stateVersion` from
     somewhere, Home Manager throws first. The fixture supplies it through
     `home-manager.sharedModules`, the case `configuredElsewhere` exists
     for, so only nixarchy's assertion refuses.
   - **`pkgsOther` unset:** the fixture `home.nix` records whether its
     argument was null in `home.sessionVariables`, and the case reads it.
     The null-access failure cannot be caught by `tryEval`.
   - **The template** is exported as
     `environment.etc."nixarchy/home-apps-template.nix"`, so the tests read
     its text without IFD.

6. **The rest:**
   - `tests/writer-lock.nix`: `--home` rows for the three writers (:252-261);
   - `tests/options.nix`: `home-template.nix` byte-format assertions and a
     `--home` remove-symmetry case (:5552-5609's shape);
   - `tests/coexistence/fixtures.nix` and `default.nix`: the two §14
     fixtures.
   - Verify: `writer-lock`, `options-files`, `coexistence`.

## Tests

- **Cheap and package tier:** every check `generated-checks.sh generated`
  prints, plus `home-selection`, `writer-lock`, `app-selection`, the
  `apply-*` checks and `coexistence`.
- **Evaluation-heavy** (the options tier in §6, not VM boots):
  `options-files` and `options-home`.
- **VM tier:** `session` locally, because apply changed, under §6's gate as
  run today. CI runs it too.
- **Not run locally:** the install job (CI).

## Rollback

1. Revert the merge.
2. A machine that already applied a `home.nix` still has the home import in
   its own generated `nixarchy-apps.nix`, which is outside this
   repository. Run `nixarchy-apply` once with the reverted script to
   regenerate it. The reverted script writes the plain file without the
   home import. Only then rebuild.

Apply also keeps per-file hashes and edited-in-flake backups under
`$XDG_STATE_HOME/nixarchy/applied`. These are inert after the revert.
