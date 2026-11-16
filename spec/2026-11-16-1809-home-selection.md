---
status: draft
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
  { pkgs, pkgsOther ? null, ... }:
  {
    home.packages = with pkgs; [  #@pkgs-begin
    ];  #@pkgs-end
  }
  ```

  The `}` is at column 0, which `ensure_block` and opt-remove's insert need.
  `pkgsOther ? null` is a default here, which is allowed: this is a Home
  Manager module argument, delivered by `extraSpecialArgs` (§4), not a
  NixOS module argument.
- **`environment.etc."nixarchy/home-template.nix"`**, beside the other three
  (`apps.nix:1637-1640`).
- **Seeding** (`modules/home.nix:1408`) adds `home` to the loop, but only
  when `osConfig.home-manager.useGlobalPkgs or false` is true. That
  matches the supported scope, and standalone Home Manager has no
  `osConfig`, so it is never seeded there.

### 2. `nixarchy-apply`

- **Before the copy loop** (`apps.nix:4670`), when `$srcdir/home.nix`
  exists:
  - **User:** `user=$(id -un)`.
  - **Pin:** a `home=` pin is already snapshotted and compared by the
    existing pin code, unchanged. The copy step below takes `home` from
    `$pinned` like the others, so a `home` pin now covers applied bytes.
- **Copying:** the loop list becomes `apps services advanced flatsnap home`,
  with the same edited-in-flake handling. `home` is not added to
  `$imports`, because it is a Home Manager module, not a NixOS one.
- **The generated file** becomes a function when `home.nix` was copied, and
  stays exactly today's plain attrset otherwise, so nothing changes for
  anyone without `home.nix`:

  ```nix
  { config, lib, ... }:
  {
    imports = [ … ];
    home-manager.users."<user>".imports = [ ./nixarchy/home.nix ];
    assertions = [
      {
        assertion = config.home-manager.useGlobalPkgs;
        message = "nixarchy: ~/.config/nixarchy/home.nix needs home-manager.useGlobalPkgs = true …";
      }
      {
        assertion = config.users.users ? "<user>";
        message = "nixarchy: home.nix was applied for <user>, who is not a user on this machine …";
      }
    ];
  }
  ```

  The user name is written as a Nix string literal. `id -un` output is
  validated against `^[a-z_][a-z0-9_-]*[$]?$` (the shadow-utils pattern),
  and apply refuses with exit 1 before copying if it does not match.
- **Failure contract:** a failed assertion fails evaluation and the build,
  which come before any switch (`nh os switch` builds first;
  `apps.nix:4864-4892`). Apply then exits with the rebuild's status, and
  nothing is switched or dropped.
  - A real user with no other Home Manager configuration gets Home
    Manager's own `home.stateVersion` error. That is also a pre-switch
    failure. A one-line comment in the generated file names that case.
  - The intent's "apply refuses" holds through the build. Apply does not
    run its own evaluation.

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

In `apps.nix`'s `config` (beside `_module.args.pkgsOther`, 1577):

```nix
home-manager.extraSpecialArgs = lib.mkIf (cfg.otherChannel.flake != null) {
  inherit pkgsOther;
};
```

It is set only when the other channel is configured, so Mode A without one
is untouched, and `pkgsOther`'s throw is never reached. `home.nix`'s
`pkgsOther ? null` covers the unset case.

## Alternatives rejected

- **A function header with an `options ? home-manager` guard.** The module
  is always imported (`nixos.nix:337`), so the guard would never be false.
- **Apply evaluating `home-manager.users` itself.** That is a second
  evaluation of the whole system. The build already evaluates it, and an
  assertion fails there before any switch.
- **Strict part-name validation for `--expect-sha256`.** It is a
  compatibility change the intent defers.
- **Routing `pkg-add --home`'s picker through `nixarchy-search --home`.**
  That widens a fifth writer for a path the intent allows refusing.

## Risks

- **Machines with `home.nix` and HM settings that change later** (for
  example `useGlobalPkgs` turned off): the assertion fails the next
  rebuild, with its message. That is the contract, but it is a new way for
  a rebuild to fail.
- **`extraSpecialArgs` merges with a user's own.** Home Manager's option is
  an attrset, and a user's `pkgsOther` of their own would conflict loudly.
  A coexistence fixture covers it (CLAUDE.md §14).
- **Hosts:** none until the owner applies a `home.nix`. Writers and apply
  are unchanged without it.

## Coexistence (§14)

`tests/coexistence/fixtures.nix` gains a fixture with
`home-manager.extraSpecialArgs.foo = 1` set by the user and the other
channel configured. Both keys survive the merge.

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
  4. **`pkg-add --home`** with no names, or an unresolved name: exit 1, and
     no `nixarchy-search` (stubbed to record a call) is executed;
  5. **`pkg-add --home <unfree>`:** no `#@unfree-allow` line in either
     file, and the system hint is printed;
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
  10. **apply with `--expect-sha256 home=<right>`:** the bytes copied are the
      snapshot's. The source is changed after the pin is computed, and the
      copy holds the pinned bytes;
  11. **apply when `id -un` does not match the pattern** (a stub `id`): exit
      1, and nothing is copied.
- **Evaluation** (in `tests/options.nix`, or the new check if cheaper):
  - the reference configuration plus a fixture `nixarchy-apps.nix` with the
    home import evaluates, and the user's `home.packages` contains `hello`;
  - with `useGlobalPkgs = false`, evaluation fails with the assertion's
    message;
  - with a user that does not exist, evaluation fails with the second
    message.
- **Writer matrix:** `tests/writer-lock.nix` gains `--home` rows for the
  three writers (refused under a held lock, succeeds under the handshake,
  keeps a symlinked `home.nix`).
- **`checks.options-files`:** byte-format assertions for `home-template.nix`
  as for the other templates, and a remove-symmetry case for `--home`
  (5552-5609's shape).
- **§1:** one named break per case, each shown failing first. The PR lists
  them.
