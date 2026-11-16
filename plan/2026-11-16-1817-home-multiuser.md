---
status: draft
issue: 1817
spec: spec/2026-11-16-1817-home-multiuser.md
coders:
  # Owner's rule: codex or agy write the code; agent-run agy cannot reach /mnt/data worktrees,
  # so agy gets inline text only and writes nothing here.
  1: codex  # small tricky shell logic (read_owner), no build needed
  2: codex  # small tricky shell logic (home_decide, account_exists)
  3: codex  # tricky: crash-safe write order and restore
  4: codex  # wiring into apply, tricky ordering against the copy loop
  5: codex  # flag parsing plus release path, small
  6: codex  # edits existing cases, small tricky
  7: codex  # new cases 1-12, small tricky logic
  8: codex  # docs, small
  # step 9 (section 1 breaks) is lead-only: builds, git, restores
reviewers:
  - codex  # reads the diff natively
  - agy    # independent model; given the diff inline
---

# Plan: one home owner per host (#1817)

Self-contained. Spec: `spec/2026-11-16-1817-home-multiuser.md` (approved, with
the intent's 2026-11-16 amendment). Anchors are `modules/apps.nix` at the base
of this branch and move as steps land; re-find them by the function names.

**Handoff rules for every step.** The coder must not commit, stage, deploy,
restart or build, and must not print the environment. The lead builds the
verify command, then commits one step per commit (agent-run needs a clean tree
between steps). Subject is a full sentence, no conventional prefix (CLAUDE.md
s8). Name the step in the commit body.

## Approved decisions (from the spec)

All changes live inside `nixarchy-apply` (`modules/apps.nix`).
`homeAppsTemplateText` (`:408-431`), `modules/home.nix` seeding
(`:1408-1410`) and the other four parts are unchanged. `programs.nixarchy.user`
is not read; nothing about ownership is baked in.

**Terms.**
- seed: caller's home.nix byte-identical to `${homeTemplate}` (`:400`), by
  `cmp -s` against the store path (not `/etc/nixarchy/home-template.nix`).
- edited: exists and differs from the template. One definition everywhere.
  A zero-byte file is edited (owner's is copied, the build fails loudly; the
  manual says so).
- state: `absent | seed | edited`.
- owner: the one user named by the existing `nixarchy-apps.nix` (`$dest`), or
  empty. Nothing else makes an owner.
- snapshot: right after `select_home_src` (`:4740`), `cp` its result to
  `$pinned/home.snap`. State is computed from, and the copy reads, the
  snapshot, so an editor change mid-apply cannot split classification from copy.

**`read_owner`** (after `user=$(id -un)`, `:4756`; only if `[ -f "$dest" ]`).
Prints owner or nothing; exit 1 with a message naming `$dest` on malformed state.
- Candidates: lines matching `^[[:space:]]*home-manager\.users\.` (any indent).
  The template's other tokens (`options.home-manager.users.definitionsWithLocations`,
  `d.value ? "@USER@"`, `config.users.users."@USER@"`) do not start a line so.
- Exact form: `^[[:space:]]*home-manager\.users\."<name>"\.imports[[:space:]]*=`,
  counted with `grep -c` BEFORE any dedup (two identical lines are two).
- Count 1 and every candidate matched the exact form: owner `<name>`, which
  must pass `valid_user` (`:4750`) because it is read back from a file.
- Count 0 and no candidate: unowned.
- Anything else (count above 1, or a candidate not in exact form, e.g. an
  unquoted name): refuse. Malformed never reads as unowned.
- Malformed message: `nixarchy-apply: <dest> names several home owners (or an
  unparseable one); fix it by hand`.

