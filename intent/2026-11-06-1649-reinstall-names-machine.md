---
status: approved
issue: 1649
author: x
---

# Intent: A reinstall image installs the machine it was built from

## Problem

`nixarchy reinstall iso` promises "boot it on new hardware and you get this system back". It can't keep that promise, so since #1648 it runs its preflights and then refuses to build.

- `mkUserIso` (`flake.nix`) only passes `source.flake`. `installer/cd.nix` uses `source` for `inputSources` and the image's version string, and the machine's name reaches nothing.
- The installer gets `--from` and `--host` only from the kernel command line (`installer/cd.nix`, `nixarchy.from=` and `nixarchy.host=`). Without them, `main()` calls `write_flake`, which writes a stock configuration.
- So a person's image would erase a disk and install a stock nixarchy. This comes from reading the code. Nobody has booted one, and Codex raised it on #1648.
- The offline image got around this with `/etc/nixarchy-reference-*`, naming a toplevel it carried. By the same reading, the old `--net` variant already installed stock.

The way back today needs a pushed git repository: boot the published image with `nixarchy.from=<repo> nixarchy.host=<name>`. A person who loses a disk with an unpushed `/etc/nixos` has no route back, and that is the case this command exists for.

## Proposed outcome

- `nixarchy reinstall iso` builds an image again, and the refusal from #1648 is gone.
- Booting that image on a blank disk installs that machine's own configuration: same host name, packages, services and settings, fetched from caches at install time.
- `/etc/nixos` on the new disk is the repository the image carried. Whether its history and remote come along is for the spec.
- The published image behaves as it does today, with no machine named.
- The manual page stops saying the command is unavailable.

## Affected users and systems

- Anyone who wants a way back after losing a disk.
- `installer/cd.nix`, `flake.nix`'s `mkUserIso`, possibly `installer/install.sh`, `pkgs/omarchy/nix-bin/nixarchy-reinstall-iso`, `docs/manual/reinstall-image.md`, `tests/reinstall-iso.nix`, `tests/install-matrix.py`.
- Not the published image, Mode A, or a machine that never runs this command.

## Constraints

- Booting the image still erases the target disk, so the confirmation stays.
- The image holds the person's `/etc/nixos`, so it stays private. Nothing here publishes it, and the command keeps saying so.
- It must not carry a closure: #1647 removed that on purpose.
- A kernel command line naming a different repository or host still wins, as a pair: an image must never combine its own repository with someone else's host name, or the reverse.
- Secrets the repository doesn't hold stay missing, as they do today. The command says it isn't a backup.

## Open questions

**1. How does the image hand its flake to the installer?** `clone_repo` runs `git clone` and requires `hosts/`, and `--host` already lets the repository decide the disk. *I recommend* the image carrying the flake as a small git repository plus the host name, with the launcher passing them as `--from` and `--host`. That reuses a tested path. The alternative, teaching `install.sh` to read a store path, is a second route to the same place. The spec settles this.

**2. What happens when the new machine's disk has a different path?** The installer takes an existing host's disk from that host's `disk-config.nix` and refuses a device that isn't there. "New hardware" is the command's main promise, and a saved `/dev/nvme0n1` on a machine with `/dev/sda` would stop before formatting. *I recommend* asking which disk to use when the saved one is absent, and writing the answer into the host's file, since the disk is about to be erased anyway and the person confirms it. The alternative is to promise only a same-path replacement disk, which is much less useful.

**3. Should a personal image be installed end to end by a check?** `reinstall-vm` did that for the offline route, and #1647 removed it as too large. *I recommend* a smaller check on the built image: its launcher passes those arguments, `clone_repo` accepts the carried repository, and a wrong host fails. The full install stays a named hole. The owner may want the full check back instead, at about `install-iso-net`'s cost.
