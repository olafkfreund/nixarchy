---
status: approved
issue: 1809
intent: intent/2026-11-16-1809-home-selection.md
---

# Spec: a Home Manager selection file, and writers that can target it

Line numbers are `main` at the branch point. `apps.nix` means
`modules/apps.nix`.

## Facts the design rests on

- **Home Manager's NixOS module is always imported**
  (`modules/nixos.nix:337`). Every machine with nixarchy's NixOS module has
  `home-manager.*` options. The intent's "machine without Home Manager's
  NixOS module" exists only without nixarchy, where `nixarchy-apply` is not
  installed. So the generated file may name `home-manager.users`
  unconditionally.
- **nixarchy's module does not set `home-manager.useGlobalPkgs`.** The
  installer does (`installer/host.nix:212-215`, with `useUserPackages` and
  `sharedModules`). Mode A machines may not.
- **The generated `nixarchy-apps.nix` is a plain attrset** (`apps.nix:4732-4737`).
- **`pkgsOther` is a NixOS `_module.args` value** (`apps.nix:1577-1595`)
  that throws when `programs.nixarchy.otherChannel.flake` is null. Home
  Manager modules do not see NixOS `_module.args`.
- **Pins:** `--expect-sha256` accepts any part name. The pinned bytes are
  snapshotted into `$pinned` and compared (`apps.nix:4631-4650`, exit 4).
  The copy loop applies only `apps services advanced flatsnap`
  (`apps.nix:4670`).
- **Seeding:** `modules/home.nix:1408-1415` seeds `apps services advanced`
  from `/etc/nixarchy/<part>-template.nix` when the user's file is absent.
- **The three writers:**

  | writer | target | parses options | writes with |
  |---|---|---|---|
  | `pkg-add` | `apps.nix` (`file=`, 2939) | yes (2995-3004) | `nx_commit` (3456) |
  | `pkg-remove` | `apps.nix` (2600) | no | `nx_sed` / `nx_put` |
  | `opt-remove` | `apps.nix` (2825) | no | `nx_put` |

  `pkg-add` also:
  - refuses curated names (3160-3168);
  - adds `pkgsOther` to the header (`ensure_other_arg`, 2965-2978);
  - creates a missing block with `ensure_block` (3098-3138), hard-coded to
    `environment.systemPackages`;
  - offers the unfree scaffold (`offer_unfree_grant`, 3349-3406);
  - falls back to `nixarchy-search` (3055-3058, and `open_missed`,
    3315-3336).

## Design

### 1. The template and seeding

- **A new `homeTemplate`** (`pkgs.writeText`) beside `appsTemplate`
  (`apps.nix:389`), shaped so the writers' sed and awk anchors work:

  ```nix
  { pkgs, pkgsOther, ... }:
  {
    home.packages = with pkgs; [  #@pkgs-begin
    ];  #@pkgs-end
  }
  ```

  The `}` is at column 0, which `ensure_block` and opt-remove's insert need.
  `pkgsOther` has no default: a function default is never used for a
  module argument, because the module system supplies a lazy
  `_module.args` lookup instead. It is always supplied (§4), as `null` when
  no other channel is configured.
- **`environment.etc."nixarchy/home-template.nix"`**, beside the other three
  (`apps.nix:1637-1640`).
- **Seeding** (`modules/home.nix:1408`) adds `home` to the loop, but only
  when `osConfig.home-manager.useGlobalPkgs or false` is true. That
  matches the supported scope, and standalone Home Manager has no
  `osConfig`, so it is never seeded there.

### 2. `nixarchy-apply`

- **Selecting the source.** The home source is chosen as the loop
  chooses: `$pinned/home.nix` when pinned, otherwise `$srcdir/home.nix`.
  Every later home decision tests that selected file, never the live
  source. A pinned `home.nix` whose source vanished after the snapshot is
  still applied as pinned.
- **The user:** `user=$(id -un)`, checked by a function `valid_user` against
  `^[a-z_][a-z0-9_-]*[$]?$` (the shadow-utils pattern). On a mismatch,
  apply exits 1 before copying anything.
- **Copying:** the loop list becomes `apps services advanced flatsnap home`,
  with the same edited-in-flake handling. `home` is not added to
  `$imports`, because it is a Home Manager module, not a NixOS one.