**`home_decide`**: a named top-level shell function, extractable by tests like
`select_home_src`. Inputs `owner` (name or empty), `caller`, `state`. Output one
word: `claim` (render and copy; caller becomes owner), `copy` (owner replaces
their copy), `keep` (no home part from the caller: copy nothing; re-render the
owner's import if there is one, else the plain form), `refuse`. Order matters:
unowned claim is evaluated BEFORE the non-owner refusal.

| owner | caller | state | output |
|---|---|---|---|
| empty | any | edited | claim |
| empty | any | seed or absent | keep (plain form) |
| O | O | seed or edited | copy |
| O | O | absent | keep |
| O | C | absent or seed | keep (import(O) and copy byte-identical) |
| O | C | edited | refuse |

A seed never claims and never refuses. The owner's own file is always copied,
seed included (how the owner applies an empty module and removes packages).

**`account_exists "$1"`**: its own function (tests redefine it). Runs
`getent passwd "$1"` and maps status to THREE answers: 0 exists; 2 confirmed
absent; any other status (127, 1, 3, ...) is a lookup failure that REFUSES the
release with `nixarchy-apply: cannot tell whether <owner> still has an account
(getent exited <n>); not releasing`. Only confirmed absence lets a non-owner
release. Add `pkgs.getent` to `nixarchy-apply`'s `runtimeInputs` (`:4391`);
it evaluates (`getent-glibc-2.44-57` confirmed on this branch's nixpkgs);
fallback `pkgs.glibc.bin`. An undeclared getent would be 127, which the rule
turns into a refusal, never a wrong "gone".

**`--release-home`**: parsed with the other flags (`:4424`), takes the lock like
any apply. After `read_owner`:
- owner empty: print `no home owner; nothing to release`, exit 0.
- allowed when caller = owner, or `account_exists "$owner"` says confirmed
  absent. Otherwise refuse (exit 1) naming the owner, before any write.
- allowed: render the plain form for the generated file, do the pair write with
  no copy and the import removed. The run then continues as an ordinary apply
  of the other four parts with the home part forced to `keep`; the caller's
  edited home.nix does NOT claim in the same run. Print which owner was released.

**`write_home_pair`** (the copy `$base/nixarchy/home.nix` and `$dest` change
together):
1. Render both to temp files first (new copy from the snapshot; generated file
   through the existing template/plain branches, `@USER@` = `render_user`,
   validated). Nothing in the flake has changed yet.
2. Back up the current copy to `$pinned/home.bak` (or note it was absent).
3. Replace through a named `replace_file <src> <dst>` (temp file `mv`d, atomic):
   - result HAS an import (claim, owner copy): home copy first, `$dest` second;
   - result REMOVES the import (`--release-home`): `$dest` first, then remove
     the copy.
4. On a failed step: restore the backup copy (or remove a copy that did not
   exist before) and exit non-zero; the previous pair remains.
5. Only after success, update the copy's record in `$applied`.
Crash safety is by write order: no interruption leaves an import pointing at a
missing file or another user's file; worst case an unimported orphan copy,
rewritten or removed by the next apply or release.

**Wiring.** `home` leaves the copy loop (`:4762`); the other four parts keep
it. Render choice at `:4828`: template branch when the output is `claim`/`copy`,
or `keep` with an owner (`render_user` = owner); the plain branch
(`:4833-4840`) only when unowned and nothing to copy, which keeps Mode A
byte-identical. Owner parse, snapshot, state and decision sit at `:4754-4760`,
before the copy loop; the only earlier effects are `mkdir -p`, the lock and the
pin snapshots (a pin mismatch still exits 4 first, `:4714`). A `refuse` leaves
flake and pins untouched. The user-name check (`:4757`) is gated on "a name
will reach generated Nix": a `claim`/`copy` caller or a non-empty owner.
Messages go to stderr.
- Refusal: `nixarchy-apply: home.nix belongs to <owner>; <caller> has edited
  theirs. Ask <owner> to apply, or run nixarchy-apply --release-home to give
  the host up.`

**Mode A**: no home files anywhere gives a byte-identical `nixarchy-apps.nix`.
**Coexistence (s14)**: no new option or merged-env contribution; no fixture.
**Out of scope**: access control; concurrent applies (no cross-user lock);
last-writer-wins on apps/services/advanced/flatsnap; per-user home selections;
automatic release when the owner's account is gone; `programs.nixarchy.user` as
owner. `valid_user` unchanged. #1809's three failure assertions unchanged.

**Rejected alternatives (do not reintroduce):** `programs.nixarchy.user` as
owner (baked in, deadlocks, races); per-user `home-<user>.nix`; automatic
release; comparing against `/etc/nixarchy/home-template.nix`; "seed counts as
no home part for everyone" (breaks owner removal).

## Steps

Common traps for steps 1-5 (put in every handoff): this is Nix `''` text, so
write shell `${` as `''${` and never write a heredoc inside it (use `printf
'%s\n'`); `set -e` does not reach inside `$(...)` or inside `if`/`!`/`&&`
conditions, so call the function as a plain statement (or `x=$(f) || exit 1`) so
errexit applies; run `nix fmt` and read `git diff --stat` (a hook may reformat
with nixpkgs-fmt, CLAUDE.md s5), then statix; a flake sees only git-added files
(`git add` before building); `installer/mkFlake.nix` needs a committed tree.
Every function defined at top level of the script, one per line start `name() {`
and closing `}` at that same indent, so `sed -n '/^name() {/,/^}/p'` extracts
it as `select_home_src` is (`tests/home-selection.nix:172`).

1. **`read_owner` (function only, not yet called).** In `modules/apps.nix`
   beside `valid_user` (`:4750`). Rules as above. Verify:
   `nix build .#checks.x86_64-linux.home-selection` still passes (function
   unused); tests for it land in step 7. Traps: `grep -c` exits 1 on count 0,
   so guard it (`|| true` on that one call only) and read the count, not the
   status; the name capture must use sed/bash regex on the exact form only.
2. **`home_decide` and `account_exists` (functions only).** Same area. Table
   and three-answer exit mapping as above; `account_exists` returns the getent
   status unchanged (0, 2, or other) so a caller can distinguish; add
   `pkgs.getent` to `runtimeInputs` (`:4391`, alphabetical with its neighbours).
   Verify: `nix eval --raw .#checks.x86_64-linux.home-selection.drvPath`, then
   build `home-selection`. Trap: do not call `account_exists` inside `if`
   without capturing the status (`rc=0; getent ... || rc=$?`).
3. **`replace_file` and `write_home_pair` (functions only).** Same area. Order
   by result kind, backup to `$pinned/home.bak`, restore on failure, `$applied`
   record updated last. Verify: build `home-selection`. Trap: restore must run
   when the SECOND replacement fails and must undo the first; do not let
   `set -e` abort before the restore (use `|| { restore; exit 1; }`).
4. **Wire into apply.** At `:4740-4760` and `:4762-4840`: snapshot to
   `$pinned/home.snap`; compute state with `cmp -s` against `${homeTemplate}`;
   `read_owner`; `home_decide`; on `refuse` print the refusal and `exit 1`
   before the copy loop; drop `home` from the loop; call `write_home_pair`
   for `claim`/`copy`; pick the render branch as specified; gate the user check
   (`:4757`) on claim/copy or non-empty owner. Verify: build `home-selection`
   (cases 8-11 are retargeted in step 6, so expect the old case-8 and case-11
   failures until then; read them, do not "fix" the product).
   Trap: the unowned claim is tested before the refusal.
5. **`--release-home`.** Flag in the `case` at `:4424`, usage text at `:4448`
   (also the `--detach` forward list near `:4619` if flags are forwarded; a
   release is never detached-forwarded unless the code already forwards by
   word, check with `grep -n -- '--yes --no-preview' modules/apps.nix`). After
   `read_owner`: the three outcomes above, then `write_home_pair` in release
   mode, then continue with the home part forced `keep`. Verify: build
   `home-selection`. Trap: a lookup failure (status other than 0 or 2) refuses
   with the lookup-failure message and writes nothing.
6. **Retarget existing cases in `tests/home-selection.nix`.** Case 8 "with
   home": write an edited file (added package line); expected file stays the
   template with `@USER@` = `$(id -un)`. Add a `fresh_flake` helper; case 8 and
   9 keep their order and case 9 reuses case 8's flake. Case 11: retarget the
   static grep for `if [ -n "$home_src" ] && ! valid_user "$user"; then` to the
   new gate. Cases 10 and the `valid_user` cases unchanged. Verify: build
   `home-selection`. Trap: the check runs under bash as a script (s1); pipes
   hide statuses, use `set -o pipefail`.
7. **New cases 1-12** (names are spec's, renumber the file's `bad N` ids
   to avoid collision with 8-11). Ownership varies through the flake: pre-seed
   `flake/nixarchy-apps.nix` (`homeAppsTemplate` through `sed`) and
   `flake/nixarchy/home.nix`; run `NIXARCHY_FLAKE=$PWD/flake "$apply" --yes
   --no-preview` on a fresh flake. `fhash` = `find flake -type f | sort | xargs
   sha256sum | sha256sum`.
   1 unowned+edited claims. 2 unowned+seed stays plain, no copy. 3 owner
   applies (new bytes; seed copied). 4 non-owner absent keeps. 5 non-owner seed
   keeps. 6 non-owner edited: rc != 0, stderr names alice and `--release-home`,
   `fhash` equal; the fixture carries a stale `apps.nix` differing from the
   caller's, so a refusal after the copy loop changes the hash. 7 malformed
   owner (two import lines, two identical lines, unquoted name): rc != 0,
   `fhash` equal; positives: indented line parses; the real generated file
   parses as exactly one owner. 8 `--release-home` by owner: both gone, plain
   form; a following edited apply claims. 9 non-owner release: refused with
   `fhash` equal while the account exists; allowed when gone; function-level
   `account_exists` redefined after sourcing for status 2 (allowed), 127 and 1
   (refused with the lookup message, no write); end to end `gone-1817` is gone,
   `nobody` present, with a precondition that `getent passwd nobody` succeeds.
   10 pair-write failure: extract `write_home_pair`, define `replace_file` to
   delegate to the real one on the first call and fail on the second; assert
   the copy changed on disk after the first replacement, then that both files
   are byte-identical to the originals; with no previous copy none is left.
   11 `home_decide` table, every row, explicit arguments. 12 snapshot:
   snapshot, then change the live file (flipping seed to edited), then classify
   and copy; both match the snapshot. Verify: build `home-selection`. Trap:
   getent in the build sandbox may lack `nobody`; the precondition must fail
   the case loudly, not skip it.
8. **Docs.** `docs/manual/configuration.md` (the `nixarchy-apply` section at
   `:514`; no page currently names `nixarchy/home.nix`, confirm with `grep -rn
   'nixarchy/home.nix' docs/`, and if a page exists use it): the owner is
   whoever the flake names; `programs.nixarchy.user` does not affect it;
   claiming; the refusal text; `--release-home` (owner, or anyone once the
   owner's account is gone); removal by applying the empty module; the
   zero-byte note. `modules/AGENTS.md`: one paragraph for the owner model and
   why `programs.nixarchy.user` is not read (deadlock, race). `tests/AGENTS.md`:
   a sentence only if a hole is named (real account lookup differs from the
   sandbox; concurrent applies untested). Check whether `docs/AGENTS.md`'s
   manual lists, or `readme-counts.sh`, need a touch if a page is added (none
   expected). Verify: the docs/readme-counts checks the lead names after
   `generated-checks.sh` runs.
9. **Section 1 breaks (LEAD ONLY; builds, git and restores).** Run after steps
   1-8 are committed and `home-selection` passes. Commit a known-good baseline
   first; restore with `git checkout HEAD -- modules/apps.nix`. For each
   break: apply, prove it landed with `git diff`, build `home-selection`, save
   the failing output, restore, watch it pass. Under the cheap tier, one at a
   time under `flock /mnt/data/vmtest/codex-build.lock`. Breaks (case):
   1 claim branch removed; 1/6 refusal before the claim; 2 seed claims; 3
   owner's seed treated as none; 4,5 non-owner absent/seed falls to plain; 5
   seed test never matches; 6 refusal after the copy loop; 7 count after
   `sort -u`, and an unmatched candidate ignored; 8 release removes only the
   import; 9 account check always true then always false; 10 restore deleted;
   9 lookup failure treated as absent; 12 snapshot replaced by the live file.
   The failing output goes in the PR (template section). Then the lead runs
   every `generated-checks.sh` target plus claimed checks touching these
   files, by the s6 tier, `options-*` shards included when no runner is busy.

## Tests

`tests/home-selection.nix`: cases 8-11 retargeted, 12 new (the spec's 1-12),
all via the fixture's pre-seeded flake. `options-*` shards unchanged in text
(the template is unchanged) and run by the lead. Mode A is the plain-form
assertion in case 2. Not run locally: the `install` job.

## Rollback

Revert the step commits (the change is confined to `modules/apps.nix`, the
test, docs). A host flake written by the new apply is valid for the old apply:
it holds the same generated file and `nixarchy/home.nix` shapes, so no migration
is needed. An orphan `nixarchy/home.nix` left by an interrupted release is
harmless and removed by the next apply or release.
