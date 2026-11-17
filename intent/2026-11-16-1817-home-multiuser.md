---
status: approved
issue: 1817
author: olafkfreund
---

# Intent: one home owner per host, so a second user's apply never drops the owner's selection

Follows `intent/2026-11-16-1809-home-selection.md` (merged as #1815).

## Decision

The owner chose **one home owner per host** over a full per-user model
(`home-<user>.nix` per user, one rendered block each). Review of the
per-user draft found it needs a cross-user lock, shared file permissions in
the flake, a migration for #1809's single `home.nix`, and handling of stale
users whose account is gone. And it would not make the rest of apply
per-user: the `apps`, `services`, `advanced` and `flatsnap` selections are
already one shared file each, written by whoever applied last. nixarchy's
system selections are last-writer-wins, i.e. already one owner per host.
Home selection follows the same shape, with an explicit owner and a refusal
instead of a silent drop.

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
but import only alice's file. `tests/coexistence/default.nix:29-49` likewise
renders one user. Nothing varies the number of users who applied (CLAUDE.md
section 3).

## Proposed outcome

Terms. The **template** is `/etc/nixarchy/home-template.nix`, the seed. A
caller's **home part** is their `~/.config/nixarchy/home.nix` (or the pinned
snapshot of it) when it exists and **differs from the template**. A
`home.nix` byte-identical to the template is the untouched seed and counts as
no home part.

- **The home owner** is `programs.nixarchy.user` when set. Otherwise it is
  the user named in the flake's existing generated home import,
  `home-manager.users."<x>"` in `nixarchy-apps.nix`: the first user who
  applied an edited home part.
- **Claiming:** with `programs.nixarchy.user` unset and no home import in the
  flake yet, only an edited `home.nix` claims the host. An untouched seed
  never does. With `programs.nixarchy.user` set, that user is the owner from
  the start and their `home.nix` is their home part, edited or not.
- **A non-owner with the untouched seed** has no home part: their apply
  proceeds with their system parts and keeps the owner's import and the
  copied `nixarchy/home.nix` unchanged. Seeding therefore stays as today
  (every Home Manager user with `useGlobalPkgs`, `modules/home.nix:1408-1410`):
  the seed locks nobody out.
- **A non-owner with an edited `home.nix`** is refused: exit non-zero, naming
  the owner, before any change to the flake.
- **The plain form** (no home text in `nixarchy-apps.nix`) is written only
  when there is neither a caller home part nor an existing owner import in
  the flake. Otherwise the owner's import is re-rendered unchanged.
- **Handover:** when `programs.nixarchy.user` is set and names a different
  user than the existing generated import, the existing import is kept
  (nothing is dropped) until the configured owner applies their own home
  part, which replaces it. Any other user with an edited `home.nix` is
  refused as above.
- **Removal:** the owner removes their packages by applying an empty home
  module (the template with an empty list, not a zero-byte file). The import
  and the claim remain. Ownership is released by setting
  `programs.nixarchy.user` to someone else (handover above).
- **Unchanged:** a host with one user behaves as today, and a host with no
  home part anywhere (Mode A) produces the same `nixarchy-apps.nix`, byte
  for byte.

## Affected users and systems

- Hosts with two or more Home Manager users, where today the second user's
  apply silently removes the first's selection. Single-user machines see no
  change.
- Files: `modules/apps.nix` (`nixarchy-apply`: owner resolution, the
  template comparison, the refusal, the plain-form branch),
  `tests/home-selection.nix`, and the manual page that names
  `nixarchy/home.nix`. `modules/home.nix` seeding is unchanged.
- The `apps`, `services`, `advanced` and `flatsnap` parts are untouched.

## Constraints

- **Scope: protection against accidental overwrites, not access control.**
  Any user's `advanced.nix` (or `apps.nix`) can set `programs.nixarchy.user`
  or Home Manager options directly, and nixarchy's system selections are
  unrestricted by design. The owner check stops a second user clobbering the
  owner by running apply; it does not stop a user who means to.
