---
status: approved
issue: 1610
intent: intent/2026-11-07-1610-user-state-migrations.md
---

# Spec: Omarchy 4.5's changes to a user's own files reach machines installed before it

## Decisions on the intent's open questions

The approved intent wrote no recommendation under its three questions, so
these are the spec's choices, each with its reason. Change any of them by
rejecting this spec.

1. **Scope: the bar only.** Port the bar's migrations. Every other migration
   in the triage gets a written decision in a ledger, and a check makes the
   next bump add rows for its own migrations. Each one that is declined here
   is its own user-visible change, and §2 wants a probe for each, which is a
   pull request apiece.
2. **Where it runs: a `post-boot.d` hook that waits for the shell and changes
   the layout through its IPC.** This is the path the `default-plugins` hook
   already uses (`modules/home.nix:2296-2442`). Running before the shell
   starts would mean editing the file directly. The intent rules that out, and
   so does `build.yml:846` ("Nothing we ship writes shell.json").
3. **Marker: upstream's own directory and file name,
   `~/.local/state/omarchy/migrations/<id>.sh`.** This is the marker upstream's
   `bin/omarchy-migrate` reads (`STATE_DIR`, line 32; `$STATE_DIR/$filename`,
   line 43). If nixarchy ever runs upstream's runner, it will skip what this
   port already did. The marker is written only for a migration that was
   ported and has finished. A declined migration gets no marker, so nothing
   claims it ran.

## What upstream does, checked against the pinned source

The source is `inputs.omarchy` at v4.5.0
(`/nix/store/fvx3…-source`). The seeds were checked with `nix flake prefetch`
for v4.0.6, v4.5.0-rc1 and v4.5.0-rc2.

- The v4.0.6 seed has `bar.centerAnchor = "omarchy.clock"`. Its
  `center` is `[indicators, clock, keyboard-layout, weather, system-update]`
  and it has no Elsewhen anywhere. The rc1, rc2 and v4.5.0 seeds have no
  `centerAnchor` and already carry `omarchy.elsewhen` in `centerEnd`. So
  **`.bar | has("centerAnchor")` marks a file seeded before 4.5**, and
  nothing in 4.5 adds the key back. The shell's writer keeps keys it does not
  know: `mutateShellConfig` deep-copies the whole config (`shell/shell.qml:175`).
  So the key also survives once the shell has rewritten the file.
- Upstream runs migrations in name order. `1790042972` puts Elsewhen
  `--after omarchy.clock` while the clock is still in `center`. `1791968925`
  then pins the tray: first in `right`, last in `left` and `center`, keeping
  only the last tray in a section. `1791969355` then splits `center` at the
  anchor: what came before the anchor is appended to `centerBegin`, and what
  came after it is put at the front of `centerEnd`. On the v4.0.6 seed the
  result is `centerBegin [indicators]`, `center [clock]`,
  `centerEnd [elsewhen, keyboard-layout, weather, system-update]`. **The order
  matters.** If the split ran first, Elsewhen would end up in `center` next to
  the clock.
- `1791968925` and `1791969355` act only on the built-in bar
  (`bar.id` empty or `omarchy.bar`). `1790042972` acts on any bar.
- The running shell exposes `putBarWidget` and `moveBarWidget` over IPC
  (`shell/shell.qml:1831,1840`). `moveBarWidget` takes `fromSection`,
  `fromIndex`, `section` and `index`. It refuses if the entry at `fromIndex`
  is not the id it was given (`services/PluginRegistry.qml:296-322`), so a
  layout that changed underneath it causes an error, not a wrong move. An
  `index` past the end is clamped to append (`barTarget`, around line 280).
  Nothing over IPC deletes a key, so `centerAnchor` stays. The 4.5 shell does
  not read it (`grep -r centerAnchor shell/` finds nothing).
- `1790528634` renames `omacom.elsewhen` to `omarchy.elsewhen`. No nixarchy
  seed ever carried `omacom.elsewhen` (v4.0.6 has no Elsewhen, and
  `grep -r elsewhen modules pkgs` finds nothing), and the package it came in
  was never installable here. So that migration is **not needed**, and it gets
  a ledger row instead of a port.

## Design

### 1. `pkgs/omarchy/nix-bin/omarchy-migrate-user` (new, `# nixarchy:new`)

A bash script that runs the three bar steps in upstream's order. It reads
`shell.json` only, and every change goes through `omarchy-shell shell …` IPC.

