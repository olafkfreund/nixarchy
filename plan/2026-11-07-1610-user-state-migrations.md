---
status: draft
issue: 1610
spec: spec/2026-11-07-1610-user-state-migrations.md
coders:
  1: codex   # small, tricky logic: ordered IPC moves, id-checked indexes, marker-on-proof polling
  2: coder   # two small edits in files with established patterns (home.nix hook, options.nix pair)
  3: agy     # large mechanical edit: 96 ledger rows copied from a fixed decision table
  4: coder   # prose and two ledger rows; needs judgement about wording, not logic
  5: codex   # tricky test logic: a stub that must mirror the shell's IPC semantics exactly, plus the oracle normalisation
  6: coder   # small check comparing a grep result with a Nix attrset
  7: coder   # one VM test block beside an existing, similar one
reviewers:
  - codex    # reads the code it names and can run read-only greps against the pinned source
  - agy      # independent read of the plan text against the spec; different model, different blind spots
---

# Plan: Omarchy 4.5's changes to a user's own files reach machines installed before it

## What this does, and the decisions it carries

A machine installed on Omarchy v4.0.x has a `~/.config/omarchy/shell.json`
seeded from v4.0.6: `bar.centerAnchor = "omarchy.clock"`, `center =
[indicators, clock, keyboard-layout, weather, system-update]`, one
`omarchy.tray` first in `right`, no Elsewhen. The v4.5.0 shell ignores
`centerAnchor`, so the clock is no longer centred and Elsewhen never appears.
Upstream fixes this with three migrations nixarchy never runs. This plan ports
those three, records a decision for every other migration that touches user
files, and stops a future bump from forgetting.

Decisions (approved in the spec, plus the owner's answers to its open
questions). Do not reopen any of them during implementation:

1. **Scope: the bar only.** Port `1790042972` (Elsewhen after the clock),
   `1791968925` (tray order) and `1791969355` (centre split), in that order.
   Every other triage hit gets a ledger row in `data/user-migrations.nix`.
2. **Where: a `post-boot.d` hook that waits for the shell and changes the
   layout only through its IPC** (`omarchy-shell shell putBarWidget` /
   `moveBarWidget`). Never write `shell.json` (#847; `build.yml` step
   "Nothing we ship writes shell.json"). Not activation, not before the shell
   starts, not upstream's scripts with a stubbed `mv`.
3. **Marker: upstream's own path and name**,
   `${OMARCHY_MIGRATION_STATE:-$HOME/.local/state/omarchy/migrations}/<id>.sh`
   (upstream `bin/omarchy-migrate:32,43`). Written only for a ported step
   whose result is visible in the file. A declined migration gets no marker.
4. **Gate: `.bar | has("centerAnchor")`.** Only v4.0.x seeds have it; rc1,
   rc2 and v4.5.0 seeds do not, and the shell's writer keeps unknown keys
   (`shell/shell.qml:175`). No key → exit 0, zero IPC calls, no markers. A
   user who deleted the key by hand gets no Elsewhen (accepted in the spec).
5. **Duplicate trays stay** (owner decision). IPC has no delete, no nixarchy
   seed ever had two trays, and `1791968925` is recorded as `partial`.
6. **`centerAnchor` stays in the file.** Nothing in 4.5 reads it, and
   removing it would need a direct write.
7. **`1790528634` (Elsewhen rename) is not-needed**: no nixarchy seed ever had
   `omacom.elsewhen`.
8. **The 18 declined migrations are not ported here.** The session drafts one
   follow-up issue text per group (step 8); the lead files them. Agents file
   nothing.
9. **`omarchy-migrate` behaviour is unchanged**: `--pending` still prints
   nothing and exits 0. Only its prose and ledger row change.
10. **Mode A:** the hook is enabled on `osConfig.programs.nixarchy.enable or
    false`, inside `config = lib.mkIf cfg.enable` (`modules/home.nix:855`),
    and `tests/options.nix` asserts both states.
11. **No coexistence fixture** (§14): no NixOS option is set. A read-only
    (home-manager managed) `shell.json` means the shell's save fails, the poll
    never sees the result, no marker is written, one journal line per login.

### What the shell actually does (checked against the pinned source while planning)

Source: `inputs.omarchy` v4.5.0 (`nix flake archive --json . | jq -r
'.inputs.omarchy.path'`).

