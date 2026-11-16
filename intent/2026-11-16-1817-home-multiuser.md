---
status: draft
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
- `valid_user` (`modules/apps.nix:4750-4752`) accepts a trailing `$`
  (`[$]?`), which would be spliced into generated Nix.

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

- **The home owner** is `programs.nixarchy.user` when set. Otherwise it is
  the user named in the flake's existing generated home import,
  `home-manager.users."<x>"` in `nixarchy-apps.nix`: the first user who
  applied a home part.
- **Refusal before change:** `nixarchy-apply` run by a user who is not the
  owner, with a home part, exits non-zero with a message naming the owner,
  before anything is written.
- **A non-owner's apply without a home part** keeps the owner's existing
  home import and the copied `nixarchy/home.nix` unchanged (today it writes
  the plain form and silently drops the import). Only the owner's own apply
  may replace, or deliberately remove, the home import.
- **Seeding:** when `programs.nixarchy.user` is set, `home.nix` is seeded
  only for that user (`modules/home.nix:1408-1410`); when unset, seeding
  stays as now and the first apply claims the host.
- **`valid_user` rejects a trailing `$`.**
- **Unchanged:** a host with one user behaves as today, and a host with no
  home part anywhere (Mode A) produces the same `nixarchy-apps.nix`, byte
  for byte.

## Affected users and systems

- Hosts with two or more Home Manager users, where today the second user's
  apply silently removes the first's selection. Single-user machines see no
  change.
- Files: `modules/apps.nix` (`nixarchy-apply`: owner resolution,
  `valid_user`, the plain-form branch), `modules/home.nix` (seeding),
  `tests/home-selection.nix`, `tests/options.nix` if the seeding gate is
  asserted there, and the manual page that names `nixarchy/home.nix`.
- The `apps`, `services`, `advanced` and `flatsnap` parts are untouched.

## Constraints

- **Refusal happens before any write:** pins, copies and the generated
  file are untouched when apply refuses.
- **Deterministic owner:** read from the generated file; exactly one
  `home-manager.users."<x>"` line names the owner. Zero lines means no owner
  yet (first apply claims it); more than one, or a line that does not parse,
  makes apply refuse rather than guess.
- **#1809's failure contract** (its three assertions in the template) is
  unchanged.
- **Mode A:** no home part means no home text in `nixarchy-apps.nix`.
- **Rendering stays Nix-safe:** the owner name passes `valid_user`, now
  without `$`, wherever it reaches generated Nix.
- **Checks (CLAUDE.md section 1, 3):** every new guard is shown failing
  first, with a two-user fixture that varies who applies. Cases:
  1. owner applies: works, import kept.
  2. non-owner applies without a home part: the owner's import and copy are
     kept.
  3. non-owner applies with a home part: refused, nothing changed (pins,
     copies, generated file byte-identical).
  4. `programs.nixarchy.user` set: only that user is seeded, and a
     non-owner is refused even on a fresh flake.
  5. a user name ending in `$` is refused.

## Out of scope

Separate issues if wanted:

- Concurrent applies by different users (no cross-user lock is added).
- The same last-writer-wins behaviour on the shared system selections
  (`apps`, `services`, `advanced`, `flatsnap`).
- Per-user home selections for several users on one host (the model the
  owner declined).

## Open questions

1. **Deliberate removal.** Under this model the owner removes their home
   selection by applying with an empty `home.nix`, which keeps an empty
   import. Is that enough, or is a way to drop the import entirely needed?
2. **Handing over ownership.** With `programs.nixarchy.user` unset, how does
   the host change owner? Proposed: set `programs.nixarchy.user`, or edit
   the generated line by hand. Is a documented manual step acceptable?
3. **Owner whose account is gone.** The template's `isNormalUser` assertion
   fails the build for everyone. Keep failing loudly (proposed), or
   release ownership?