- **The generated file** becomes a function when `home.nix` was copied, and
  stays exactly today's plain attrset otherwise, so nothing changes for
  anyone without `home.nix`:

  ```nix
  { config, options, lib, ... }:
  let
    # Home Manager configurations of <user> from anywhere but this file.
    configuredElsewhere = lib.any (d: d.file != __curPos.file && d.value ? "<user>")
      options.home-manager.users.definitionsWithLocations;
  in
  {
    imports = [ … ];
    home-manager.users."<user>".imports = [
      { _module.args.pkgsOther = if config.programs.nixarchy.otherChannel.flake != null
                                   then config._module.args.pkgsOther else null; }
      ./nixarchy/home.nix
    ];
    assertions = [
      { assertion = config.home-manager.useGlobalPkgs; message = "…needs home-manager.useGlobalPkgs = true…"; }
      { assertion = config.users.users."<user>".isNormalUser or false; message = "…<user> is not a user on this machine…"; }
      { assertion = configuredElsewhere; message = "…<user> has no Home Manager configuration of their own; home.nix adds to one, it does not create one…"; }
    ];
  }
  ```

  - **`isNormalUser`, not `users.users ? user`.** With `useUserPackages`,
    Home Manager adds a `users.users.<name>` entry (holding only
    `packages`) for every user it configures, including the one this file
    names. So "the attribute exists" is satisfied by this file itself.
    Home Manager does not set `isNormalUser`.
  - **`configuredElsewhere`** reads the option's definitions. It ignores
    this file's own, which are compared by `__curPos.file`, the generated
    file's path. So a `home-manager.users.<user>` that only this file
    creates fails the assertion.
  - **`pkgsOther`** goes to that one user's Home Manager module as
    `_module.args`, from the NixOS argument's value. It is `null` when no
    other channel is configured, so no throw is reached. No shared state is
    touched (`extraSpecialArgs` is not used, §4).
  - The user name is a Nix string literal, already validated by
    `valid_user`.
- **Failure contract:** an assertion is enforced when the system's
  toplevel is built, before any switch (`nh os switch` builds first,
  `apps.nix:4864-4892`). Apply exits with the rebuild's status, and nothing
  is switched or dropped. Apply runs no evaluation of its own.

### 3. The writers' `--home`

All three get a `--home` flag, which sets `file=…/nixarchy/home.nix` and
`scope=home`. Everything else, lock and write primitives included, is
unchanged. Each writer checks the scope first:

- **Refuses `--home` unless** `osConfig`-equivalent facts hold. The script
  knows them at build time, so `apps.nix` bakes
  `homeScope=${if config.home-manager.useGlobalPkgs then "1" else "0"}`
  into each of the three. With `0`, `--home` exits 1: "user-scope packages
  need home-manager.useGlobalPkgs = true …".
- **A missing `home.nix`** under `--home`: exits 1 with "no home.nix -- log
  in again to have it created", mirroring `nixarchy-search`'s message for
  `apps.nix`.

**`pkg-add --home`:**
- **Curated names** are refused exactly as today (3160-3168), and the
  message is unchanged.
- **`ensure_block`** writes `home.packages` instead of
  `environment.systemPackages` when `scope=home`. That is a single variable
  in its text (3110-3117).
- **`ensure_other_arg`** works unchanged on `home.nix`'s header. The header
  already has `pkgsOther ? null`, so it is a no-op, and the function is
  idempotent.
- **The unfree scaffold** is not offered. When an unfree hit exists, it
  prints the system hint: "this package is unfree; allow it in the system
  configuration (programs.nixarchy.allowUnfree, or an allowUnfreePredicate
  in ~/.config/nixarchy/apps.nix), then apply".
- **No picker:**
  - with no names: exit 1 with usage, instead of `exec nixarchy-search`;
  - with unresolved names: `open_missed` prints them and exits 1, instead of
    exec'ing the picker.

**`pkg-remove --home` and `opt-remove --home`:**
- **Pickers:** both, run with no names, open their own pickers over
  `home.nix`'s markers. Those pickers list only the scoped file, so they
  cannot reach system writers. No refusal is needed.

### 4. `pkgsOther` for Home Manager

`pkgsOther` reaches Home Manager only through the generated file (§2): as
`_module.args` on the one user that has a `home.nix`, scoped to that
user's module list. `apps.nix`'s `config` is unchanged. Machines without
`home.nix` see no new setting at all.

## Alternatives rejected

- **A function header with an `options ? home-manager` guard.** The module
  is always imported (`nixos.nix:337`), so the guard would never be false.
- **Apply evaluating `home-manager.users` itself.** That is a second
  evaluation of the whole system. The build already evaluates it, and an
  assertion fails there before any switch.
- **Strict part-name validation for `--expect-sha256`.** It is a
  compatibility change the intent defers.
- **`home-manager.extraSpecialArgs.pkgsOther`.** Home Manager declares it
  `types.attrs`, which merges with a shallow `//`. A user's own
  `pkgsOther` there would silently replace ours, or ours theirs, and it
  would apply to machines without `home.nix`.
- **`config.users.users ? user` as the user check.** Home Manager's
  `useUserPackages` creates that attribute itself.
- **Relying on Home Manager's `home.stateVersion` error** to refuse a user
  with no configuration. A shared module can supply `stateVersion`, and
  apply would then create a configuration, contrary to the intent.