- **`moveBarWidget` reports a refusal as its reply.**
  `shell/services/PluginRegistry.qml:325-334` returns `moveBarEntry`'s error
  (`:331`), and the IPC wrapper (`shell/shell.qml:1840-1847`) prints it
  instead of `ok`: for example `widget at center[0] is not omarchy.clock`
  when the entry at `fromIndex` is not the named id (`moveBarEntry`,
  `:296-323`). The file is not changed by a refused move. **The script stops
  the step at the first reply that is not `ok`**, and still judges each step
  by re-reading the file, because `ok` does not prove the save landed
  (`persistShellConfig` skips the write on an unreadable file). The stub in
  step 5 reproduces both: it prints the refusal and leaves the file alone.
- `putBarWidget` (`PluginRegistry.qml:339-358`) returns `""` (→ `ok`) when
  the id is already on the bar or enabled, `"not ready"` while scanning, drops
  `before`/`after` when the neighbour is missing, and otherwise enables with
  the placement. IPC wrapper: `shell/shell.qml:1831-1838`.
- `barTarget` (`:261-294`) clamps an `index` past the end to the end.
- `ensureConfigShape` (`:405-413`) gives the file every section in
  `Util.barSections` = `["left","centerBegin","center","centerEnd","right","tray"]`
  (`shell/Commons/Util.qml:179`) and a `plugins` array.
- `persistShellConfig` (`shell/shell.qml:118-128`) sets `version = 1` and does
  not write when the file was unreadable.
- Entries in the v4.0.6 seed are objects (`{"id": "omarchy.clock", ...}`);
  compare ids with `if type == "object" then .id else . end`.

## Steps

Every step that edits a `.nix` file ends with `nix fmt` and a read of
`git diff --stat`, because a hook on this machine reformats `.nix` files with
nixpkgs-fmt after every edit (§5). Every new file is `git add`ed before any
evaluation (§5: a flake sees only tracked files). Every local build runs
under `flock /mnt/data/vmtest/codex-build.lock` (§6). codex and agy cannot
build; the session runs every check command below after their edit.

