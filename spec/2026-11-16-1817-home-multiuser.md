---
status: approved
issue: 1817
intent: intent/2026-11-16-1817-home-multiuser.md
---

# Spec: one home owner per host

Implements `intent/2026-11-16-1817-home-multiuser.md` (approved, with its
2026-11-16 amendment). All line numbers are `modules/apps.nix` at the base of
this branch.

## Design

All changes are inside `nixarchy-apply`. `homeAppsTemplateText` (`:408-431`),
`modules/home.nix` seeding (`:1408-1410`) and the other four parts are
unchanged. `programs.nixarchy.user` is not read: nothing is baked in for
ownership (contrast `homeScope=` at `:2637`).

### Terms

- **seed**: the caller's home.nix is byte-identical to `${homeTemplate}`
  (`:400`), via `cmp -s`. The store path is used rather than
  `/etc/nixarchy/home-template.nix` because it cannot go missing or be edited.
- **edited**: a home.nix that exists and differs from the template. This is
  the one definition used everywhere below.
- **state** of the caller's home part: `absent`, `seed` or `edited`.
- **owner**: the one user named by the existing `nixarchy-apps.nix` (`$dest`),
  or empty. Nothing else makes an owner.
- **snapshot**: right after `select_home_src` (`:4740`), `cp` its result to
  `$pinned/home.snap` (a file under the existing `$pinned` temp dir, as pins
  do). State is computed from the snapshot and the copy reads the snapshot, so
  an editor change mid-apply cannot split classification from copy. When pinned
  the source is already a snapshot; the extra `cp` keeps one path.

### Reading the owner (`read_owner`)

Placed after `user=$(id -un)` (`:4756`), guarded by `[ -f "$dest" ]`. It
prints the owner or nothing, and exits 1 with a message naming `$dest` on
malformed state:

- Lines matching `^[[:space:]]*home-manager\.users\.` (any indentation) are
  the candidates. The template's other tokens
  (`options.home-manager.users.definitionsWithLocations`, `d.value ? "@USER@"`,
  `config.users.users."@USER@"`) do not start the line with it, so a correct
  generated file never trips this.
- Of those, the lines matching the exact form
  `^[[:space:]]*home-manager\.users\."<name>"\.imports[[:space:]]*=` are
  counted with `grep -c` **before any dedup** (two identical lines are two).
- Count 1 and every candidate matched the exact form: owner `<name>`, which
  must pass `valid_user` (`:4750`) because it is read back from a file.
- Count 0 and no candidate: unowned.
- Anything else (count above 1, or a candidate that is not the exact form,
  e.g. an unquoted name): refuse. Malformed state never reads as unowned.

### Decision (`home_decide`)

