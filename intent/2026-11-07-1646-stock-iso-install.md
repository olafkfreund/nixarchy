---
status: draft
issue: 1646
author: x
---

# Intent: Install from the stock NixOS ISO, with no image of our own

A maybe, for later. The owner wants everything else finished first (#1646).

## Problem

Since #1648, a release publishes one network image, `iso-net` (1.79 GiB),
and every install needs a network. The image mostly does two jobs: it starts
the installer on tty1 with our branding, and it writes the
`/etc/nixarchy-iso-net` marker (`installer/cd.nix:436`) that switches on the
network-only steps in `installer/install.sh`. The installer itself is already
a flake package with its own runtime tools (`flake.nix:956`, `#install`), so
in principle a stock NixOS minimal ISO could run it:

```bash
sudo nix --extra-experimental-features 'nix-command flakes' \
  run github:olafkfreund/nixarchy#install
```

Nobody has run this on a stock ISO, and the code says it would be less safe
than our image:

- `ask_network` (`installer/install.sh:463`) and `preflight_build`
  (`installer/install.sh:2526`) both start with `on_net_image || return 0`.
  On stock media there is no marker, so the cache reachability probe and the
  dry-run plan are skipped, and an install can fail after `format_disk` has
  wiped the disk. That is the #300 failure the preflight exists to prevent.
- The marker check also stands in for "this is a live install with no seeded
  store". Its only other meaning today is "not `checks.install`", which runs
  with no network, no marker and a seeded store. A fix must keep that check's
  preflight skipped.
- The stock live store is a tmpfs overlay too, so `check_store_space` and the
  `--store /mnt` fallback carry the same weight as on our image, unmeasured.
- Our image lists nixarchy.cachix.org and hyprland.cachix.org in its own
  `nix.conf` (`installer/cd.nix:400`). The build passes them explicitly
  (`installer/install.sh:2686`), but the preflight's dry-run passes only
  `SUBSTITUTE_FLAGS` (`installer/install.sh:71`). On a stock ISO, once the
  preflight runs there, it would plan without our caches and report most of
  the desktop as "will be built".
- Not the install itself, but a stock ISO also lacks our `/etc/gitconfig`
  `safe.directory` entry (`installer/cd.nix:412-432`). That entry is for a
  rescue `nixos-install` after `/etc/nixos` has been chowned to the user; the
  chown runs after `run_install` (`installer/install.sh:3067-3069`), so the
  install does not need it.

## Proposed outcome

The smallest outcome worth having: **a documented, tested `nix run` command
that installs nixarchy from the stock NixOS minimal ISO, and is as safe as our
image before the disk is touched.**

1. The network preflight runs on stock media too, with our caches, not only
   on our image. A dead cache or an unplannable system on stock media refuses
   with "the disk has not been touched", the same as on `iso-net`.
2. A VM check on the stock minimal ISO with two cases: an install with
   `--answers` that records time to the first question, bytes downloaded and
   peak live-store use; and a dark cache that is refused with the disk left
   intact. A success alone cannot show the preflight ran (CLAUDE.md §1).
3. One manual section (in `docs/manual/the-iso.md`, or `unattended-installs.md`
   for the `--answers` form) gives the command, says it is the advanced path,
   says what it does not give you, and names the NixOS ISO release and
   nixarchy revision the check last passed with.

Not covered by this outcome:

- Removing `iso-net`. That is a separate decision, taken only after (2) has
  numbers, and it also has to answer #1649 (a replacement must tell the
  installer which machine it is restoring).
- Our branding, the tty1 autostart, the newest kernel during install, or Wi-Fi
  setup before the command. On a stock ISO the user joins the network
  (`nmtui`) and types the command themselves.
- A `#try` path from the stock ISO.

## Affected users and systems

- People who already run NixOS media, fleets that netboot the stock image, and
  anyone who cannot download our 1.79 GiB image.
- `installer/install.sh` (the `on_net_image` gate), `flake.nix`'s `#install`
  package, a new check under `tests/`, and the manual.
- Not affected: `iso-net`, `checks.install`, the installed system.

## Constraints

- `checks.install` must keep its preflight skipped: no network, seeded store
  (`installer/install.sh:2490`). Whatever replaces the marker test must be a
  property a check can vary (CLAUDE.md §3), not a second marker the stock ISO
  happens to lack.
- The new VM check is VM tier: it needs a VM job, so its workflow placement is
  a CI-gate change a human decides (CLAUDE.md §4, §11).
- The stock ISO's version is not ours to pin. The check pins one NixOS release
  ISO by hash, and the manual names the release it was tested against.
- `iso-net` and `install.sh` stay unchanged in behaviour for our image.

## Open questions

1. **Do it at all, and when?** Recommendation: not before the current queue is
   clear, as the owner said. If only one part is taken, take the preflight
   fix: it is small, and someone running `nix run …#install` from a stock ISO
   today can lose a disk to it.
2. **What switches the preflight on?** A stock ISO has a store too, so "the
   store is seeded" is not the distinction. What separates `checks.install`
   is that the target closure is already present and no network is expected.
   Recommendation: the spec names that condition directly and tests both
   sides of it, rather than testing for our marker.
3. **Document before the VM check exists?** Recommendation: no. An untested
   documented command is a promise nobody has kept; land the check first.
4. **Rescue from a stock ISO.** A rescue `nixos-install` against a user-owned
   `/mnt/etc/nixos` fails without our `safe.directory` entry, and
   `git -c` cannot fix it, because libgit2 does not read it
   (`installer/cd.nix:425-429`). Recommendation: out of scope here; the manual
   section tells rescuers to keep using our image, or to add the entry by hand.
5. **Should this lead to dropping `iso-net`?** Recommendation: decide after
   the numbers from (2) and #1649, in its own issue.