1. **`pkgs/omarchy/nix-bin/omarchy-migrate-user` (new).**
   Header exactly like `omarchy-mise-unshadow:1-6`: `#!/usr/bin/env bash`,
   `# nixarchy:new`, `# omarchy:summary=Port Omarchy's user-file migrations
   that apply here`, `# omarchy:hidden=true`; `set -euo pipefail`. The
   `# nixarchy:new` line is required or `pkgs/omarchy/default.nix:1039-1043`
   fails the build ("replaces nothing in this Omarchy version"), and the same
   loop links it into `$out/bin` (`:1050`).

   Behaviour, in order:
   - `cfg=${XDG_CONFIG_HOME:-$HOME/.config}/omarchy/shell.json`,
     `state=${OMARCHY_MIGRATION_STATE:-$HOME/.local/state/omarchy/migrations}`.
   - **Gate:** `jq -e '.bar | type == "object" and has("centerAnchor")' "$cfg"`
     fails or the file is unreadable → `exit 0`. No IPC before this line.
   - If all three markers exist → `exit 0`.
   - **Readiness:** copy only the ping loop at `modules/home.nix:2353-2358`
     (not that hook's `state=` line, which names a different directory): up to 120 × `omarchy-shell
     shell ping` one second apart; still no answer → `exit 0`, no marker.
     `export OMARCHY_SHELL_IPC_TIMEOUT=${OMARCHY_SHELL_IPC_TIMEOUT:-30s}`.
   - **Step `1790042972`** (skip if `$state/1790042972.sh` exists):
     `omarchy-shell shell rescanPlugins || true`. If any bar entry's id is
     `omacom.elsewhen` (upstream's own jq: `[.bar.layout[]?[]? | if type ==
     "object" then .id else . end] | index("omacom.elsewhen")`), skip the put.
     Else call `omarchy-shell shell putBarWidget omarchy.elsewhen
     '{"after":"omarchy.clock"}'` directly — **not** `omarchy-bar put`, which
     returns 0 when the shell never answered (`bin/omarchy-bar:380`). Retry
     while the reply is `not ready` (up to 50 × 1 s, as `ask_to_put`,
     `bin/omarchy-bar:313-318`). Any reply other than `ok` → log, stop the
     whole run (no later step: order matters).
     Proof: poll the file ≤10 s for `omarchy.elsewhen` (or `omacom.elsewhen`)
     anywhere in `.bar.layout`; then `mkdir -p "$state"; touch
     "$state/1790042972.sh"`. No proof → log, stop.
   - **Step `1791968925`** (skip if marker exists; skip without a marker if
     `(.bar.id // "" | tostring)` is not `""` or `omarchy.bar`, matching
     upstream which never acts on such a bar): read the file once. Then,
     **separately for each section** S in `right`, `left`, `center`: the
     pinned position is index 0 for `right` and the last index for `left` and
     `center`. Take the **last** `omarchy.tray` entry's index `t` in S
     (upstream keeps `[-1:]`). If `t` is not already at the pinned position,
     issue one `moveBarWidget omarchy.tray
     '{"fromSection":S,"fromIndex":t,"section":S,"index":P}'` for S, with
     P = 0 for `right`, or the section length for `left`/`center` (clamped to
     append). Extra trays stay (decision 5). A reply other than `ok` → log,
     stop the run.
     Proof: from the one read, compute each section's expected **whole
     array** (entries as JSON objects, so two trays that carry different
     fields are told apart) and poll ≤10 s until all three sections equal it.
     Then touch the marker.
   - **Step `1791969355`** (skip if marker exists; same built-in-bar test):
     read `center` once; `k` = index of the first entry whose id equals
     `.bar.centerAnchor` (a string; otherwise treat as absent). Absent → no
     moves, write the marker (upstream also leaves `center` whole; fixture g).
     Else compute the expected result *from this one read*:
     `centerBegin' = centerBegin + center[0:k]`, `center' = [center[k]]`,
     `centerEnd' = center[k+1:] + centerEnd`. Issue `k` moves of
     `fromSection:"center", fromIndex:0` (naming `center[i]`'s id) to
     `section:"centerBegin", index: <len, i.e. append>`, then `n-k-1` moves of
     `fromSection:"center", fromIndex:<current last index>` (naming that
     entry's id) to `section:"centerEnd", index:0`. Ids per move come from the
     one read, so a layout that drifted makes the shell refuse; the first
     reply that is not `ok` stops the step (log, no marker), so no later move
     runs against a layout that no longer matches the read.
     Proof: poll ≤10 s until the three sections' id lists equal the computed
     result; then touch the marker. Otherwise log and stop; the next login
     re-reads and recomputes.
   - Every log line goes through one function:
     `log() { printf '%s\n' "$*" | systemd-cat -t nixarchy-user-migrations || true; }`
     (`|| true`: a log that cannot reach the journal must not abort the run
     under `set -e`/`pipefail`).

   Shell traps: `set -e` does not reach inside `$(...)` — write
   `out=$(cmd) || { log; exit 0; }` (§5). Never `mapfile < <(cmd)` for a list
   that may legitimately fail (§4). Never `grep -q` on a pipeline under
   `pipefail` (checked by `checks.grep-q-pipefail`). Reads use `jq` on the
   file; nothing in the script redirects into, `mv`s, `cp`s or `install`s onto
   `shell.json` (the build.yml guard must stay green with **no** `847-allow`
   in this file). `jq` reads happen in the C locale is fine; only parsing
   `omarchy-shell`/`qs` stdout needs `LC_ALL=C.UTF-8` (§13), and replies here
   are compared with `case`, not parsed.

   Check: `bash -n` on the file; `nix build .#omarchy` (package tier, gated
   per §6: no p620 system build, load < 12, `vm-host-free.sh` prints `free`
   for both `install` and `edge`) proves the bin is installed and linked;
   the behaviour is proven by step 5.

2. **`modules/home.nix` ~2446 (after `default-plugins`, before
   `mise-notice`): new entry `"omarchy/hooks/post-boot.d/user-migrations"`.**
   ```nix
   "omarchy/hooks/post-boot.d/user-migrations" = {
     enable = osConfig.programs.nixarchy.enable or false;
     executable = true;
     text = ''
       #!/usr/bin/env bash
       export PATH=${lib.makeBinPath [ cfg.package pkgs.jq pkgs.coreutils pkgs.systemd ]}:$PATH
       exec omarchy-migrate-user
     '';
   };
   ```
   Plus a one-line `# Why:` pointer above it to the new `pkgs/AGENTS.md`
   section from step 4 (§7: reasoning lives in AGENTS.md).

   **`tests/options.nix:1135-1139`**: add `userMigrationsHook = { on =
   defaultHomeOn.xdg.configFile."omarchy/hooks/post-boot.d/user-migrations".enable;
   off = fixtureNixarchyOff.xdg.configFile."omarchy/hooks/post-boot.d/user-migrations".enable; };`
   beside `miseNoticeHook`, with the same `.enable, not ?` comment reason.
   Then build `options-shards` (cheap) to confirm the new case lands in
   exactly one shard, and the shard that holds it (options tier: at most two
   at once, no runner busy, §6 table).

   Traps: §7 (Mode A; plain assignment, no mkDefault needed on a bool here
   because it mirrors `mise-notice`); §5 nixfmt after the edit; §1 break:
   change `enable` to `true` and show `userMigrationsHook.off` fails.
   Check: `nix build .#checks.x86_64-linux.options-shards`, then the owning
   `options-*` shard; `nix fmt -- --ci`; `statix check .`; `deadnix --fail .`.

3. **`data/user-migrations.nix` (new).** An attrset keyed by migration id
   (string, no `.sh`), each `{ decision = "ported" | "partial" | "not-needed"
   | "declined"; reason = "..."; }`, plus `predates = [ ... ];` with one
   shared comment: "In v4.0.6 already; every nixarchy seed carries its effect."
   The row set is exactly the 96 files from
   `grep -lE 'HOME|XDG_CONFIG|\.config|shell\.json' "$src"/migrations/*.sh`
   (verified while planning: 218 migrations, 96 hits). `predates` = the 52
   hits that already exist in v4.0.6's `migrations/` (derive with
   `comm -12` against `nix flake prefetch --json github:basecamp/omarchy/v4.0.6`,
   store path `/nix/store/6s7r8sc3zp51xk0micr7jdcc9yp94ahw-source` at planning
   time). The 44 rows:

   | decision | ids | reason |
   |---|---|---|
   | ported | `1790042972`, `1791969355` | `omarchy-migrate-user` |
   | partial | `1791968925` | order ported; duplicate trays kept (no IPC delete; no seed had two) |
   | not-needed (mise) | `1786719479` `1786967403` `1787215824` `1787342993` `1787573629` `1788941927` `1789310715` `1790457067` `1790863209` `1791382872` `1792343225` | no mise here; `omarchy-mise-install` refuses (#1625) |
   | not-needed (packages/system) | `1789764927` `1790539857` `1790542069` `1791345484` `1791708587` `1792345511` `1791479273` `1793667581` `1788261467` `1791769486` | gated on `omarchy-pkg-*`, pacman or `/var/lib`; apps and system state come from the flake. `1791345484`: handled, `pkgs/AGENTS.md` (Disktree). `1788261467`: portal set by `modules/nixos.nix`. `1791769486`: no nixarchy release shipped the USB approval units |
   | not-needed (other) | `1790528634` | no seed ever had `omacom.elsewhen` |
   | not-needed (other) | `1793315076` | Apple Silicon `~/.bashrc`; bash setup comes from `/etc/bashrc` (`modules/nixos.nix:1236`) |
   | declined | `1788129995` `1791723398` `1787679775` `1788281348` `1791123731` `1791376887` `1791470456` `1791676907` `1791696584` `1791698594` `1791705142` `1791722809` `1791875754` `1792259038` `1792474908` `1792648436` `1793477875` `1793565796` | real user-file edit that may apply; needs its own fixture first (§2, §3). Follow-up drafted per group (step 8) |

   The implementer checks each `not-needed` reason against the migration
   text and the code it names; a reason that does not hold becomes
   `declined` without argument (spec). A file comment points to the check
   from step 6 and says a bump adds rows for its new hits.
   Traps: §5 nixfmt; `git add` before step 6 evaluates it.
   Check: `nix eval --json --file data/user-migrations.nix | jq 'del(.predates) | length'`
   → 44, and `.predates | length` → 52. Full proof is step 6.

4. **Prose and ledgers.**
   - `pkgs/omarchy/nix-bin/omarchy-migrate:5-17`: replace "86" with the
     current shape (no number that a bump makes stale, or "218 at v4.5.0");
     add that user-file migrations that apply here are ported into
     `omarchy-migrate-user` and every user-file migration is decided in
     `data/user-migrations.nix`. Lines 19-end unchanged (decision 9). Fix the
     heredoc's last paragraph only if it now says something false.
   - `data/bin-ledger.nix:390-394` (`omarchy-migrate`): same correction in
     `reason`; keep `class = "replace"` and the `pacman` field.
   - `data/bin-ledger.nix`, new row `"omarchy-migrate-user" = { class = "new";
     reason = "Not in upstream. Run once per user from a post-boot hook: ports
     the bar's three 4.5 migrations through the shell's IPC on a v4.0.x seed,
     with upstream's own migration markers (#1610)."; };` in alphabetical
     position (after `omarchy-migrate`).
   - `pkgs/AGENTS.md`: new `##` section appended at the end (do not insert
     mid-file; anchors are cross-referenced): what `omarchy-migrate-user`
     does, the IPC-only rule and why (#847), the `moveBarWidget` refusal reply and why the file is still re-read,
     the marker path, and "a bump that brings new migrations: run
     `checks.user-migrations-ledger`, add a row per id it names".
   Traps: §5 nixfmt on the ledger; §7 (short code comments, reasoning in
   AGENTS.md). Check: `nix build .#checks.x86_64-linux.bin-ledger`
   (cheap; it derives `class` from the tree, so a missing row fails it).

5. **`tests/user-migrations.nix` (new) + `tests/fixtures/shell-json/` +
   `flake.nix` checks entry `user-migrations`.**
   Wire it like `panel-loaders` (`flake.nix:2391-2395`): `import
   ./tests/user-migrations.nix { pkgs = pkgsFor.${system}; omarchy =
   self.packages.${system}.omarchy; omarchySrc = omarchy; }`. Adding the
   `checks` entry is enough for CI (§4: the "Build every check no other job
   claims" step runs it); **no workflow edit**.

   A `runCommand` with `jq`, `bash`, `coreutils`, `diffutils`. Per case and
   per run (script and oracle each get their own fresh `HOME`): set
   `XDG_CONFIG_HOME=$HOME/.config`, `XDG_STATE_HOME=$HOME/.local/state`,
   `XDG_DATA_HOME=$HOME/.local/share`, `XDG_CACHE_HOME=$HOME/.cache` and
   `OMARCHY_MIGRATION_STATE=$HOME/.local/state/omarchy/migrations` exactly,
   not merely "under" `HOME`: upstream's migrations read the literal
   `$HOME/.config/omarchy/shell.json`, so the script and the oracle must
   resolve the same relative path (§4: moving `HOME` alone is not isolation).
   A stub `systemd-cat` first on `PATH` appends its stdin to
   `$HOME/journal.log` (the sandbox has no journal). `OMARCHY_SHELL_IPC_TIMEOUT` irrelevant; set a
   tiny poll budget via the script's own constants only if step 1 exposes
   them as env overrides (keep the defaults otherwise; 10 s polls against a
   stub that writes synchronously return at once).

   **Stub `omarchy-shell`** (a bash script first on `PATH`), mirroring the
   facts above: `shell ping` → ok; `shell rescanPlugins` → ok; `shell
   putBarWidget ID JSON` → `ok` without change if ID is already in the layout,
   otherwise insert `{"id":ID}` after the `after` neighbour (dropping
   `after` if the neighbour is absent → section end of the manifest default,
   `centerEnd`); `shell moveBarWidget ID JSON` → if
   `layout[fromSection][fromIndex]` does not have id ID, prints `widget at
   <S>[<i>] is not <ID>` and leaves the file alone; otherwise splices into
   `section` at `min(index, len)` and prints `ok`. Every write first applies
   `ensureConfigShape` (all six `barSections` arrays, `plugins`) and sets
   `version = 1`. The line that writes the sandbox file carries `847-allow`.
   Every call is appended to `$HOME/ipc.log`. A `STUB_NOWRITE=1` mode answers
   `ok` and writes nothing (fixture f).

   **Oracle:** upstream's `migrations/1790042972.sh`, `1791968925.sh`,
   `1791969355.sh` from `omarchySrc`, run in that order with `bash` on a copy
   of the same fixture, with the same stub and the vendored
   `${omarchy}/bin/omarchy-bar` on `PATH`. Normalise both results before
   comparing: fill every `barSections` array and `plugins`, drop `version` and
   `.bar.centerAnchor`, `jq -S`. Compare with `diff -u` and print it on
   failure.

   Fixtures under `tests/fixtures/shell-json/` (`git add` them):
   (a) v4.0.6 seed verbatim (`config/omarchy/shell.json` from the v4.0.6
   source above), (b) edited around the clock (widgets on both sides,
   non-empty `centerBegin`/`centerEnd`, tray mid-`right`), (c) v4.5.0 seed
   (`${omarchySrc}/config/omarchy/shell.json`, referenced, not copied),
   (d) (a) with `bar.id = "local.neon-bar"`, (e) is (a) run, then Elsewhen
   removed from the layout, then run again, (f) (a) with `STUB_NOWRITE=1`,
   then rerun with the working stub, (g) (a) with the clock moved to `right`,
   (h) (a) with `right: [{"id":"omarchy.tray","t":1}, X,
   {"id":"omarchy.tray","t":2}]` — the extra `t` field tells the two trays
   apart, which the shell keeps (it moves whole entries).

   | case | asserts |
   |---|---|
   | a | normalised == oracle; `centerEnd[0]` id is `omarchy.elsewhen`; 3 markers |
   | b | normalised == oracle |
   | c | `cmp` with the input; `ipc.log` empty; no marker dir |
   | d | the only layout-changing call in `ipc.log` is the Elsewhen `putBarWidget` (no `moveBarWidget`; `ping`/`rescanPlugins` are expected); normalised == oracle; one marker |
   | e | Elsewhen still absent after the second run; `ipc.log` of the second run empty |
   | f | no markers after the first run, and a line in `journal.log`; 3 markers after the rerun; result == (a)'s |
   | g | normalised == oracle (no moves); 3 markers |
   | h | `right` equals exactly `[tray t:2, tray t:1, X]` (the last tray moved to the front, the other kept in order); marker `1791968925.sh` written |

   Note on (h): the oracle deletes the extra tray, so (h) does **not**
   compare with the oracle; it asserts the documented partial port.

   **§1 breaks, each applied, shown with `git diff`, run, and the red output
   captured for the PR, then restored with `git checkout HEAD -- <file>`
   (not `git checkout -- <file>`, which restores the index, §5):**
   a: run the split before the Elsewhen put → Elsewhen in `center`;
   (also: stub `moveBarWidget` answering `ok` on a refusal → an extra fixture
   with a drifted layout must still get no `1791969355` marker);
   b: split appends to `centerBegin` at index 0 → order differs;
   c: delete the gate → calls logged;
   d: drop the built-in-bar test from the split;
   e: ignore the `1790042972` marker;
   f: touch the marker on the IPC reply instead of the file proof;
   g: treat a missing anchor as index 0;
   h: pin the first tray instead of the last.
   Commit a known-good baseline before the break loop (§5).

   Traps: §4 hermetic `XDG_*`; §5 heredocs inside `''…''` reindent the file —
   write fixtures and the stub as real files under `tests/`, and multi-line
   shell text with `printf '%s\n'`; `''${` for literal `${`; never `\$`.
   `set -e` does not reach `$(...)`. Check name not on the `claimed` list.
   Check: `flock /mnt/data/vmtest/codex-build.lock nix build
   .#checks.x86_64-linux.user-migrations --print-build-logs` (cheap tier).

6. **`checks.user-migrations-ledger`** (`tests/user-migrations-ledger.nix`,
   `runCommand`, wired beside step 5's entry). Inputs: `omarchySrc` and
   `data/user-migrations.nix` serialised with `builtins.toJSON`
   (`pkgs.writeText`). It computes the triage set with the exact grep from
   step 3 (fail if it is empty — an empty list is not "all decided", §4),
   compares with the ledger's ids ∪ `predates`, and names every missing and
   every extra id; it also fails on any `decision` outside the four values.
   §1 breaks: delete the `1791969355` row → output names `1791969355`; add a
   `9999999999` row → output names it; set one decision to `"skip"` → named.
   Check: `nix build .#checks.x86_64-linux.user-migrations-ledger` (cheap).

7. **VM step in `tests/plugin.nix`**, appended after the #1391 block
   (currently ending at line 717, before `'';`). As the `omarchy` user, the
   spec says: **stop the shell, copy, start it.** Stop it with the kill loop
   upstream's `bin/omarchy-restart-shell:84` uses (`quickshell kill -p
   "$CONFIG_DIR" --any-display`, same `CONFIG_DIR` derivation as that script),
   and assert `omarchy-shell shell ping` now fails before copying — if
   `omarchy-launch-shell`'s loop respawns it, find the session's own stop path
   and say so in the PR rather than writing under a live shell. Copy fixture
   (a) over `~/.config/omarchy/shell.json` on a line carrying `# 847-allow`
   (the guard looks the marker up in the original line, as
   `tests/session.nix:2966`), remove `~/.local/state/omarchy/migrations`,
   start the shell with `omarchy-restart-shell`, and wait for `omarchy-shell
   shell ping` (the wait loop near `tests/plugin.nix:280-290`). Then run
   `~/.config/omarchy/hooks/post-boot.d/user-migrations`, then compare the
   normalised file with check 5's expected (a) output (pass it into the VM
   test as a store path built by step 5's derivation, e.g.
   `passthru.expectedA`) and check the three markers. This proves the real
   IPC behaves as the stub does.
   §1 break: swap steps in the script so the split runs first → this step
   fails. VM tier: only when `gh api repos/olafkfreund/nixarchy/actions/runners
   -q '[.runners[]|select(.busy)]|length'` prints `0` and no p620 system build
   runs (`pgrep -fc '^(nix build|nh os build|nixos-rebuild).*p620'`); evaluate
   the drvPath first and build `'<drv>^*'` (§5: background builds pin
   nothing).
   Check: `nix build .#checks.x86_64-linux.plugin --print-build-logs`.

8. **Follow-up issue texts (session only; no file in the repo, nothing
   filed).** For each group below, the session reads every migration in it
   from `omarchySrc` and drafts one issue body: what upstream changes, which
   nixarchy users miss it and why (seed-once at `modules/home.nix:1162` /
   `:459`, or other), the fixture that would prove a port (§2, §3), and a
   suggested milestone and area label (§12). Grouping is by subject and is
   corrected if reading shows otherwise:
   - imv editor binding: `1788129995`
   - Neovim: `1791723398`
   - Hyprland layouts: `1787679775`, `1791698594`
   - Themes, backgrounds, transparency: `1788281348`, `1791123731`,
     `1791470456`, `1791705142`, `1792259038`
   - Web apps: `1791696584`, `1791875754`
   - Browser flags: `1791376887`, `1792474908`
   - Input and dictation: `1791676907`, `1793477875`
   - herdr: `1791722809`
   - OpenCode: `1793565796`
   - Notifications: `1792648436`
   The drafts go in the PR body under "Follow-ups for the lead to file",
   each naming its ledger rows. Do not write the literal skip-CI marker
   anywhere in them (§8).

## Tests (by §6 tier)

| tier | command | expected |
|---|---|---|
| cheap | `nix fmt -- --ci`; `nix run nixpkgs#statix -- check .`; `nix run nixpkgs#deadnix -- --fail .` | clean |
| cheap | `checks.grep-q-pipefail` | green (memory: it failed CI twice) |
| cheap | `checks.user-migrations` | green; each of the eight breaks red |
| cheap | `checks.user-migrations-ledger` | green; three breaks red, naming the id |
| cheap | `checks.bin-ledger` | green with the new row; red without it |
| cheap | `checks.options-shards` | green |
| cheap | the `build.yml` "Nothing we ship writes shell.json" step, run locally as a script under bash (§1: CI runs bash) | green; `omarchy-migrate-user` has no `847-allow` |
| package | `nix build .#omarchy` | builds; `result/bin/omarchy-migrate-user` exists |
| options | the shard holding `userMigrationsHook` | green; red with `enable = true` |
| VM | `checks.plugin` | green; red with steps swapped |
| every other target `.github/scripts/generated-checks.sh` prints | as §6 "run the checks locally before you push" | green |

Not run locally: `install`, `free-space`, `installer-refusal` (self-hosted
install job; nothing here reaches the installer), and anything a hosted
runner limits. Named as such in the PR.

## CI

No workflow file changes. The two new checks are picked up by the
generated-checks step. If that turns out false (read the step's list in the
run log), the fix is a workflow edit and needs a human merge (§10, §11).

## Rollback

Revert the PR. Users who already ran the hook keep the moved layout and the
three markers, which is exactly upstream's end state, so nothing needs
undoing on their machines. To stop the hook without a revert, delete the
`user-migrations` entry in `modules/home.nix`; the script is inert without
it.
