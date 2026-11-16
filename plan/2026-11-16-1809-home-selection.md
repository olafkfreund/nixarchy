---
status: draft
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
   - **Source and user:** the selection and `valid_user` (a named function,
     so step 4 can extract it), before the copy loop (:4670);
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
   - **case 10** is static, like `tests/apply-detach-interface.nix:103-118`.
     That test's comment explains why a timed race cannot fail. It greps
     that the home selection reads `$pinned/home.nix`. §1: point the
     selection at the live file, and the grep fails;
   - **case 11** extracts `valid_user` from the built script.
   - Verify: the check passes, then one named break per case.
5. **Evaluation of the generated file** (in the same check, or
   `tests/options.nix` if the evaluation fixtures there are cheaper):
   - take case 8's generated `nixarchy-apps.nix` and `nixarchy/home.nix`
     into a fixture NixOS configuration, the reference plus two normal
     users with their own Home Manager configurations, and
     `useGlobalPkgs = true`;
   - force `config.system.build.toplevel.drvPath`;
   - cover the spec's five evaluation cases, including the `pkgsOther` set
     and unset.
   - §1: drop each assertion in turn, and its case passes evaluation when
     it should not; drop the `configuredElsewhere` file filter, and the
     no-own-configuration case passes.
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
- **VM tier:** `options-files` and `options-home`; `session`, because apply
  changed.
- **Not run locally:** the install job (CI).

## Rollback

Revert the merge. A `home.nix` already applied is copied into the flake.
Reverting removes the import, and the user's home packages go at the next
rebuild, as with any reverted selection. No state outside the flake is
written.
