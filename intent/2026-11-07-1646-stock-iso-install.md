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
- Our image ships `/etc/gitconfig` with `safe.directory = /mnt/etc/nixos`
  (`installer/cd.nix:432`) for root without sudo. Under `sudo` on a stock ISO
  git exempts root only when `SUDO_UID` owns the repository. Whether any git
  or libgit2 call during the install trips on this is not known.

## Proposed outcome

The smallest outcome worth having: **a documented, tested `nix run` command
that installs nixarchy from the stock NixOS minimal ISO, and is as safe as our
image before the disk is touched.**

1. The network preflight runs on any live medium that is not the seeded test
   store, not only on ours. A dead cache or an unplannable system on stock
   media refuses with "the disk has not been touched", the same as on
   `iso-net`.
2. One VM check installs from the stock minimal ISO with `--answers`, and
   records time to the first question, bytes downloaded and peak live-store
   use.
3. One manual section (in `docs/manual/the-iso.md`, or `unattended-installs.md`
   for the `--answers` form) gives the command, says it is the advanced path,
   and says what it does not give you.

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
2. **What switches the preflight on?** Recommendation: run it unless the store
   is seeded (`checks.install`'s condition, stated directly), rather than
   testing for our marker. Spec decides the exact test.
3. **Document before the VM check exists?** Recommendation: no. An untested
   documented command is a promise nobody has kept; land the check first.
4. **Does `sudo` on the stock ISO need our `safe.directory` entry?**
   Recommendation: answer it in the VM check rather than by reading; if it
   does, the installer passes `-c safe.directory` itself.
5. **Should this lead to dropping `iso-net`?** Recommendation: decide after
   the numbers from (2) and #1649, in its own issue.