- **Refusal comes before the copy loop and the generated-file write.** When
  apply refuses, the flake (the copies and the generated file) and the pinned
  snapshots used for the build are untouched. User-local state (the caller's
  lock file, the state directory) may already exist.
- **Deterministic owner:** read from the generated file; exactly one
  `home-manager.users."<x>"` line names the owner. Zero lines means no owner
  yet; more than one, or a line that does not parse, makes apply refuse
  rather than guess.
- **#1809's failure contract** (its three assertions in the template) is
  unchanged.
- **Mode A:** no home part and no owner import means no home text in
  `nixarchy-apps.nix`.
- **Rendering stays Nix-safe:** the owner name passes `valid_user` wherever
  it reaches generated Nix. A trailing `$` is legal inside the quoted
  attribute name (`home-manager.users."alice$"` evaluates; interpolation
  needs dollar-brace, which `valid_user` already rejects), so
  `valid_user` is unchanged.
- **Checks (CLAUDE.md section 1, 3):** every new guard is shown failing
  first, with a two-user fixture that varies who applies. Cases:
  1. owner applies: works, import kept.
  2. non-owner with the untouched seed applies: proceeds, the owner's import
     is kept, the system parts are applied.
  3. non-owner with an edited `home.nix` applies: refused, flake
     byte-identical before and after.
  4. first apply with the untouched seed does not claim the host.
  5. configured-owner handover: the old import is kept until the configured
     owner applies, which replaces it.
  6. the plain form is written only when there is no owner import.

## Out of scope

Separate issues if wanted:

- Access control: stopping a user who edits `advanced.nix` or `apps.nix` to
  set `programs.nixarchy.user` or Home Manager options directly.
- Concurrent applies by different users (no cross-user lock is added).
- The same last-writer-wins behaviour on the shared system selections
  (`apps`, `services`, `advanced`, `flatsnap`).
- Per-user home selections for several users on one host (the model the
  owner declined).

## Open questions

1. **Resolved by the amendment below.** Was: **Owner whose account is gone.** The template's `isNormalUser` assertion
   fails the build for everyone. Keep failing loudly (proposed; the fix is
   handover by setting `programs.nixarchy.user`), or release ownership
   automatically?

## Amendment (2026-11-16, owner's decision after spec review)

Status stays approved. This amendment supersedes "The home owner is
`programs.nixarchy.user` when set", Claiming's `programs.nixarchy.user`
sentence, Handover, Removal's last sentence, and open question 1. Everything
else above stands, including Constraints and the #1809 failure contract.

- **The home owner is only the user named in the flake's existing generated
  home import** (`home-manager.users."<x>"` in `nixarchy-apps.nix`).
  `programs.nixarchy.user` no longer affects home ownership. Why: it is baked
  into the installed apply binary, so an owner whose account was deleted could
  not be replaced without a rebuild the broken flake would not allow (a
  deadlock), and handover through it raced the owner's own apply.
- **Claiming:** with no home import in the flake, the first apply with an
  *edited* `home.nix` claims the host. The untouched seed never claims.
- **Handover and recovery are one explicit command,
  `nixarchy-apply --release-home`.** It removes the home import and the copied
  `nixarchy/home.nix` from the flake, as one consistent write. It is allowed
  for the owner, and for any user when the owner's account no longer exists on
  the machine (`getent passwd <owner>` fails). Anyone else is refused.
- **After a release the host is unowned**; the next apply with an edited
  `home.nix` claims it.
- **Refusal text:** a non-owner with an edited `home.nix` is refused as
  before, and the message names the owner and points to `--release-home`.
- **Open question 1 is answered:** a gone owner is recovered by any user's
  `--release-home`; the build keeps failing loudly until then.
- **Unchanged:** Mode A (no home files anywhere: byte-identical output);
  concurrent applies and the system selections' last-writer-wins stay out of
  scope.
