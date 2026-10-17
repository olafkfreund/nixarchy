---
status: draft
issue: 1303
author: olafkfreund
---

# Intent: Menu conditions that give the wrong answer on NixOS

## Problem

Some menu rows decide whether to show, or whether to show a tick, with a
check written for Arch. On NixOS these checks do not fail. They give a wrong
answer, so a row is hidden that should be shown, or shown when it should not
be, and nothing reports it.

Rechecked on main (`7e0ceac5`) against the tree in `/run/current-system`:

- **Hibernate is never shown.** `omarchy-hibernation-available` checks
  `/sys/power/image_size` and non-zram swap, then also requires
  `/etc/mkinitcpio.conf.d/omarchy_resume.conf`. Only Omarchy's Arch installer
  writes that file. A NixOS machine set up as
  `docs/manual/troubleshooting.md` describes (disk swap, `boot.resumeDevice`)
  can hibernate, but the row stays hidden. The check is upstream's, and
  quattro has the same check. nixarchy has no hibernation option, and zram,
  the default, cannot hibernate (`modules/nixos.nix:2047`). The manual's
  swap-file recipe also leaves out `resume_offset`. NixOS needs that
  parameter to resume from a swap file.
- **Choosing Helix does nothing, and the row is never shown.** The upstream
  row's `when` is `omarchy-cmd-present helix`, but nixpkgs installs the
  binary as `hx`. If the row is reached anyway, `omarchy-default-editor helix`
  saves `helix`. `omarchy-launch-editor` then finds no `helix` on PATH and
  opens nvim. So fixing only the `when` would show a row that does not work.
  The menu's Install row knows the binary is `hx` (`tests/options.nix:2305`).
  The Setup row does not.
- **Zen is never offered as the default browser.** The row's `when` is
  `omarchy-cmd-present zen-browser`, but the Zen nixarchy ships provides
  `zen-beta` (modules/AGENTS.md, "`ours` apps"). `omarchy-default-browser zen`
  sets `zen.desktop`. It is not yet checked whether the zen-browser flake
  installs a desktop file with that name. If it does not, choosing Zen would
  fail too.
- **The snapshot rows show on machines without snapper.**
  `system.recovery.snapshot` and `.snapshot.restore` are nixarchy's own rows
  (`modules/apps.nix:560`, `:581`), and neither has a `when`. Only the
  installer configures snapper (`installer/host.nix:341`). On a Mode A
  machine, such as this ext4 workstation, both rows open a terminal that
  only says no. Confirmed: `command -v snapper` finds nothing here.
- **Style › Font lists `cursor.pcf`.** `omarchy-font-list` is
  `fc-list :spacing=100`. The X11 bitmap font `font-cursor-misc` matches it
  with the family name `cursor.pcf`. NixOS adds that font when
  `services.xserver.enable` is on, and nixarchy does not add it itself. It is
  not known whether a stock Arch Omarchy install has the font and shows the
  same entry. That decides whether the fix belongs upstream.
- **The power-profile tick does not move after a switch.** The menu's
  `power-profiles` provider does not have `volatile: true`, which the fonts
  provider has (`Menu.qml:266-280`). Its list is read once and never reread.
  This is upstream code and behaves the same on Arch.

One claim in the issue is out of date. **The channel rows do tick on
`7e0ceac5`.** #1291 changed `omarchy-channel-current` to run
`nixarchy-channel omarchy --current`. On the current system's tree it prints
`stable`. The `dev` in the issue came from a Hyprland session started on
2026-10-14, before that deploy. That session's `PATH` and `OMARCHY_PATH`
still point at the older tree
(`zlhw6r3r…-nixarchy-omarchy-tree`, not in `/run/current-system`), and that
tree has upstream's pacman script. The session also reads the new
`/etc/nixarchy/omarchy-menu.jsonc`. So after a switch, until the user logs
in again, new menu rows run old scripts: `update.nixpkgs.*` call
`nixarchy-channel --current`, which the old script does not accept. That is a
real problem, but a different one: stale scripts after a switch. It is not a
wrong condition.

None of this was caught because the menu checks test that rows have the
right *form*, not that they give the right *answer*:

- `tests/menu-verbs.nix` checks that a `checked` exists and that the channel
  actions are well formed.
- `tests/coverage.py` checks that commands named in rows exist. It compares
  binary names only for the Install rows' `disabled` probes.

