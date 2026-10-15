---
title: Omarchy Channels
---

# Omarchy channels: stable, edge or your own checkout

Omarchy is developed on a branch called `quattro`, and its releases are cut
from it. nixarchy lets you choose which Omarchy your desktop runs:

| channel | what you get | who it is for |
|---|---|---|
| **stable** (the default) | Omarchy's latest release | everyone |
| **edge** | Omarchy's development branch, `quattro`, after nixarchy has built and booted it | trying what is coming before it is released |
| **dev** | Omarchy built from your own git checkout | working on Omarchy itself |

This is a separate choice from **which nixpkgs** you build on (stable 26.05 or
unstable; see [Stable or unstable](channels)). Any pairing works: edge Omarchy
on unstable nixpkgs, stable Omarchy on 26.05, and so on. Changing one never
touches the other.

## Switching

From the menu: **Update ▸ Channel**, then *Stable*, *Edge* or *Dev*. The one
you are on is ticked.

Or from a terminal:

```bash
nixarchy channel omarchy              # which one this machine runs
nixarchy channel omarchy edge         # switch to edge
nixarchy channel omarchy dev ~/omarchy  # build from your checkout
nixarchy channel omarchy stable       # back to the release
```

It edits one line of `/etc/nixos/flake.nix` and keeps the old file as
`flake.nix.pre-channel`. It asks before it writes. Then it re-locks and tells
you to rebuild:

```bash
nh os switch
```

Nothing changes until that rebuild. If the re-lock fails (offline, say), the
flake is put back as it was.

## Edge: the next release, tested first

Edge is not the raw tip of `quattro`. It is a nixarchy branch, `edge`, that a
nightly job moves forward, **only after** that day's `quattro`:

1. builds with every NixOS patch nixarchy carries;
2. passes the same checks a release does: the menu, the command ledger, the
   option set, and three booted desktops.

When something upstream breaks on NixOS, edge simply stays where it is. A
rolling issue labelled
[`omarchy-edge`](https://github.com/olafkfreund/nixarchy/issues?q=label%3Aomarchy-edge)
says what broke. So edge can lag `quattro` by a few days, but it does not move
to something that does not boot.

`nixarchy version` shows the date edge was cut, for example
`edge-20261015-246f33a (edge)`.

**What edge carries without a NixOS port yet** is listed in
[#1280](https://github.com/olafkfreund/nixarchy/issues/1280): language
switching, and the fingerprint reader's resume hook. The passwordless-sudo
toggle is hidden. Each one is being ported, and lands on stable with the
release that brings it.

## Dev: your own checkout

For working on Omarchy itself:

```bash
git clone https://github.com/basecamp/omarchy ~/omarchy
nixarchy channel omarchy dev ~/omarchy
nh os switch
```

- **Commit, then update.** Your flake follows the branch the checkout was on
  when you switched, locked at its last commit. Uncommitted edits are not
  built. After a commit:

  ```bash
  omarchy update --nixarchy
  ```

  That picks up the new commit along with nixarchy.
- **nixarchy's NixOS patches are applied to your checkout**, the same ones
  edge uses. If your change moves something nixarchy patches, the rebuild
  fails and says where. That is the signal to update the patch.
- To follow a different branch, check it out and run the `dev` command again.

## Going back

```bash
nixarchy channel omarchy stable && nh os switch
```

Or boot the previous generation from the boot menu, which needs no network
and no rebuild.

## On a NixOS machine with your own flake

If you added nixarchy to a NixOS configuration you already had, rather than
installing from the ISO, the channel is still one line: the `url` of your
`nixarchy` input.

| your `nixarchy.url` | what you run | what `nixarchy channel omarchy` reports |
|---|---|---|
| `github:olafkfreund/nixarchy/release` | stable releases | stable |
| `github:olafkfreund/nixarchy/v4.0.4-3` (a tag) | that release, pinned | custom |
| `github:olafkfreund/nixarchy` (no branch) | **`main`**: every merge, ahead of releases | stable |
| `github:olafkfreund/nixarchy/edge` | edge | edge |

### Switching with the command

`nixarchy channel omarchy …` works on your flake too. Point it at your flake
with `NIXARCHY_FLAKE` if it is not in `/etc/nixos`:

```bash
NIXARCHY_FLAKE=~/nixos-config nixarchy channel omarchy edge
```

It edits your flake only when the input is written as a block, which may
contain nested `inputs.* = { … };` lines:

```nix
nixarchy = {
  url = "github:olafkfreund/nixarchy";
  inputs.nixpkgs.follows = "nixpkgs";
};
```

It rewrites only that `url` line, plus two lines for dev. Any other shape is
refused and the file is left untouched. That includes the dotted form
`nixarchy.url = "…";`, a fork, a pinned tag, or a local path. Edit it by hand
then.

> **A bare URL follows `main`, not releases.** The command reports it as
> stable, because it is neither edge nor dev, so `nixarchy channel omarchy
> stable` says there is nothing to do. On such a machine, stable means `main`.

### Switching by hand

Edge: change the one line, then re-lock and rebuild.

```nix
nixarchy = {
  url = "github:olafkfreund/nixarchy/edge";   # …/release for stable; no branch for main
  inputs.nixpkgs.follows = "nixpkgs";
};
```

```bash
nix flake update nixarchy
sudo nixos-rebuild switch --flake .#<host>
```

Dev: add your checkout as a top-level input and point nixarchy at it. Name
the branch you work on, since only committed work is built:

```nix
omarchy = {
  url = "git+file:///home/you/omarchy?ref=main";
  flake = false;
};
nixarchy = {
  url = "github:olafkfreund/nixarchy/edge";
  inputs.omarchy.follows = "omarchy";
  inputs.nixpkgs.follows = "nixpkgs";
};
```

```bash
nix flake update nixarchy omarchy
sudo nixos-rebuild switch --flake .#<host>
```

### Trying edge on one machine first

The channel is a property of the flake, so a config repo serving several
machines moves them all together. To try edge on one machine, give that
host its own copy of the input (or build it from a branch of your config
repo with the edge URL), and leave the others on stable.

## Checking where you are

```bash
nixarchy doctor
```

reports both choices: which nixpkgs and which Omarchy. For dev it also names
the checkout.

## Related

- [Stable or unstable](channels): the nixpkgs choice
- [Updates](updates): what moves when you update
- [Getting started](getting-started): adding nixarchy to NixOS you already run