- **Gate.** Exit 0 and do nothing unless `shell.json` is readable and
  `.bar | has("centerAnchor")` holds. A fresh 4.5 install, and a user who
  installed on rc1, rc2 or v4.5.0, never takes this path. That covers a 4.5
  user who has already removed Elsewhen: they keep it removed.
- **Shell readiness.** Copy `default-plugins` exactly: up to 120 one-second
  `shell ping` attempts, `OMARCHY_SHELL_IPC_TIMEOUT=30s`, and exit 0 with no
  marker if the shell never answers. The next login tries again.
- **`1790042972` (Elsewhen).** Skip if the marker exists. Run
  `shell rescanPlugins`. Upstream skips the put when an `omacom.elsewhen`
  entry is on the bar, and so does this script. Otherwise call
  `shell putBarWidget omarchy.elsewhen '{"after":"omarchy.clock"}'`. Retry on
  `not ready`, the way `omarchy-bar`'s `ask_to_put` does. **This does not go
  through `omarchy-bar put`**, which returns 0 when the shell never answers
  (`bin/omarchy-bar`, `ask_to_put` and its return 1 → `return 0`), and that
  would write a marker for a put that never happened.
- **`1791968925` (tray).** Skip if the marker exists or the bar is not
  built-in. For `right`, `left` and `center`, if the section's last
  `omarchy.tray` entry is not at the pinned end, issue one `moveBarWidget`
  with `fromSection` and `fromIndex` to index 0 (`right`) or to the end. Extra
  trays in one section are not removed. Upstream deletes them, but IPC has no
  delete short of disabling the plugin. This is recorded in the ledger as a
  partial port, and it is the one place where this design falls short of the
  intent's "as upstream's own migration leaves it": a layout that lists more
  than one tray in a section keeps the extras, and the 4.5 bar draws them all.
  No seed nixarchy ever shipped has more than one tray. A v4.0.6 seed has a
  single tray, already first in `right`, so this step is a no-op there.
- **`1791969355` (split).** Skip if the marker exists or the bar is not
  built-in. Read `center` once and find the anchor's index `k` among `n`
  entries. If it is absent, move nothing. This matches upstream, which keeps
  `center` whole. Otherwise issue `k` moves of `center[0]` to `centerBegin`
  at the end, then `n-k-1` moves of `center[last]` to `centerEnd` at index 0.
  Each move names the id that is expected at that `fromIndex`, so any drift
  stops the step.
- **Marker only on proof.** After each step, poll the file (read-only, at most
  10 s) until it shows the step's result. Only then
  `touch ~/.local/state/omarchy/migrations/<id>.sh`. The shell does not save
  when it found the file unreadable (`persistShellConfig`,
  `shell/shell.qml:122`). So "the IPC said ok" is not "the file changed", and
  without this a home-manager-managed, read-only `shell.json` would get
  markers for nothing.
- Failures are logged with `systemd-cat -t nixarchy-user-migrations`, like
  `default-plugins`.

It lives in `nix-bin` because it is another `omarchy-*` command next to
`omarchy-migrate` and `omarchy-mise-unshadow`. `default.nix:1036-1050`
already installs and links a `# nixarchy:new` bin.

### 2. `modules/home.nix`: hook `omarchy/hooks/post-boot.d/user-migrations`

This goes next to `default-plugins` (around line 2296), with the same
`export PATH=${lib.makeBinPath [ cfg.package pkgs.jq pkgs.coreutils pkgs.systemd ]}`.
The whole module is `config = lib.mkIf cfg.enable` (`modules/home.nix:855`),
so with Omarchy off the hook does not exist. The hook is also enabled on
`osConfig.programs.nixarchy.enable or false`, the gate `mise-notice` uses
(`:2447`). `tests/options.nix:1137-1138` already asserts that gate on and off
for `mise-notice`, and a matching pair is added for this hook (Mode A, §7).

### 3. `data/user-migrations.nix` (new ledger)

There is one row per migration that the triage grep
(`HOME|XDG_CONFIG|\.config|shell\.json`) selects from the pinned
`migrations/`. Each row is `{ decision = "ported" | "partial" | "not-needed" | "declined"; reason = "…"; }`.
Migrations already in v4.0.6, whose effect every nixarchy seed already has, go
in one `predates` list with one shared reason. There are 52 of them: 96 hits
minus the intent's 44. The other rows are the 44, decided as follows:

- **ported (2):** `1790042972`, `1791969355`.
- **partial (1):** `1791968925`. The order is ported, but duplicate trays are
  left in place.