Nothing compares a Setup `when` with the binary nixpkgs actually installs.
Nothing runs a `when` on a machine where the answer should be yes.

## Proposed outcome

- A condition is true exactly when the thing it describes is true on the
  NixOS machine it runs on:
  - Hibernate shows on a machine with resume configured, and stays hidden on
    zram.
  - Helix and Zen show when they are installed, and choosing either makes it
    the default that opens.
  - The snapshot rows show only where snapshots work.
  - Style › Font lists only fonts a person could use.
  - The power-profile tick follows the active profile.
- Each condition that is fixed gets a check that can fail at the cheapest
  layer that can change the input that matters (CLAUDE.md §2, §3). Each check
  is shown failing before the fix is restored (§1).
- The hibernation recipe in the manual works as written.
- The upstream defects are written up for the maintainer, who decides whether
  to send them upstream. Nothing is filed anywhere without being asked to.

## Affected users and systems

- Everyone who uses the stock Omarchy menu: Setup › Defaults, System, and
  Style.
- Mode A adopters: the snapshot rows. People who set up hibernation by hand:
  the Hibernate row.
- People who have the Helix or Zen app enabled
  (`programs.nixarchy.apps.helix`, `.zen`).
- Likely files: `modules/apps.nix` (menu overrides), `pkgs/omarchy/default.nix`
  and `data/bin-ledger.nix` (if a `bin/` script is patched),
  `docs/manual/troubleshooting.md`, and the checks under `tests/`.

## Constraints

- **§2 and §3: a check that can fail, at the cheapest layer.**
  - Hibernation depends on the machine having resume configured, and no VM
    boots that way. The check needs a stubbed case with resume configured
    and one without, not just one boot.
  - The Helix and Zen checks need to compare against the binary and desktop
    file the selected package really ships, the way `coverage.py` already
    does for `disabled`. Comparing against a name written in the check is
    not enough.
  - Snapshots need a case with snapper and one without.
- **Mode A.** No new row and no changed default may affect a machine that
  has not enabled the feature. `tests/options.nix` covers both the on and
  off state of any option this adds.
- **§11 upstream routing.** The power-profile cache, and the Arch-only names
  in rows that nixarchy does not override, are Omarchy's behaviour. A patch
  kept here must be re-applied at every source bump. If a fix belongs
  upstream, say so; do not file it unasked.
- **Do not patch a `bin/` script in a way that changes it on Arch.** A
  carried patch uses `--replace-fail`, so an upstream change breaks the build
  instead of shipping a half-applied patch. It also gets a ledger row.
- #1302 changes the same `system.recovery.snapshot*` rows, to fix where
  they appear in the menu. Whichever lands second rebases onto the other
  (§9).
- The channel rows are out of scope unless the stale-scripts problem is
  taken on here (see Open questions).

## Open questions

1. **Stale scripts after a switch.** A running session keeps the old tree's
   `PATH` and `OMARCHY_PATH` but reads the new `/etc` menu. Is that in scope
   here, a new issue, or known behaviour to document ("log in again after an
   update")? Recommendation: a new issue. It affects every row whose script
   changes, not only these.
2. **Hibernation scope.** Should the menu just recognise a NixOS resume setup
   (`boot.resumeDevice` set, enough disk swap, `disk` in `/sys/power/state`),
   or should nixarchy also add an option that sets hibernation up? The first
   is the bug. The second is a feature, and conflicts with the zram default.
3. **Helix and Zen.** Should the menu rows be overridden in `modules/apps.nix`
   from `cfg.apps.<name>.package`, as the Install rows are, or should the
   saved `helix` name be patched in `omarchy-default-editor` and
   `omarchy-launch-editor`? And does the zen-browser flake install
   `zen.desktop`? That needs checking against the pinned input.
4. **`cursor.pcf`.** Does a stock Arch Omarchy install show it? If yes, it is
   upstream's filter and goes in the upstream write-up. If no, filter it here.
5. **Power profile.** #1305 is the issue for Omarchy's own menu code, but
   its list does not include the missing `volatile`. Should this move there,
   so all the upstream menu-code findings are in one place, or stay here?
6. **Install rows: none here.** `install.editor.helix` and
   `install.browser.zen` stay visible after the app is installed. That is
   because `omarchy-pkg-present` in a guard is answered by `pacman`
   (`MenuModel.js:419`), which is #1301. They are left to #1301.