- **Routing `pkg-add --home`'s picker through `nixarchy-search --home`.**
  That widens a fifth writer for a path the intent allows refusing.

## Risks

- **Machines with `home.nix` and HM settings that change later** (for
  example `useGlobalPkgs` turned off): the assertion fails the next
  rebuild, with its message. That is the contract, but it is a new way for
  a rebuild to fail.
- **A user who sets `_module.args.pkgsOther` in their own Home Manager
  module** conflicts with ours. `_module.args` merges per attribute, and
  two definitions of one value fail loudly at evaluation, which is visible,
  not silent. The coexistence fixture covers it (§14).
- **Hosts:** none until the owner applies a `home.nix`. Writers and apply
  are unchanged without it.

## Coexistence (§14)

`tests/coexistence/fixtures.nix` gains a fixture, wired into
`tests/coexistence/default.nix`'s explicit list: a user Home Manager module
that sets its own `_module.args.pkgsOther`, plus a generated home import.
Evaluation fails, naming both definitions, which is the documented loud
outcome. A second fixture with `home-manager.extraSpecialArgs.foo = 1`
shows that nixarchy does not touch `extraSpecialArgs`.

## Verification

- **`tests/home-selection.nix`** (new, cheap tier, runCommand): it runs the
  built `nixarchy-pkg-add`, `pkg-remove`, `opt-remove` and `nixarchy-apply`
  against fixture files and a fixture flake, in the shape of
  `tests/app-selection.nix` and `tests/apply-imports.nix`. Cases:
  1. **`pkg-add --home hello`:** `home.nix` gains the row, and `apps.nix`
     is byte-identical;
  2. **`pkg-add hello`** (no flag): `home.nix` is byte-identical;
  3. **`pkg-add --home firefox`** (curated): refused with today's message,
     and nothing is written;
  4. **`pkg-add --home`** with no names, and with an unresolved name, run
     under a PTY (`script`), as `tests/app-selection.nix:166-184` does, so
     `can_pick` succeeds: exit 1, and the `nixarchy-search` stub records no
     call. Without a PTY, `can_pick` alone would refuse, and the case could
     not fail;
  5. **`pkg-add --home <unfree>`**, from scripts built with `allowUnfree =
     false` and no predicate (the configuration where today's writer does
     offer the scaffold): no `#@unfree-allow` line in either file, and the
     system hint is printed;
  6. **`pkg-remove --home hello` and `opt-remove --home a.b`:** only
     `home.nix` changes;
  7. **`homeScope=0` variant** (a second build of the scripts): `--home`
     exits 1 with the `useGlobalPkgs` message, and writes nothing;
  8. **apply with `home.nix`:** the flake gets `nixarchy/home.nix`, and the
     generated file is a function with the `home-manager.users."<user>"`
     import and both assertions. Without `home.nix`, the generated file is
     byte-identical to today's;
  9. **apply with `--expect-sha256 home=<wrong>`:** exit 4, and nothing is
     copied;
  10. **pinned home, source gone:** with a correct `home=` pin, the window
      between snapshot and copy is reached deterministically. The test uses
      the same mechanism `tests/apply-detach-interface.nix` relies on (the
      plan reads it; per its note at :110, never a sleep). There it deletes
      `home.nix`. The copy and the generated import are still made from the
      snapshot. §1: switching the selection to the live file makes the case
      fail;
  11. **`valid_user`**, extracted from the built script as
      `tests/writer-lock.nix` extracts `insert_line` (a PATH stub cannot
      precede `runtimeInputs`' coreutils): accepts `alice` and `bob_2`;
      rejects `Alice`, `a b`, `x"y` and the empty string.
- **Evaluation of the file the script writes.** Case 8's generated
  `nixarchy-apps.nix` is imported into a fixture NixOS configuration with
  two normal users, `alice` and `bob`, each with their own Home Manager
  configuration, and `useGlobalPkgs = true`. Assertions are forced by
  evaluating `config.system.build.toplevel.drvPath`, which `home.packages`
  alone does not do:
  - the invoking user's (`alice`'s) `home.packages` contains `hello`, and
    `bob`'s does not;
  - with `useGlobalPkgs = false`: evaluation fails with the first message;
  - with the user not defined: the second message;
  - with `alice` having no Home Manager configuration of her own: the third
    message;
  - with the other channel configured, a `home.nix` row `pkgsOther.hello`
    evaluates. With it unset, a row forcing `pkgsOther` fails as a null
    attribute access, not a missing argument.
- **Writer matrix:** `tests/writer-lock.nix` gains `--home` rows for the
  three writers (refused under a held lock, succeeds under the handshake,
  keeps a symlinked `home.nix`).
- **`checks.options-files`:** byte-format assertions for `home-template.nix`
  as for the other templates, and a remove-symmetry case for `--home`
  (5552-5609's shape).
- **§1:** one named break per case, each shown failing first. The PR lists
  them.