- **not-needed: mise (11):** `1786719479`, `1786967403`, `1787215824`,
  `1787342993`, `1787573629`, `1788941927`, `1789310715`, `1790457067`,
  `1790863209`, `1791382872`, `1792343225`. nixarchy ships no mise, and
  `omarchy-mise-install` refuses (#1625).
- **not-needed: packages and the system (10):** `1789764927`,
  `1790539857`, `1790542069`, `1791345484` (Disktree, already handled,
  `pkgs/AGENTS.md`), `1791708587`, `1792345511`, `1791479273`, `1793667581`,
  `1788261467` (the portal is configured by `modules/nixos.nix`), `1791769486`
  (no nixarchy release shipped the USB approval units). On NixOS, apps and
  system state come from the flake. Each of these is gated on `omarchy-pkg-*`,
  pacman or `/var/lib`, and does not apply here.
- **not-needed: other (2):** `1790528634` (see above) and `1793315076`
  (Apple Silicon `~/.bashrc`; bash setup comes from `/etc/bashrc`, at
  `modules/nixos.nix:1236`).
- **declined, follow-up (18):** `1788129995` (it rewrites imv's Ctrl+E from
  `tensaku-edit` to `omasnap`; the v4.0.6 seed's `config/imv/config:16`
  names `tensaku-edit`, which nixarchy does not ship, and the seed never
  replaces an existing file, `modules/home.nix:1162`), `1791723398` (it adds
  two files to a Neovim config that was copied once; nixarchy seeds
  `~/.config/nvim` only into nothing, at `modules/home.nix:459`, so seeded
  users miss them), `1787679775`, `1788281348`, `1791123731`,
  `1791376887`, `1791470456`, `1791676907`, `1791696584`, `1791698594`,
  `1791705142`, `1791722809`, `1791875754`, `1792259038`, `1792474908`,
  `1792648436`, `1793477875`, `1793565796`. These are real user-file edits
  that may apply here: layouts, backgrounds, web app launchers, flags, herdr,
  OpenCode, dictation and notifications. Each needs its own fixture before it
  is ported (§2, §3). The PR lists them for a human to file. An agent does not
  file issues in this workflow.

Each reason is checked against the code when its row is written. The check
below proves that every row exists, not that its reason is true. The reasons
are reviewed in the pull request. Where a
reason fails, the row becomes `declined` and is not argued.

### 4. `pkgs/omarchy/nix-bin/omarchy-migrate` and `data/bin-ledger.nix`

This changes comments and prose only, and the behaviour stays the same:
`--pending` still answers nothing. The header and the ledger row
(`data/bin-ledger.nix:390`) say that user-file migrations are ported into
`omarchy-migrate-user` and decided in `data/user-migrations.nix`. They drop
the stale "86", because there are now 218 migration scripts. Add a ledger row
for `omarchy-migrate-user` (`class = "new"`). `pkgs/AGENTS.md` gets one
paragraph under the vendored-tree section: a bump that brings new migrations
adds rows, and the check below names them.

## Coexistence (§14)

No NixOS option is set, so there is nothing to collide in a merged
environment, and `tests/coexistence/fixtures.nix` gains no fixture. The one
case of the user's own config meeting this is a `shell.json` that home-manager
manages as a read-only store link. There the shell's write fails, the poll
never sees the result, no marker is written, and one journal line appears per
login. Nothing is overwritten. What Quickshell's writer does with a store
symlink has not been measured. The design does not depend on it, because no
marker is written unless the file shows the result. Fixture (f) below covers
that rule.

## Alternatives rejected

- **Run upstream's migration scripts with a stubbed `mv`.** They write
  `shell.json` directly (`jq … > tmp; mv tmp shell.json`), which is the #847
  hazard, and `build.yml:846` exists to fail on exactly that.
- **Edit the file before the shell starts in the session.** It is not live
  then, but that is still a direct writer that the guard would have to exempt.
  On a session that crashed and came back, the shell may already be up.
- **Activation.** There is no session there, and the shell may be running.
- **Port all 44 now.** That is 16 separate behaviours with no fixtures, which
  is the "check that cannot vary" problem (§3) in bulk.
- **A nixarchy-only marker directory.** It works, but it would duplicate
  upstream's, and a future real `omarchy-migrate` would re-run the bar steps.
- **Delete `centerAnchor` afterwards.** Nothing reads it, and deleting it
  would need a direct write.

## Risks

- **The stub test's model of `moveBarWidget` is not the shell.** The cheap
  check proves the ordering and gating against upstream's own jq. Only the VM
  step proves that the real IPC does the same thing.
- **A person who rearranges the bar while the hook runs.** A move that names
  the wrong id at `fromIndex` is refused, the step stops without a marker, and
  the next login recomputes from the file. The worst case is a split left half
  done until the next login, which the same rule then completes.
- **Users on v4.0.x who already fixed their bar by hand.** If they took the
  clock out of `center` but left the `centerAnchor` key, nothing moves, as
  upstream would do, and Elsewhen is still put once, which is upstream's
  behaviour too. If they deleted the `centerAnchor` key itself, the gate reads
  their file as a 4.5 one, and they get no Elsewhen. Upstream would put it
  there. This is accepted: nothing else in the file tells a pre-4.5 file
  without the key apart from a 4.5 user who removed Elsewhen. Putting it on
  the second would overwrite a choice, and missing the first only leaves out
  a widget.
- **The Elsewhen put happens at a login after the rebuild**, not at the
  rebuild. Nothing user-visible depends on that timing.

## Verification

Every check is cheap unless noted, so every run is under `flock
/mnt/data/vmtest/codex-build.lock`.

**A. `checks.user-migrations`** (`tests/user-migrations.nix`, `runCommand`,
moved `HOME` and all `XDG_*` per §4)

A stub `omarchy-shell` on `PATH` answers `ping`, `rescanPlugins`,
`putBarWidget` and `moveBarWidget` by editing the sandbox's `shell.json` with
jq. It logs every call, and the line that writes the file carries `847-allow`.
The oracle is upstream's own `migrations/1790042972.sh`, `1791968925.sh` and
`1791969355.sh`, run in order from `inputs.omarchy` on a copy of the same
fixture with the same stub behind the vendored `omarchy-bar`. The real shell's
`ensureConfigShape` (`services/PluginRegistry.qml:405-413`) adds every bar
section, `tray` included, and `plugins`, which upstream's jq does not. So the
stub does the same, and both results are normalised before comparing: every
`Util.barSections` array and `plugins` filled in, `version` and
`.bar.centerAnchor` dropped, keys sorted. Fixtures are under
`tests/fixtures/shell-json/`:

| fixture | asserts | break that must turn it red |
|---|---|---|
| (a) v4.0.6 seed, verbatim | equals the oracle; `centerEnd` starts with `omarchy.elsewhen`; 3 markers | run the split before the Elsewhen put → Elsewhen lands in `center` |
| (b) edited: widgets on both sides of the clock, non-empty `centerBegin`/`centerEnd`, tray mid-`right` | equals the oracle | replace the split's "append to `centerBegin`" with index 0 → order differs |
| (c) v4.5.0 seed (no `centerAnchor`) | file byte-identical, zero IPC calls, no markers | remove the gate → Elsewhen calls logged |
| (d) `bar.id = "local.neon-bar"` with an anchor | only the Elsewhen put; layout otherwise equals the oracle | drop the built-in-bar test from the split |
| (e) (a) again after removing Elsewhen | stays removed | ignore the marker for `1790042972` |
| (f) stub that answers ok but does not write | no markers; a rerun with a working stub completes | write the marker on the IPC reply instead of the file |
| (g) anchor not in `center` | equals the oracle (nothing moves) | treat a missing anchor as index 0 |
| (h) `right: [tray, widget, tray]` | the last tray is first in `right`; the other tray stays (the documented partial port); marker written | pin the first tray instead of the last |

**B. `checks.user-migrations-ledger`** (same file or a sibling,
`runCommand`): the set of triage hits in `${inputs.omarchy}/migrations` equals
the ledger's rows plus `predates`, and every row's `decision` is one of the
four. The error names each missing or extra id. Breaks: delete the
`1791969355` row (must print that id), and add a row for `9999999999` (must
print it).

**C. VM step in `tests/plugin.nix`**, which already re-runs `post-boot.d`
hooks (lines 700-717). This is VM tier, run only when no self-hosted runner is
busy. Stop the shell, copy fixture (a) into place (the shell is not running,
so this is not #847, and the line still carries `847-allow` for the guard),
start the shell, and run the hook. Then `cmp` the file, normalised as in A,
against check A's expected output for (a), and check the three markers.
Break: swap the step order in the script, and this step must fail.

**D. Existing guards stay green:** `build.yml` "Nothing we ship writes
shell.json" (the script has no writer), the `bin-ledger` check (new row), the
`options-*` shards (the new hook's off state), `nix fmt -- --ci`, statix,
deadnix and `checks.grep-q-pipefail`.

The failing output for every break in A, B and C goes in the PR (§1). The PR
also shows `git diff` proof that each break was actually applied.
