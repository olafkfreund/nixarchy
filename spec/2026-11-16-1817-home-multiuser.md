---
status: draft
issue: 1817
intent: intent/2026-11-16-1817-home-multiuser.md
---

# Spec: one home owner per host

Implements `intent/2026-11-16-1817-home-multiuser.md` (approved). All line
numbers are `modules/apps.nix` at the base of this branch.

## Design

All changes are inside `nixarchy-apply`. `homeAppsTemplateText` (`:408-431`),
`modules/home.nix` seeding and the other four parts are unchanged.

### Terms

- **seed**: `home_src` byte-identical to `${homeTemplate}` (`:400`), via
  `cmp -s`. The store path is used rather than `/etc/nixarchy/home-template.nix`
  because it cannot go missing or be edited; `/etc` links to the same file
  (`:1675`). `diffutils` is already in `runtimeInputs`.
- **edited**: `home_src` non-empty and not the seed.
- `home_src` is what `select_home_src` returns (`:4740`): the pinned snapshot
  when pinned, else the live file. Every test below, and the copy loop, read
  that one value, so a refusal and a copy never look at different bytes.
- **cfg**: `programs.nixarchy.user`, baked in at build time as
  `${if cfg.user == null then "" else cfg.user}` (same pattern as `homeScope=`
  at `:2637`; the option is nullable, `modules/nixos.nix:472`). Not read at run
  time, since the flake being applied may not set it. `user=$(id -un)` stays the
  caller.
- **imported**: the owner named by the existing `nixarchy-apps.nix` (`$dest`).

### Reading the imported owner (deterministic)

Placed after `user=$(id -un)` (`:4756`), guarded by `[ -f "$dest" ]`:

- Lines matching `^  home-manager\.users\."[^"]*"\.imports` give the names;
  `sort -u` them. `homeAppsTemplateText` is the only emitter and always writes
  exactly that shape at that indent. The template's other `home-manager.users`
  tokens (`options.home-manager.users.definitionsWithLocations`, the
  `d.value ? "@USER@"` test, `config.users.users."@USER@"`) do not match the
  anchored pattern, so a correct generated file never trips the refusal.
- 0 names and no other line starting `  home-manager.users.`: unowned.
- Exactly 1 name: imported owner. It must pass `valid_user` (`:4750`) before it
  reaches `sed`, since it is read back from a file.
- More than 1 name, or a `  home-manager.users.` line the pattern did not
  match: refuse (exit 1), message names `$dest`. Never guess.

### Ownership rule (decision order)

`owner` = `cfg` if non-empty, else `imported`, else none. `isowner` = caller
equals `owner`.

1. **Caller is the owner (`isowner`).** If the caller has any `home.nix`
   (seed included) it is the home part: copy it and render `import(caller)`.
   The seed is deliberately a home part here. Otherwise the owner could never
   remove packages: the template already has an empty list
   (`:400-406`), so "apply the empty module" (intent, Removal) is the seed byte
   for byte. This settles two things the intent states inconsistently (its
   lines 68-72 versus 79-80 and 96-99): the seed test applies to non-owners
   only. If cfg names the caller and `imported` is another user A, this is the
   **handover**: A's import is replaced, A's packages drop, and apply prints a
   one-line note saying so. If the owner has no `home.nix`, there is no home
   part: fall through to rule 3.
2. **Caller is not the owner and is edited.** Refuse, exit 1, before the copy
   loop. This covers cfg set to someone else, and any imported owner other
   than the caller.
3. **Caller is not the owner and has the seed or no file.** No home part.
   Proceed with apps, services, advanced and flatsnap. The `home` iteration of
   the copy loop is skipped, so the owner's `nixarchy/home.nix`, its record and
   `copied` are untouched. Render `import(imported)` if there is one (see
   below).
4. **No owner at all** (cfg empty, nothing imported): an edited file claims
   (rule 1 applies with the caller as owner); the seed or no file does not, and
   the plain form is written.

Resulting table (O = owner, C = caller):

| cfg | imported | C | C's home.nix | outcome |
|---|---|---|---|---|
| unset | none | any | seed/none | proceed, plain form |
| unset | none | C | edited | claim, render import(C) |
| unset | O | O | any | copy, render import(O) |
| unset | O | C | seed/none | proceed, import(O) kept, home.nix untouched |
| unset | O | C | edited | refuse, names O |
| =O | O | O | any | as above |
| =O | O | C | seed/none | proceed, import(O) kept |
| =O | O | C | edited | refuse, names O |
| =X | none | X | any | claim, render import(X) |
| =X | none | Y | seed/none | proceed, plain form |
| =X | none | Y | edited | refuse, names X |
| =X | A | X | any file | handover: import(X) replaces import(A) |
| =X | A | X | none | proceed, import(A) kept until X has a file |
| =X | A | A or Y | seed/none | proceed, import(A) kept |
| =X | A | A or Y | edited | refuse, names X |
| any | malformed or 2+ | any | any | refuse, names `$dest` |

A zero-byte `home.nix` is an ordinary edited file: no new branch. For the
owner it is copied and the Home Manager module system fails the build; the
manual says so. The owner whose account is gone (open question): keep failing
loudly on the template's `isNormalUser` assertion (`:426`); the refusal and
the manual name `programs.nixarchy.user` as the fix.

