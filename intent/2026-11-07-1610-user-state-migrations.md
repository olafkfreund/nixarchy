---
status: draft
issue: 1610
author: x
---

# Intent: Omarchy 4.5's changes to a user's own files reach machines installed before it

## Problem

Omarchy moves an existing machine forward with migrations: scripts in
`migrations/` that run once, at update time. Some edit system state, and
nixarchy replaces those with NixOS options. Others edit the user's own files
in `~/.config` and `~/.local/state`. Those are the problem here.

nixarchy never runs migrations. `pkgs/omarchy/nix-bin/omarchy-migrate` tells
`--pending` callers that nothing is pending and refuses a bare run. Its
reasoning is that the pin moves "with the packaging updated to match". For
user files that has not happened. `main` went from Omarchy v4.0.6 to
v4.5.0-rc1 in #1405 (2026-10-21), then to v4.5.0 in #1606. Between v4.0.6 and
v4.5.0 upstream added 98 migrations. 44 of them touch `$HOME`, `~/.config` or
`shell.json` (listed at the end). Only three are named anywhere outside
`intent/`, `spec/` and `plan/`, and only Disktree's
(`migrations/1791345484.sh`, `pkgs/AGENTS.md`) is handled in code.

The bar shows the effect. A machine installed on v4.0.6 was seeded from that
release's `config/omarchy/shell.json`: `"centerAnchor": "omarchy.clock"`, and
a `center` list of indicators, clock, keyboard layout, weather and update.
The v4.5.0 shell no longer reads `centerAnchor` (it appears nowhere under
`shell/`). Upstream moves the anchor's neighbours into `centerBegin` and
`centerEnd` with `migrations/1791969355.sh`, which does not run here. So:

- The clock is no longer centred on an upgraded machine. The five widgets are
  centred as one group.
- Elsewhen, the 4.5 world clock, never reaches the bar. Upstream adds it with
  `omarchy-bar put omarchy.elsewhen --after omarchy.clock` in
  `migrations/1790042972.sh`, which also does not run here.

A new install is unaffected, because it is seeded from v4.5.0's `shell.json`,
and `modules/home.nix` seeds only a file that does not exist yet. This reaches
everyone whose `shell.json` was seeded by an older release and has been
updated since.

`omacom/omarchy#15517` turned up this gap. It is one of the 58 PATCHED-CHECK
rows in #1610. Of those rows, it is the only one where a real behaviour change
fails to reach nixarchy users. The others are ok, adapted, or n/a (see the
audit table in the #1610 review).

## Proposed outcome

- On a machine upgraded from v4.0.6, the bar looks as it did before the
  upgrade, as upstream's own migration leaves it. The clock is centred, the
  widgets that were around it move into `centerBegin` and `centerEnd`, and
  Elsewhen sits after the clock. This is not the same as a fresh v4.5.0 bar,
  which puts the keyboard layout on the right; upstream's migration does not
  either. It happens once for each user, without them doing anything. A user
  who later removes Elsewhen keeps it removed.
- Every 4.5 migration that touches user files has a written decision: ported,
  not needed here (with the reason), or declined. A future bump finds that
  list and adds to it, instead of starting again.
- `omarchy-migrate`'s comment and its `data/bin-ledger.nix` row describe what
  actually happens to user-file migrations.

## Affected users and systems

- Everyone on `main` who installed before #1606 (v4.0.x seeds). New installs
  are not affected.
- `~/.config/omarchy/shell.json`, which the shell itself rewrites. Writing
  the file while the shell is running leaves the bar's IPC targets dead, even
  when the bytes are identical (`docs/internals/shell-json-reload.md`, #847).
  `build.yml`'s step "Nothing we ship writes shell.json" fails on any such
  writer.
- Other user files named by the 44 migrations: theme and background state,
  herdr, Neovim, Chromium flags, web app launchers, dictation bindings,
  OpenCode.
- `modules/home.nix`, where activation already seeds and links user files.
  `pkgs/omarchy/nix-bin/omarchy-migrate`, `data/bin-ledger.nix`.

## Constraints

- Never overwrite a user's choice. A port acts only on the state upstream's
  migration acts on, and changes nothing otherwise. That covers a layout the
  user has edited around the anchor, which upstream's split keeps as it is,
  and a layout with no `centerAnchor`, which upstream leaves alone.
- Never write `shell.json` directly. Changes go through the running shell's
  own writer, as the post-boot hook in `modules/home.nix` (around line 2285)
  already does for plugins.
- Runs once per user, with a marker in that user's home, and is idempotent.
  Running it twice gives the same file.
- Mode A: someone importing `nixosModules.nixarchy` with Omarchy turned off
  sees no change (§7).
- Do not run upstream's migrations wholesale. 29 use sudo, 12 write under
  `/usr` and 8 call pacman (`omarchy-migrate`'s own count), so the reasoning
  for the stub still holds. Port the user-file part only.
- Any check written for this has to be shown to fail (§1). A fixture of a
  v4.0.6 `shell.json` is the variable that matters (§3): every check today
  boots a fresh v4.5.0 seed and cannot see this.
- No mise. The mise-wrapper migrations are covered by #1625.

## Open questions

1. **Scope.** Port only the bar (`1791969355`, `1791968925`, `1790042972`,
   `1790528634`) and record a decision for the other 40, or port every one
   that changes something visible?
2. **Where it runs.** Activation cannot edit the live file (see Constraints).
   Should the bar migrations reuse the existing post-boot hook path, which
   waits for the shell and uses its IPC writer? Or should they run before the
   shell starts in the session, when nothing holds the file yet?
3. **Marker.** Each user has their own marker, either way. Should it go in
   upstream's own migration state directory under the user's home, so a later
   port of `omarchy-migrate` could share it, or should nixarchy keep a marker
   of its own?

### The 44 migrations that touch user files (v4.0.6 → v4.5.0)

`1786719479` Antigravity for Gemini · `1786967403` Kimi wrapper ·
`1787215824` hey wrapper · `1787342993` ori wrapper · `1787573629` mise
wrapper output · `1787679775` named workspace layouts · `1788129995` Omasnap ·
`1788261467` keyring Secret portal · `1788281348` re-stage theme intros ·
`1788941927` basecamp wrapper · `1789310715` cf wrapper · `1789764927` OWE
video backgrounds · `1790042972` Elsewhen on the bar · `1790457067` Node pin ·
`1790528634` Elsewhen rename · `1790539857` Monologue · `1790542069` Hype ·
`1790863209` Grok via mise · `1791123731` transparency example ·
`1791345484` Disktree · `1791376887` Chromium overlay scrollbars ·
`1791382872` mise lazy shims · `1791470456` WebP background repair ·
`1791479273` keep Voxtype · `1791676907` Shift out of an IME ·
`1791696584` web app window names · `1791698594` layouts as modes ·
`1791705142` opaque without animations · `1791708587` Signed ·
`1791722809` herdr tab bar · `1791723398` Neovim line background ·
`1791769486` USB/Thunderbolt approval · `1791875754` web app names, own
command · `1791968925` bar tray order · `1791969355` bar centre split ·
`1792259038` renumbered backgrounds · `1792343225` mise prune setting ·
`1792345511` T3 Code app · `1792474908` Brave Origin Copy URL ·
`1792648436` 4.0 notification leftovers · `1793315076` Apple Silicon shell ·
`1793477875` dictation on Alt+Space · `1793565796` OpenCode 2 theme ·
`1793667581` Superwhisper setup.

This list was made by grepping each new migration for `HOME`, `XDG_CONFIG`,
`.config` and `shell.json`. That is a triage, not a classification.
