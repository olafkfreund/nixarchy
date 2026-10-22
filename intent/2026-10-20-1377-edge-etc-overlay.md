---
status: approved
issue: 1377
author: olafkfreund
---

# Intent: edge knows what every file in quattro's /etc is for

## Problem

`data/etc-overlay.nix` holds one row per file in Omarchy's `etc/` tree,
each saying what answers that file on NixOS: installed, native, covered or
not applicable. `checks.etc-overlay` fails when a shipped file has no row.
On `main`, PR CI runs it, and it caught 4.0.6's new vconsole drop-in
today (#1374).

**Edge never runs it.** `omarchy-edge.yml`'s verify step builds a fixed
list (`menu-verbs menu-actions bin-ledger skill-parity panel-loaders
review-pins stable-eval`), and edge has no PR CI. Quattro has kept adding
`/etc` files, and edge's verify has stayed green while
`checks.etc-overlay` on edge is red, with 13 files unclassified (measured on
2026-10-20, quattro 4f920a2):

- `mise/conf.d/omarchy-agent-accounts.toml`
- `mise/conf.d/omarchy-tools.toml`
- `mkinitcpio.conf.d/00-omarchy-hooks.conf`
- `mpv/mpv.conf`
- `sudoers.d/omarchy-locale-generate`
- `sysctl.d/90-omarchy-arp.conf`
- `systemd/system.conf.d/20-mount-events.conf`
- `systemd/system/proc-sys-fs-binfmt_misc.mount.d/10-omarchy-conditions.conf`
- `systemd/system/systemd-binfmt.service.d/10-eager-mount.conf`
- `systemd/user/wayland-wm@hyprland.desktop.service.d/10-keep-shell.conf`
- `udev/rules.d/60-omarchy-io-scheduler.rules`
- `xkb/rules/evdev`
- `xkb/symbols/omarchy`

Each is a decision nobody has made. Some are probably Arch-only, such as
mkinitcpio or `locale-gen` through sudoers. Others are behaviour an edge
user may be missing without anyone knowing, such as the Hyprland session
unit drop-in, the io scheduler, the ARP sysctl, the binfmt drop-ins, mpv
defaults, and a custom xkb layout.

## Proposed outcome

- **Every file quattro ships under `etc/` has a row on edge**, with a
  reason someone has read the file for. A file that needs a NixOS
  equivalent either gets one in this change, if it is small, or its own
  issue, with its row saying so.
- **Edge verify runs `checks.etc-overlay`**, so the next quattro bump that
  adds a file turns edge red instead of shipping silently.
- `main` is untouched, apart from the workflow, since stable 4.0.6 ships
  none of these files.

## Affected users and systems

- Edge-channel users: p620, razer, and anyone else on `edge`.
- Edge's `data/etc-overlay.nix`, on `edge-candidate`. These rows cannot go
  on `main`, where `etc-overlay` would call them stale and fail.
- `.github/workflows/omarchy-edge.yml` on `main`, which adds one check name
  to the verify list.
- Possibly `modules/`, if a file needs a NixOS equivalent. That code would
  live on edge or `main` depending on whether stable needs it.

## Constraints

- **A workflow edit is a CI-gate change (CLAUDE.md §11).** It goes in its
  own PR to `main` with the reasoning, and you merge it.
- **Order matters.** If the workflow change lands before edge's rows, the
  next edge run goes red on all 13. So the rows go onto `edge-candidate`
  first, and the workflow PR merges after them.
- **Edge-only rows survive merges.** When `main` is next merged into
  `edge-candidate`, the rows must not conflict away. They go where `main`
  and `edge` agree, proved by a trial merge, which is the same lesson as
  #1356 and #1368.
- §1: `etc-overlay` is proved red on the current edge (already measured)
  and green with the rows. The workflow step is proved to fail an edge run
  when the check is red. Reverting one row and running the step's command
  in a scratch tree shows that.
- Every reason is written from reading the file, not from its name (§12:
  search for the behaviour).

## Open questions

- **Files that need an equivalent.** Reading may show that some of the 13
  do something a nixarchy desktop should do too: likely the Hyprland
  `10-keep-shell` drop-in, the io-scheduler udev rule, or the ARP sysctl. I
  propose that this change classifies all 13, implements only equivalents
  that are a line or two, and files an issue for anything larger, marking
  its row "covered by #N" until then. Is that the split you want?
- **Does the same gap exist for other checks?** Edge verify also skips, for
  example, `patched-files`. I propose limiting this to `etc-overlay`, and
  noting in the spec any other inventory check edge skips, as a follow-up
  rather than scope here.

## Decisions (owner, 2026-10-20: "use your recommendations")

- Classify all 13. Implement an equivalent only where it is a line or two,
  and file an issue for anything larger, its row reading "covered by #N".
- Scope is `etc-overlay` alone. Other inventory checks edge skips are
  listed in the spec as follow-ups.
