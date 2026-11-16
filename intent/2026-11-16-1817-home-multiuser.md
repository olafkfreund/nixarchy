---
status: draft
issue: 1817
author: olafkfreund
---

# Intent: per-user home selections, so one user's apply never drops another's

Follows `intent/2026-11-16-1809-home-selection.md` (merged as #1815).

## Problem

#1809 gave each Home Manager user a `~/.config/nixarchy/home.nix`, but the
flake side of it is single-user:

- `nixarchy-apply` copies the caller's file to one shared path,
  `$base/nixarchy/home.nix` (`modules/apps.nix:4772`, the `home` part of the
  copy loop at `:4763`).
- It regenerates `nixarchy-apps.nix` from `homeAppsTemplate` with the caller
  alone substituted for `@USER@` (`modules/apps.nix:4829`; template at
  `:408-431`, one `home-manager.users."@USER@".imports = [ ./nixarchy/home.nix ]`).
- With no home part, the generated file is the plain `imports = [ ... ]`
  form (`modules/apps.nix:4831-4836`), with no home import at all.
- Every Home Manager user on a `useGlobalPkgs` machine has `home.nix` seeded
  (`modules/home.nix:1408-1410`), so any second user hits this without opting in.

Two ways a second user's apply drops the first user's selection:

1. **Bob has a `home.nix`** (the seeded, empty one). `select_home_src`
   (`modules/apps.nix:4740`) returns Bob's file; the copy loop overwrites
   `nixarchy/home.nix` with it (`diff` differs, `copy_into_flake`,
   `:4772`). Edited-in-flake detection cannot help: its record
   (`$applied/<hash of dst>`, `:4765`) lives under Bob's own
   `XDG_STATE_HOME`, so with no record of his own the overwrite is silent.
   The regenerated file imports `home-manager.users."bob"` only, so Alice's
   packages are removed at the next switch.
2. **Bob has no `home.nix`** (seeding skipped, deleted, or a machine that
   predates #1809). `home_src` is empty, so the plain template is written
   (`:4831`) and the shared file is not touched, but nothing imports it any
   more. Alice's import is dropped just the same.

Both contradict #1809's approved intent ("never silently dropping packages").

What the tests assume: `tests/home-selection.nix` has one user
(`someone`, `:25`; the user is `id -un`) and case 8 compares the generated
file against exactly one `@USER@` substitution (`:161`). `tests/options.nix`
`homeApps*` cases (`:1361-1404`, fixture `:3115-3193`) define alice and bob
but import only alice's file; the template is applied once with
`@USER@`=alice. `tests/coexistence/default.nix:29-49` likewise renders one
user. Nothing varies the number of users who applied (CLAUDE.md section 3).

## Proposed outcome

- **Per-user copies in the flake:** `$base/nixarchy/home-<user>.nix`, copied
  from that user's `~/.config/nixarchy/home.nix`.
- **Per-user rendered modules:** one block per user, rendered from the
  template, for every `home-<user>.nix` present in the flake. The generated
  `nixarchy-apps.nix` imports all of them, whoever applied.
- **A user's apply rewrites only their own files.** A user without
  `home.nix` removes nobody else's import (and adds none of their own).
- Edited-in-flake rules, `--expect-sha256 home=` pins and the `valid_user`
  check keep their meaning, now per user's file.
- **Mode A:** with no `home-*.nix` in the flake, `nixarchy-apps.nix` stays
  byte-identical to today's plain form.

## Affected users and systems

- Hosts with two or more Home Manager users applying to one flake (the
  family or shared-workstation case); single-user machines see no change
  beyond a renamed copy.
- Files: `modules/apps.nix` (`nixarchy-apply`, `homeAppsTemplateText`),
  `tests/home-selection.nix`, `tests/options.nix` (`homeApps*`,
  `casesD`), `tests/coexistence/`, and the manual page that names
  `nixarchy/home.nix`.
- The `apps`, `services`, `advanced` and `flatsnap` parts are shared in the
  same way (one `$base/nixarchy/<part>.nix`); this intent does not change
  them (see Open questions).

## Constraints

- **Migration:** a flake carrying #1809's single `nixarchy/home.nix` must
  keep evaluating after upgrade, and its owner is unrecorded.
- **Edited-in-flake:** a hand-edit to `home-<user>.nix` is kept, and
  reported, exactly as for the other parts.
- **Pins:** `--expect-sha256 home=` pins the invoking user's bytes; no
  pin may let a different file be applied (#1809 constraint).
- **Mode A:** no home file anywhere means no home text anywhere in
  `nixarchy-apps.nix`, byte for byte.
- **Clearing a selection:** a user who applies with no `home.nix` must not
  silently lose it, yet there must be a deliberate way to remove it.
- **Rendering stays Nix-safe:** every user name that reaches generated Nix
  passes `valid_user`, including names found by scanning the flake.
- **Checks (section 1):** every new guard is shown failing first. The
  two-user case must be a fixture that varies the user count, and the
  failure of both drop paths above must be reproduced before the fix.

## Open questions

1. **Migration owner.** An existing `nixarchy/home.nix` from #1809 has no
   recorded owner. Options: (a) the first user to apply after upgrade
   adopts it if their file's bytes equal it, otherwise it is left and
   imported for no one (loses it); (b) rename it to `home-<user>.nix` for
   whoever applies first and tell them; (c) keep importing a legacy
   `home.nix` for the user named in the existing generated file's
   `home-manager.users."<user>"` line, deterministic and recoverable.
   Which?
2. **Clearing a selection.** How does a user deliberately remove theirs?
   Options: an empty `home.nix` (already works: empty module); a
   `nixarchy-apply --drop-home` flag deleting only their own copy; or
   removing their file by hand in the flake.
3. **Users whose copy is present but who no longer exist** (account
   deleted): the `isNormalUser` assertion (`:426`) would fail the build for
   everyone. Skip with a warning, or keep failing loudly?
4. **Scope of the shared parts.** Should `apps.nix` and friends become
   per-user too, or is that a separate issue? (They are inherently
   machine-wide system selections, so proposed: separate, unchanged.)
5. **Enumerating users.** Generate imports by scanning
   `$base/nixarchy/home-*.nix` at apply time, or keep a small manifest? The
   scan is simpler; a manifest survives a partial git checkout.