A named shell function, extracted by the tests like `select_home_src`. Inputs:
`owner` (name or empty), `caller`, `state` (`absent|seed|edited`). Output, one
word: `claim` (render and copy; the caller becomes owner), `copy` (the owner
replaces their copy), `keep` (no home part from the caller: copy nothing,
re-render the owner's import if there is one, else the plain form), `refuse`.

Order matters: the unowned claim is evaluated **before** the non-owner refusal,
otherwise the first claim on a fresh host is refused.

| owner | caller | state | output |
|---|---|---|---|
| empty | any | edited | claim |
| empty | any | seed or absent | keep (plain form) |
| O | O | seed or edited | copy |
| O | O | absent | keep |
| O | C | absent or seed | keep (import(O) and copy byte-identical) |
| O | C | edited | refuse |

The seed rule applies to non-owners and the unowned case only: a seed never
claims and never refuses. The owner's own file is always copied, seed
included, which is how an owner applies an empty module and removes packages
(the seed is the template with an empty list).

A zero-byte home.nix is an ordinary edited file. The owner's is copied and the
Home Manager module system fails the build; the manual says so.

### `--release-home` and `account_exists`

`account_exists` is its own function so a test can extract the logic and
replace it. It runs `getent passwd "$1"` and maps the status to three answers,
never two:

- exit 0: the account exists.
- exit 2: confirmed absent (getent's "key not found").
- any other status (127 command missing, 1, 3, ...): a lookup failure, which
  **refuses** the release with a message naming the status
  (`nixarchy-apply: cannot tell whether <owner> still has an account (getent
  exited <n>); not releasing`). Only confirmed absence lets a non-owner
  release.

`getent` is not in `nixarchy-apply`'s `runtimeInputs` (`:4391`: branch-guard,
coreutils, diffutils, gnugrep, git, gnused, util-linux, nh, systemd, ...), so
the plan adds it there: `pkgs.getent` (nixpkgs' glibc getent package; the plan
confirms the attribute evaluates before using it, `pkgs.glibc.bin` being the
fallback). An undeclared command would otherwise be status 127, which the rule
above turns into a refusal rather than a wrong "gone". `--release-home` is parsed with the
other flags; it takes the lock like any apply. After `read_owner`:

- owner empty: print `no home owner; nothing to release`, exit 0.
- allowed when caller = owner, or `account_exists "$owner"` fails. Otherwise
  refuse (exit 1) naming the owner, before any write.
- allowed: render the plain form for the generated file, then do the pair
  write below with no copy. The run then continues as an ordinary apply of the
  other four parts, with the home part forced to `keep`; a caller's edited
  home.nix does not claim in the same run. Print which owner was released.

### Pair write (`write_home_pair`)

The home copy (`$base/nixarchy/home.nix`) and `$dest` must change together, or
the flake imports one user with another user's selection.

1. Render both to temp files first (the new copy from the snapshot; the
   generated file through the existing template/plain branches, `@USER@` =
   `render_user`, validated). Nothing in the flake has changed yet.
2. Back up the current copy to `$pinned/home.bak` (or note it was absent).
3. Write order depends on the result, and each replacement goes through a named
   function `replace_file <src> <dst>` (a temp file `mv`d into place, so each
   is atomic):
   - the result **has an import** (claim, owner copy): the home copy first,
     `$dest` second;
   - the result **removes the import** (`--release-home`): `$dest` first
     (dropping the import), then remove the copy.
4. If a step fails: restore the backup copy (or remove a copy that did not
   exist before) and exit non-zero. The previous pair is what remains.
5. Only after success, update the copy's record in `$applied`.

Why the order makes a crash safe: killed between the two writes, the has-import
order leaves the old `$dest` (old import, or none) beside a new copy, which is
either the same user's file or unimported; the release order leaves `$dest`
without the import beside the old copy, an orphan nothing imports. So no
interruption leaves an import pointing at a missing file or at another user's
file. An orphan copy is harmless and the next apply or `--release-home`
rewrites or removes it.

The home iteration of the copy loop (`:4762`) is removed from the loop; the
other four parts keep it. Render choice at `:4828`: the template branch when
the output is `claim`/`copy`, or `keep` with an owner (`render_user` = owner);
the plain branch (`:4833-4840`) only when unowned and nothing to copy, which
keeps Mode A byte-identical.

### Where it sits

Owner parse, snapshot, state and decision: in the block at `:4754-4760`,
before the copy loop. The only earlier effects are `mkdir -p`, the lock and the
pin snapshots (a pin mismatch still exits 4 first, `:4714`). A `refuse` leaves
the flake and pins untouched. The user-name check (`:4757`) is gated on "a name
will reach generated Nix": a `claim`/`copy` caller or a non-empty owner.
Messages go to stderr.

- Refusal: `nixarchy-apply: home.nix belongs to <owner>; <caller> has edited
  theirs. Ask <owner> to apply, or run nixarchy-apply --release-home to give
  the host up.`
- Malformed: `nixarchy-apply: <dest> names several home owners (or an
  unparseable one); fix it by hand`.

### Docs

The manual page naming `nixarchy/home.nix` gets: the owner is whoever the flake
names; `programs.nixarchy.user` does not affect it; claiming; the refusal;
`--release-home` (owner, or anyone once the owner's account is gone); removal
by applying the empty module; the zero-byte note.

## Alternatives rejected

- **`programs.nixarchy.user` as owner and handover through it** (earlier
  draft): baked into the installed binary, so a deleted owner deadlocks
  recovery, and handover raced the owner's apply. The owner decided against it.
- **Per-user `home-<user>.nix`**: lock, permissions, migration, stale users,
  and the other four parts stay last-writer-wins anyway.
- **Releasing automatically when the owner's account is gone**: hides a
  misconfiguration, and an unattended write of the flake. The explicit
  command, allowed for anyone in that case, gives the same recovery.
- **Comparing against `/etc/nixarchy/home-template.nix`**: mutable; the store
  path is the same bytes.
- **Seed counts as no home part for everyone**: breaks owner removal.

## Risks

- Existing flakes where a second user already overwrote the import read as
  owned by that user; `--release-home` is the repair.
- The anchored parse depends on the template's shape; a template change must
  update it. The "real generated file parses as one owner" case fails loudly.
- Scope is accidental overwrite, not access control (intent): anyone can run
  `--release-home` once the owner's account is gone, and edit the flake.
- A crash between the two pair writes is made safe by write order, not rolled
  back: see "Why the order makes a crash safe" above. The worst case is an
  unimported orphan copy, cleaned by the next apply or release.
- Coexistence (CLAUDE.md s14): no new option or merged-env contribution, so no
  fixture; Mode A is covered by the plain-form case.
- Concurrent applies and system-selection last-writer-wins stay out of scope.

## Verification

### Existing tests that change

- `tests/home-selection.nix` case 8, "with home": its `reset_files` home file
  is byte-identical to the seed, which under the new rule is unowned + seed and
  yields the plain form. It must write an edited file (an added package line),
  and the expected file stays the template with `@USER@` = `$(id -un)`.
- Case 8, "without home": unchanged, but the shared `flake/` now carries state
  between cases (a generated file makes an owner), so each new case starts from
  a fresh `flake/` through a `fresh_flake` helper; case 8 and 9 keep their order.
- Case 9 (pin mismatch exits 4, nothing changed): unchanged in assertions; it
  reuses case 8's flake.
- Case 11: the static grep `if [ -n "$home_src" ] && ! valid_user "$user"; then`
  encodes the old gate and is retargeted to the new gate (claim/copy caller or
  non-empty owner); `valid_user` cases are unchanged.
- Case 10 (`select_home_src`): unchanged.
- No case "assumes `someone` always owns" other than case 8; the one-user
  fixture (`:23-27`) stays, the owner is varied through the flake instead.
- `tests/options.nix` `homeApps*` (`:1361-1404`, fixture `:3115-3193`): no
  change. The template text is unchanged; alice is the fixture's owner and
  bob's file is never imported, which is what `homeAppsUserScope` asserts.
- `tests/coexistence/default.nix:29-49`: no change (one rendered user, text
  unchanged).

### New cases

Ownership comes from the flake fixture, so the baked config of the apply binary
is irrelevant: vary the owner by pre-seeding `flake/nixarchy-apps.nix`
(`homeAppsTemplate` through `sed`, as case 8 does, with `alice`, `$(id -un)` or
a malformed variant) and `flake/nixarchy/home.nix`. Each case runs
`NIXARCHY_FLAKE=$PWD/flake "$apply" --yes --no-preview` on a fresh `flake/` in
a bash script (s1). `fhash` = `find flake -type f | sort | xargs sha256sum |
sha256sum`.

1. unowned + edited: claims; import(`$(id -un)`), copy equals the file.
2. unowned + seed: plain form, no `home-manager.users`, no `nixarchy/home.nix`
   (the seed does not claim).
3. owner applies: copy replaced by the new bytes. Owner applies the seed: copied
   (removal works).
4. non-owner, absent file: import(alice) and copy byte-identical.
5. non-owner, seed: same as 4.
6. non-owner, edited: rc != 0, stderr names alice and `--release-home`, `fhash`
   identical before and after. The fixture holds a stale `apps.nix` that differs
   from the caller's, so a refusal placed after the copy loop changes the hash.
7. malformed owner: two import lines (identical lines too), an unquoted
   `home-manager.users.alice.imports`: rc != 0, `fhash` identical. Positive:
   an indented line parses as owner, and the real generated file parses as
   exactly one owner.
8. `--release-home` by the owner: rc 0, copy and import both gone, plain form;
   a following apply with an edited file claims.
9. `--release-home` by a non-owner: refused with `fhash` identical while the
   owner's account exists; allowed when it is gone. `account_exists` is the
   seam: extract `home_decide`-adjacent functions and redefine `account_exists`
   after sourcing for the function-level cases; function-level cases cover
   all three answers: a status-2 result (confirmed absent) lets a non-owner
   release, and a lookup failure (the function pointed at a command that exits
   127, and another that exits 1) refuses with the lookup-failure message and
   no write; end to end, use a name that
   certainly has no account (`gone-1817`) for "gone" and `nobody`, with a
   precondition that `getent passwd nobody` succeeds in the sandbox, for
   "present".
10. pair-write failure: extract `write_home_pair` and define `replace_file`
    after sourcing so it delegates to the real one on the first call and fails
    on the second. Assert first that the first replacement happened (the copy
    changed on disk mid-run), then that after the failure both the copy and the
    generated file are byte-identical to the originals; and when there was no
    previous copy none is left. Removing the restore leaves the changed copy
    and fails the case; a test that fails the first call would not prove it.
11. `home_decide` table: every row, sourced with explicit arguments.
12. snapshot: function-level. Snapshot the caller's home.nix, then change the
    live file, then classify and copy; assert the classification and the copied
    bytes both match the snapshot, not the live file (use a live change that
    flips seed to edited, so classification differs too).

The #1809 three assertions (template) and Mode A (case 8 plain) are unchanged.

### Section 1 breaks

One per guard; prove each landed with `git diff`; restore with
`git checkout HEAD -- modules/apps.nix` from a committed baseline; failing
output goes in the PR.

| case | break |
|---|---|
| 1 | claim branch removed (unowned edited reads as keep) |
| 1/6 | refusal evaluated before the unowned claim |
| 2 | seed claims the host |
| 3 | owner's seed treated as no home part |
| 4, 5 | non-owner absent/seed falls to the plain form (the #1817 bug 2) |
| 5 | seed test never matches (seed treated as edited) |
| 6 | refusal moved after the copy loop |
| 7 | owner count taken after `sort -u`; or an unmatched candidate ignored |
| 8 | release removes only the import |
| 9 | account check always true, then always false |
| 10 | restore step deleted |
| 9 | lookup failure treated as absent (any nonzero = gone) |
| 12 | snapshot replaced by reading the live file (classification and copy) |

Not run locally here: nothing is built by this spec.

## Clarifications found in plan review (2026-11-16)

Approved text above is unchanged; these settle what it left open.

- **Release restores both files.** In "Pair write" step 4, "restore the backup
  copy" means both the copy and `$dest`. A release replaces `$dest` first, so if
  the removal of the copy then fails, restoring only the copy would leave an
  unowned `$dest` after a failed command. Step 2 therefore backs up both, and a
  failure restores both (write mode as well, harmlessly). `$applied` is untouched
  on failure. In release mode "update the copy's record" (step 5) means remove it.
  Verification gains a release-failure case: the removal step fails after `$dest`
  changed, and both files are byte-identical to the originals.
- **A release renders the post-release state once.** `--release-home` clears the
  owner, forces the home part to `keep` and renders the plain form for the
  generated file at the normal render point (after the copy loop, where
  `$imports` is known); it never re-renders the released owner and never writes
  `$dest` earlier. The same holds for the claim/copy pair write: it runs where
  `$imports` is known, so only the refusal and the release authorisation precede
  the copy loop.
- **Edited-in-flake protection stays for the home part.** The copy loop's rule
  (an edit made in the flake since the last apply is kept as a persistent
  `edited-in-flake` backup with a NOTE, not overwritten silently) applies to the
  home copy in the pair write, on a claim, an owner copy and a release. Verified
  by a case where the flake copy is edited and the next apply keeps the backup.
- **`--release-home` combinations.** With `--detach`, `--status` or `--log` it
  exits 2 before any unit starts or query runs, because the detached unit
  forwards only `--yes`, `--no-preview` and the expect flags and would otherwise
  run an ordinary apply. With `--expect-sha256 home=` the pin check runs first.
- **The validated name is the rendered one.** The user-name check (`:4757`)
  validates the name that will reach generated Nix (the caller for a
  claim/copy, the owner for a keep), checked after the decision.
- **Error handling.** Functions here must not rely on errexit: `set -e` is off
  inside a function called on the left of `||`, in `if`, or in `$(...)`, so each
  failing command carries an explicit `|| return`. `x=$(f) || exit 1` does not
  make errexit apply inside `f`.
- **Verification seams.** Function-level cases execute the production functions
  extracted from the script (`snapshot_home`, `read_owner`, `home_decide`,
  `account_exists`, `release_allowed`, `replace_file`, `remove_file`,
  `write_home_pair`), not copies. Case 9's "the function pointed at a command
  that exits 127 / 1" is a stub `getent` first on PATH, which exercises the real
  `account_exists`. Cases 3-5 pre-seed the home copy with non-seed bytes so a
  skipped copy cannot pass. Added cases: read_owner rejects a quoted invalid
  name, a release names the owner on stderr when refused, a release by the
  owner with an edited caller home.nix still copies the other four parts and
  does not claim, and `--release-home` with `--detach` is rejected.
- **Test ids.** The cases above are numbered 1-12 within this spec; the test
  file already uses 1-11, so the plan names them `own-N`.