### Where it sits in `nixarchy-apply`

- Owner parse and cfg: right after `user=$(id -un)` (`:4756`).
- Decision and refusal: in the block at `:4754-4760`, before the copy loop
  (`:4762`). The only earlier effects are `mkdir -p`, the lock and the pin
  snapshots (a pin mismatch still exits 4 first, `:4714`). No flake file and no
  pinned snapshot has been touched. Messages go to stderr so a detached unit
  shows them in `--log`.
- Copy loop: for `part = home`, `continue` when rule 3 applies (non-owner), put
  just before `dst` is set (`:4774`).
- Render (`:4828`): choose the template branch when the caller supplies a home
  part (rules 1/4) or an owner is imported (rule 3); substitute `@USER@` with
  `render_user` (`caller` or `imported`), and run `valid_user` on it. The
  plain branch (`:4833-4840`) is reached only with neither, which keeps Mode A
  byte-identical.
- Messages: `nixarchy-apply: home.nix belongs to <owner>; <caller> has edited
  theirs. Ask <owner> to apply, or set programs.nixarchy.user to hand over.`
  and `nixarchy-apply: <dest> names several home owners (or an unparseable
  one); fix it by hand`.

### Docs

The manual page naming `nixarchy/home.nix` gets the owner rule, the handover,
removal by applying the empty module, and the zero-byte note.

## Alternatives rejected

- **Per-user `home-<user>.nix`** (the owner declined it): needs a cross-user
  lock, shared permissions, a #1809 migration and stale-user handling, and the
  other four parts stay last-writer-wins anyway.
- **Release ownership automatically when the owner's account is gone**: hides a
  real misconfiguration; the build failure is the right signal.
- **Reading cfg from the flake at run time**: the flake may not set it, and
  baking it matches `homeScope`.
- **Comparing against `/etc/nixarchy/home-template.nix`**: a mutable path; the
  store path is the same bytes without the failure mode.
- **Seed counts as no home part for everyone**: breaks owner removal (above).

## Risks

- Existing flakes where a second user already overwrote the import are read as
  owned by that user; handover via cfg is the repair.
- The anchored parse depends on the template's shape; a template change must
  update it. Case 7 parses the real generated file so this fails loudly.
- Scope is accidental overwrite, not access control (intent constraint): a
  user editing `advanced.nix` can still set cfg.
- Coexistence (CLAUDE.md s14): no new option or merged-env contribution, so no
  new fixture; Mode A is covered by the plain-form case.
- Concurrent applies by different users stay out of scope.

## Verification

Extend `tests/home-selection.nix` (one user today, so it cannot vary the
variable that matters, s3). The sandbox caller is `$(id -un)`; vary the owner
by pre-seeding `flake/nixarchy-apps.nix` (render `homeAppsTemplate` with `sed`,
as case 8 does) naming `$(id -un)` or `alice`. cfg variants use
`variantBin (configWith { nixarchy.user = ...; }) "apply"` as `unfreeOff` does.
The multi-name decision table is also exercised by sourcing the decision
function with explicit caller, cfg and imported arguments (as `select_home_src`
and `valid_user` are sourced, cases 10-11), since the sandbox name is unknown
at evaluation time; document in `tests/AGENTS.md` that the handover's
configured-owner-applies half is covered by that function only.

Cases, each `NIXARCHY_FLAKE=$PWD/flake "$apply" --yes --no-preview`, fresh
`flake/` each time, bash script (s1):

1. owner applies edited file: rc 0, import kept, `home.nix` copied.
2. owner applies the seed: copied, import kept (removal works).
3. non-owner, seed: rc 0, import(alice) kept, `nixarchy/home.nix` unchanged,
   caller's `apps.nix` copied.
4. non-owner, edited: rc != 0, stderr names alice, hash of `flake/`
   (`find flake -type f | sort | xargs sha256sum | sha256sum`) identical. The
   fixture holds a stale `apps.nix` that differs from the caller's, so a
   refusal placed after the copy loop changes the hash.
5. first apply with seed, no import: rc 0, plain form, no `home-manager.users`.
6. handover: cfg alice, import bob; stranger edited refused with identical
   hash and bob's import kept; configured owner applying replaces it (function
   level); cfg owner without a file keeps bob's import.
7. malformed state (two import lines; one unparseable line): rc != 0, identical
   hash. Plus: the real generated file parses as exactly one owner.
8. zero-byte caller `home.nix` as non-owner is refused; as owner it is copied.

Section 1 breaks, one per guard (prove each landed with `git diff`; restore
with `git checkout HEAD -- modules/apps.nix` from a committed baseline; failing
output goes in the PR):

| case | break |
|---|---|
| 1 | owner detection always false |
| 2 | seed test applied to the owner too |
| 3 | seed test never matches (seed treated as edited) |
| 4 | refusal moved after the copy loop, then deleted |
| 5 | seed claims the host |
| 6 | handover drops the old import / old import not kept |
| 3b | revert to plain form whenever `home_src` is empty (the #1817 bug 2) |
| 7 | multiple import lines pick the first |

Options tier (`tests/options.nix`) needs no change while the template text is
unchanged; if it changes, add a bob-owner case in the `homeAppsUserScope`
shape (`:1361-1369`).

Not run locally here: nothing is built by this spec.
