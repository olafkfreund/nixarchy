---
status: approved
issue: 1817
spec: spec/2026-11-16-1817-home-multiuser.md
coders:
  # Owner's rule: codex or agy write the code; agent-run agy cannot reach /mnt/data worktrees,
  # so agy gets inline text only and writes nothing here.
  1: codex  # small tricky shell logic (read_owner, home_decide, release_allowed) plus its tests
  2: codex  # tricky: snapshot, crash-safe pair write and restore, plus its tests
  3: codex  # wiring into apply, tricky ordering; retargets cases 8-11
  4: codex  # --release-home flag, reject rules, end-to-end tests
  5: codex  # docs, small
  # step 6 (section 1 breaks) is lead-only: builds, git, restores
reviewers:
  - codex  # reads the diff natively
  - agy    # independent model; given the diff inline
---

# Plan: one home owner per host (#1817)

Self-contained. Spec: `spec/2026-11-16-1817-home-multiuser.md` (approved, with
the intent's 2026-11-16 amendment). Anchors are `modules/apps.nix` at the base
of this branch and move as steps land; re-find them by the function names.

**Handoff rules for every step.** The coder must not commit, stage, deploy,
restart, build, format or print the environment, and edits only the files the
step names. The lead then runs the lead's checklist below, builds the verify
command, and commits one step per commit (agent-run needs a clean tree between
steps). Subject is a full sentence, no conventional prefix (CLAUDE.md s8). Name
the step in the commit body.

**Lead's checklist after each coder step** (never given to a coder): `nix fmt`
and read `git diff --stat` (a hook may reformat with nixpkgs-fmt, CLAUDE.md s5);
statix; `git add` the files (a flake sees only tracked files; the installer
checks also need a committed tree); then the step's verify command. Cheap tier
only, one build at a time under `flock /mnt/data/vmtest/codex-build.lock`.

## Approved decisions (from the spec)

All changes live inside `nixarchy-apply` (`modules/apps.nix`).
`homeAppsTemplateText` (`:408-431`), the seeding of `home.nix` (not in
`modules/home.nix`; it is the `homeTemplate` copy in `modules/apps.nix`, find it
with `grep -n 'home-template' modules/*.nix`) and the other four parts are
unchanged. `programs.nixarchy.user`
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
- snapshot: `snapshot_home` (below) copies `select_home_src`'s result to
  `$pinned/home.snap`. State is computed from, and the copy reads, the
  snapshot, so an editor change mid-apply cannot split classification from copy.
  The live path `$srcdir/home.nix` is named only inside `select_home_src` and
  `snapshot_home`; `classify_home` reads only `$home_snap`.

## Functions (production code the tests execute)

Every function is defined at top level of the script (one `name() {` at line
start, closing `}` at line start) so tests extract it with `sed -n
'/^name() {/,/^}/p' "$apply"` as `select_home_src` is (`tests/home-selection.nix`
case 10). Functions pass state through named globals, listed per function.
Tests source the extracted production functions, set the globals, call, and
break by mutating these same functions; nothing is re-implemented in a test.

**Error handling rule (replaces the old "x=$(f) || exit 1" advice, which is
wrong).** `set -e` is off inside any function called on the left of `||`, inside
`if`/`!`/`&&`, and inside `$(...)` (no `inherit_errexit`); `x=$(f) || exit 1`
therefore does not make errexit apply inside `f`. So every function here puts an
explicit `|| return 1` (or `|| { cleanup; return 1; }`) on EVERY command that can
fail, and never relies on errexit. Call them as plain statements, or with an
explicit `|| exit 1` (safe, because the function's own propagation is explicit);
the tests run with errexit off and so exercise exactly that. Under `set -u`,
every global a function reads is set before the first call.

- `valid_user <name>` (exists, `:4750`).
- `select_home_src` (exists): prints the pinned or live path, or nothing.
- `snapshot_home <template>`: globals read `srcdir`, `pinned`; sets `home_snap`
  (`$pinned/home.snap`, or empty when there is no home.nix), `home_state`
  (`absent|seed|edited`) and `home_srcmsg` (`$srcdir/home.nix`, for messages).
  Calls `select_home_src`; when its result is non-empty, `cp` it to the snapshot
  (guarded: no `cp` of an empty name). It does not classify.
- `classify_home <template>`: global read `home_snap`; sets `home_state` from
  the SNAPSHOT only: empty `home_snap` or `[ ! -f ]` is absent (never `-s`, so a
  zero-byte file is edited), `cmp -s "$home_snap" "$1"` is seed, else edited.
  Separate from `snapshot_home` so own-12 can change the live file between the
  two calls. The caller passes `${homeTemplate}`, the store path (a test passes
  its own template file).
- `read_owner`: global read `dest`; sets global `owner` (name, or empty). Missing
  `$dest` or no candidate: empty, return 0. Malformed, or a name failing
  `valid_user`: message naming `$dest` on stderr, return 1. Rules:
  - Candidates: lines matching `^[[:space:]]*home-manager\.users\.` (any indent).
    The template's other tokens (`options.home-manager.users.definitionsWithLocations`,
    `d.value ? "@USER@"`, `config.users.users."@USER@"`) do not start a line so.
  - Exact form: `^[[:space:]]*home-manager\.users\."<name>"\.imports[[:space:]]*=`
    with `<name>` one or more non-quote characters, counted with `grep -c` BEFORE
    any dedup (two identical lines are two).
  - Count 1 and every candidate matched the exact form: owner `<name>`, which
    must pass `valid_user` because it is read back from a file.
  - Count 0 and no candidate: unowned. Anything else (count above 1, a candidate
    not in exact form such as an unquoted or empty name): refuse. Malformed
    never reads as unowned.
  - Malformed message: `nixarchy-apply: <dest> names several home owners (or an
    unparseable one); fix it by hand`.
  - Trap: `grep -c` exits 1 on count 0; capture with `n=$(grep -c ... || true)`
    on that one call and read the count, not the status.
- `home_decide <owner> <caller> <state>`: pure, prints one word, no failing
  command. `claim` (render and copy; caller becomes owner), `copy` (owner
  replaces their copy), `keep` (no home part from the caller: copy nothing;
  re-render the owner's import if there is one, else the plain form), `refuse`.
  Order matters: unowned claim is evaluated BEFORE the non-owner refusal.

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
- `account_exists <name>`: runs `getent passwd "$1" >/dev/null 2>&1` and returns
  its status unchanged (0 exists, 2 confirmed absent, anything else is a lookup
  failure). Resolves `getent` through PATH, so a test puts a stub first.
- `release_allowed <owner> <caller>`: returns 0 when allowed, 1 after printing
  the reason to stderr. Caller = owner: allowed. Otherwise `rc=0;
  account_exists "$1" || rc=$?`: 0 refuses (`nixarchy-apply: home.nix belongs to
  <owner>, who still has an account; only <owner> can release it`); 2 is allowed;
  any other status refuses with `nixarchy-apply: cannot tell whether <owner>
  still has an account (getent exited <n>); not releasing`. Only confirmed
  absence lets a non-owner release. Add `pkgs.getent` to `nixarchy-apply`'s
  `runtimeInputs` (`:4391`; it evaluates, `getent-glibc-2.44-57`; fallback
  `pkgs.glibc.bin`); an undeclared getent is 127, which refuses.
- `replace_file <src> <dst>`: the existing `copy_into_flake` (`:4671`, temp in
  `$base`, `chmod --reference`, `mv`) under the spec's name; delete
  `copy_into_flake` and point its two callers at it. Add `|| return 1` to its
  `mktemp`. Atomic because the temp is in `$base`, the same filesystem as every
  destination (`$base/nixarchy/` and `$dest`).
- `remove_file <path>`: `rm -f -- "$1" || return 1`; its own function only so a
  test can fail the removal step of a release.
- `restore_one <bak> <dst>`: if `<bak>` exists, `cp -p` it over `<dst>`; else
  `rm -f <dst>` (it did not exist before). Never calls `replace_file`.
- `write_home_pair <write|release> <rendered-dest>`: globals `base`, `dest`,
  `pinned`, `applied`, `home_snap`, `home_srcmsg`, `copied` (appended to).
  `<rendered-dest>` is the already rendered generated file (a temp file), so the
  function writes, never renders. The copy is `$base/nixarchy/home.nix`.
  1. `rm -f $pinned/home.bak $pinned/dest.bak`, then back up BOTH the current
     copy and the current `$dest` (`cp -p`; a missing file leaves no backup).
  2. Edited-in-flake protection, carried from the copy loop (`:4787`): when the
     copy exists, `$applied/<sha-of-path>` record exists and `sha256sum <copy>`
     differs from it, `cp` the copy to `$applied/home.nix.edited-in-flake.<ts>`
     (persistent, not in `$pinned`) and print the NOTE naming `$home_srcmsg`.
     Release does this too: it deletes the copy.
  3. `write`: if the copy exists and is byte-identical to `$home_snap`, skip
     the copy write (the loop's "already up to date" rule); otherwise
     `replace_file "$home_snap" copy` first, `replace_file "<rendered-dest>"
     "$dest"` second, and add ` home` to `copied` when the copy was written.
     The `$applied` record is refreshed (in both branches) only AFTER the
     `$dest` replacement succeeds, so a failure leaves `$applied` untouched. `release`: `replace_file "<rendered-dest>" "$dest"` first, then
     `remove_file` of the copy. Each call is `... || { restore_one
     "$pinned/home.bak" copy; restore_one "$pinned/dest.bak" "$dest"; return 1; }`.
  4. On any failed step, BOTH the copy and `$dest` are restored (a release has
     already replaced `$dest` when the removal fails, so restoring only the copy
     would leave an unowned `$dest`); return 1; the previous pair remains and
     `$applied` is untouched.
  5. Only after success: `write` stores `sha256sum <copy>` in the record;
     `release` removes the record.
  Crash safety is by write order: no interruption leaves an import pointing at a
  missing file or another user's file; worst case an unimported orphan copy,
  rewritten or removed by the next apply or release.

## Wiring in `nixarchy-apply`

- **Flags** (`:4424`): `--release-home` sets `release_home=1`, in the usage text
  (`:4448`). Right after the parse loop, before any query or the detach block:
  `--release-home` together with `--detach`, `--status` or `--log` exits 2 with
  `nixarchy-apply: --release-home cannot be combined with --detach, --status or
  --log`. Not forwarded: the detach unit forwards only `--yes --no-preview` and
  the expect flags (`:4619`), so forwarding would silently run an ordinary
  apply. `--expect-sha256 home=` with `--release-home` is allowed; the pin check
  runs first and a mismatch exits 4 before anything is written.
- **Placement, after the pins and `valid_user` (`:4750`):**
  `snapshot_home`; `classify_home ${homeTemplate}`; `user=$(id -un)`; `read_owner`; then
  - normal: `home_action=$(home_decide "$owner" "$user" "$home_state")`;
    `refuse` prints the refusal and `exit 1` before the copy loop (flake and pins
    untouched);
  - `--release-home`: owner empty prints `no home owner; nothing to release` and
    exits 0; `release_allowed "$owner" "$user" || exit 1`; then
    `released=$owner`, `owner=""`, `home_action=release` (the caller's home.nix
    is ignored and never claims in this run). The post-release state is what is
    rendered: owner empty, home forced to keep, no import.
  - `render_user`: `claim`/`copy` give `$user`; `keep` with an owner gives
    `$owner`; otherwise empty (plain form, Mode A unchanged).
  - Name check: `if [ -n "$render_user" ] && ! valid_user "$render_user"; then`
    (the name that will reach generated Nix; the old line checked `$user`, the
    wrong variable once the owner can differ from the caller).
- **Copy loop** (`:4762`): `for part in apps services advanced flatsnap`; delete
  the `home` branches (`src="$home_src"`, `[ "$part" != home ]`); `copy_into_flake`
  calls become `replace_file`.
- **One writer for `$dest`, after the loop** (`:4826`), where `$imports` is
  already known (this is the answer to "where is `$imports` known": the pair
  write is NOT at `:4754-4760`; only the refusal and the release authorisation
  are before the loop). The render block renders to `$tmp` as now, using
  `render_user` in place of `user`/`home_src` (template branch when
  `render_user` is non-empty, plain branch otherwise). Then:
  `home_action` in `claim|copy` runs `write_home_pair write "$tmp" || exit 1`;
  `release` runs `write_home_pair release "$tmp" || exit 1` and prints
  `released home.nix from <owner>`; anything else keeps the existing `chmod` and
  `mv`. `$dest` is therefore written once, in every mode. In every mode that
  replaces `$dest` the `chmod --reference` stays (`replace_file` does it).
- Messages go to stderr (not the "released" line).
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

Traps for every coder handoff: this is Nix `''` text, so write shell `${` as
`''${` and never write a heredoc inside it (use `printf '%s\n'`); the error
handling rule above (explicit `|| return 1` on every failing command in every
function, no `x=$(f) || exit 1` reliance); every function at top level with
`name() {` and `}` at line start; the script runs under `set -o errexit
-o nounset -o pipefail` (writeShellApplication), so every global is set before
use; read the `AGENTS.md` of the directory you edit. Nothing in a handoff asks a
coder to stage, format or build.

Test file conventions (`tests/home-selection.nix`, a bash script under `set +e`,
so `bad` counts failures): add `getent` to its `nativeBuildInputs`; a helper
`extract() { sed -n "/^$1() {/,/^}/p" "$apply"; }` writes the production
functions into one file, sourced once (`valid_user select_home_src
snapshot_home classify_home read_owner home_decide account_exists release_allowed
replace_file remove_file restore_one write_home_pair`; an empty extraction is a
`bad`). Function-level cases set the globals the function lists, call it, and
read results; a stub `getent` is a script first on PATH (`exit "$GETENT_RC"`),
because sourced functions do not get the wrapper's `runtimeInputs` PATH and
`getent` may be absent from the sandbox. New case ids are `own-1` ... `own-16`
in `bad` (the file's existing 1-11 are kept and never reused). Fixtures:
`fresh_flake` removes `flake/` and `$XDG_STATE_HOME/nixarchy/applied`, recreates
`flake/flake.nix`; `owned_flake <owner> <copy-bytes>` calls `fresh_flake`, writes
`flake/nixarchy-apps.nix` (`homeAppsTemplate` through `sed`) and
`flake/nixarchy/home.nix`. The pre-seeded copy is ALWAYS distinct non-seed bytes
(for example `# previous owner bytes`), never `homeTemplate`: a copy equal to the
seed would make "owner's seed treated as none" pass (own-3). `fhash` = `find
flake -type f | sort | xargs sha256sum | sha256sum`.

1. **Decision functions and their tests.** `read_owner`, `home_decide`,
   `account_exists`, `release_allowed`, beside `valid_user` (`:4750`), not yet
   called; `pkgs.getent` in `runtimeInputs`. Tests, function level, in
   `tests/home-selection.nix`: own-7a (read_owner: one line, an indented line,
   the real generated file from `homeAppsTemplate` parses as exactly one owner;
   two lines, two identical lines, an unquoted name, a quoted `"-bad"` and an
   empty `""` name refuse and leave `owner` unset), own-11 (every `home_decide`
   row, explicit arguments), own-9a (`release_allowed` through the real
   `account_exists` with a stub getent returning 0 -> refused naming the owner on
   stderr; 2 -> allowed; 127 and 1 -> refused with the lookup message; caller =
   owner -> allowed with no getent call). Verify: build `home-selection`.
2. **Snapshot and pair write, and their tests.** `snapshot_home`,
   `replace_file` (rename of `copy_into_flake`, both callers updated), `remove_file`,
   `restore_one`, `write_home_pair`; not yet called from the apply flow except
   the renamed `replace_file`. Update case 10's static grep to the new shape: the
   count of `$srcdir/home.nix` outside `select_home_src` and `snapshot_home`
   (delete both bodies with sed, then `grep -cF`) must be 0 and the unmodified
   file's count must be at least 1. Tests, function level: own-12 (`snapshot_home`
   with the live file equal to the template, then change the live file so it
   is edited (and the pinned file too, when pinned), THEN `classify_home`;
   `home_state` must be `seed`, and the bytes `write_home_pair write` puts in
   the copy must equal the snapshot-time content); own-10 (stub
   `replace_file` after sourcing: real on the first call, fail on the second;
   assert the copy changed on disk after the first, then after the failure copy
   and `$dest` are byte-identical to the originals, `$applied` record unchanged;
   with no previous copy, none is left); own-14 (release: `remove_file` stub
   records whether `$dest` already changed and fails; assert `$dest` was changed
   at that moment, then both copy and `$dest` restored byte-identical, record
   unchanged); own-16a (copy edited in the flake since the record: after a
   successful `write` and after a successful `release`, `$applied/home.nix.
   edited-in-flake.*` holds the edited bytes and the NOTE was printed; the
   record matching: no backup, no NOTE). Verify: build `home-selection`.
3. **Wire into apply (behaviour change; retarget in this step).** As in
   "Wiring" except the flag handling: snapshot, owner, decision, refusal before
   the loop, `home` out of the loop, one writer after the loop, `render_user`
   and its name check. In the same step: add `fresh_flake`; case 8 "with home"
   writes an edited file (`sed -i '/#@pkgs-end/i\    hello  #@pkg hello'` as
   case 6 does) so it claims, expected file stays the template with `@USER@` =
   `$(id -un)`; "without home" calls `fresh_flake` first; case 9 reuses case 8's
   flake (order kept); case 11's static grep becomes `if [ -n "$render_user" ]
   && ! valid_user "$render_user"; then`; other `valid_user` assertions kept.
   End-to-end cases: own-1 (unowned + edited claims: import(`$(id -un)`), copy
   equals the file); own-2 (unowned + seed: plain form byte-identical to case 8's
   `plain.expected`, no `home-manager.users`, no `nixarchy/home.nix`; this and
   case 8 "without home" are the Mode A proof); own-3 (owner applies new bytes:
   copy replaced; owner applies the seed: copied, pre-seed copy is non-seed);
   own-4 (non-owner absent: import(alice) and copy byte-identical); own-5
   (non-owner seed: same); own-6 (non-owner edited: rc != 0, stderr names alice
   and `--release-home`, `fhash` equal; fixture carries a stale `apps.nix`
   differing from the caller's so a refusal after the copy loop changes the
   hash); own-7b (malformed owner flake files: two lines, two identical lines,
   unquoted, quoted `"-bad"`: rc != 0, `fhash` equal); own-16b (end to end: owner
   edits `flake/nixarchy/home.nix` after a successful owner apply, applies
   again: rc 0, copy replaced by the source, `$applied/home.nix.edited-in-flake.*`
   keeps the edit). Verify: build `home-selection`, green at this commit.
   Trap: the unowned claim is tested before the refusal.
4. **`--release-home`.** Flag, usage, the reject rule, owner-empty exit 0,
   `release_allowed`, `home_action=release` with `owner=""`, and the `release`
   branch of the single writer. End-to-end cases: own-8 (release by owner: rc 0,
   stdout names the owner, copy and import gone, plain form; a following edited
   apply claims); own-9b (non-owner release refused with `fhash` equal and stderr
   naming the owner while `nobody` exists, with a precondition that
   `getent passwd nobody` succeeds that fails the case loudly; allowed for
   `gone-1817`); own-13 (release by the owner while the caller has an edited
   `home.nix` and a changed `apps.nix`: rc 0, the other four parts are copied,
   the edited home.nix does not claim, no import, no copy); own-15
   (`--release-home` with `--detach`, `--status` and `--log`: rc 2, `fhash`
   equal, no unit started because the check precedes it). Verify: build
   `home-selection`. Trap: a lookup failure (status other than 0 or 2) refuses
   and writes nothing.
5. **Docs.** `docs/manual/configuration.md` (the `nixarchy-apply` section at
   `:514`; `grep -rn 'nixarchy/home.nix' docs/` found no page naming it at the
   base, use one if it exists): the owner is whoever the flake names;
   `programs.nixarchy.user` does not affect it; claiming; the refusal text;
   `--release-home` (owner, or anyone once the owner's account is gone; not
   combinable with `--detach`); removal by applying the empty module; the
   zero-byte note. `modules/AGENTS.md`: one paragraph for the owner model, why
   `programs.nixarchy.user` is not read (deadlock, race), and the errexit rule
   above (general, would bite others). `tests/AGENTS.md`: a sentence only if a
   hole is named (real account lookup differs from the sandbox; concurrent
   applies untested). Check `docs/AGENTS.md`'s manual lists and
   `readme-counts.sh` only if a page is added (none expected). Verify: the
   docs/readme-counts checks the lead names after `generated-checks.sh` runs.
6. **Section 1 breaks (LEAD ONLY; builds, git and restores).** After steps 1-5
   are committed and `home-selection` passes. Commit a known-good baseline
   first; restore with `git checkout HEAD -- modules/apps.nix`. For each break:
   apply, prove it landed with `git diff`, build `home-selection`, save the
   failing output, restore, watch it pass. Cheap tier, one at a time under
   `flock /mnt/data/vmtest/codex-build.lock`. Breaks (cases that must fail):
   - own-1: claim branch removed; own-1/own-6: refusal evaluated before the
     unowned claim; own-2: seed claims; own-3: owner's seed treated as none;
   - own-4, own-5: non-owner absent/seed falls to the plain form; own-5: seed
     test never matches; own-6: refusal moved after the copy loop;
   - own-7a/own-7b: count after `sort -u`, an unmatched candidate ignored, and
     `valid_user` omitted from `read_owner`;
   - own-8: release removes only the import; own-8: owner not cleared on release
     (the released owner is re-rendered); own-13: release skips the other four
     parts, and release lets an edited caller claim;
   - own-9a/own-9b: `release_allowed` always allows, then always refuses;
     `account_exists` maps every nonzero status to 2; lookup failure treated as
     absent;
   - own-10: restore deleted; the record refreshed before the `$dest`
     replacement (in either branch); own-14: release restores only the copy (not `$dest`);
   - own-12: `classify_home` reads the live file instead of `$home_snap`, and
     separately `write_home_pair` copies the live file; own-15: reject rule removed; own-16a/own-16b: the
     edited-in-flake backup removed from `write_home_pair`.
   The failing output goes in the PR (template section). Then the lead runs
   every `generated-checks.sh` target plus claimed checks touching these files,
   by the s6 tier, `options-*` shards included when no runner is busy.

## Tests

`tests/home-selection.nix`: existing cases 1-7 untouched; 8-9 and 11 retargeted
in step 3 and 10's grep in step 2 (each step leaves the check green); new cases
`own-1` ... `own-16` as listed (the spec's 1-12 map to own-1 ... own-12; own-13
to own-16 are the review additions). Mode A is existing case 8 "without home"
plus own-2, both byte-identical to the plain form. Function-level cases run the
extracted production functions with errexit off; end-to-end cases run the
built `nixarchy-apply`. `options-*` shards unchanged in text (the template is
unchanged) and run by the lead. Not run locally: the `install` job.

## Rollback

Revert the step commits (the change is confined to `modules/apps.nix`, the
test, docs). A host flake written by the new apply is valid for the old apply:
it holds the same generated file and `nixarchy/home.nix` shapes, so no migration
is needed. An orphan `nixarchy/home.nix` left by an interrupted release is
harmless and removed by the next apply or release.
