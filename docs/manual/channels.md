---
title: Stable or unstable
---

# Stable or unstable

A machine makes two separate choices here, and this page covers both:

- **which nixpkgs** it builds on, stable or unstable. That is _Update ▸ Nixpkgs_,
  and most of this page;
- **which Omarchy** it runs: stable, edge or your own checkout. That is
  _Update ▸ Channel_; see [Omarchy: stable, edge or your own
  checkout](#omarchy-stable-edge-or-your-own-checkout).

Any pairing works, and switching one never moves the other. For nixpkgs:

```
nixarchy channel              # which one this machine follows
nixarchy channel stable       # nixos-26.05, and the matching home-manager
nixarchy channel unstable     # nixos-unstable
```

## The uncomfortable part, first

**"Stable" sounds safer, and here it is less tested.**

nixarchy is developed against unstable. The flake pins `nixos-unstable` and
every check runs against whatever that locks to. Stable is a real answer, not a
supported one.

What CI proves about stable is narrow and worth knowing exactly: a check
evaluates this flake against `nixos-26.05` on every change, in about twenty
seconds. That proves the configuration is **valid** on stable — every attribute
exists, every option is an option. It does **not** prove the machine boots or
that the desktop comes up. That part is checked weekly instead: a VM boots a
desktop session on stable every Sunday night. (Currently red: on 26.05 the
login screen cannot load the GPU driver, Issue #1211.) It is not run on every change,
because the install job is already the slowest thing in the project and
doubling it would slow every change for everyone.

So: fewer people run stable here, and the automated evidence behind it is
thinner. If you want the combination that is actually exercised, that is
unstable.

## What each one means

| | stable | unstable |
|---|---|---|
| nixpkgs | `nixos-26.05` | `nixos-unstable` |
| home-manager | `release-26.05` | tracks master |
| package versions | frozen until the next release | move continuously |
| tested by nixarchy | evaluated on every change; a session boot weekly | everything |

Switching moves **both** nixpkgs and home-manager, and that is not a
convenience. The two are developed as a pair, and a machine on stable nixpkgs
with a master home-manager is a combination neither project supports —
home-manager itself warns about it. `nixarchy channel` does both edits or
neither.

## What it does not change

**Hyprland comes from upstream either way.** The compositor is pinned to
`github:hyprwm/Hyprland`, not taken from nixpkgs, so choosing stable does not
give you a stable compositor. Same for Omarchy itself, which is pinned to a
release.

So the choice is about your *package set* — your browser, your editor, your
libraries — and not about the desktop.

## Your flake stays yours

`nixarchy channel` edits `/etc/nixos/flake.nix`, and it does that under one
rule: **only lines this project wrote get rewritten.** If you have reshaped
your flake, it refuses and prints the edit for you to make, rather than
guessing. It backs up first and re-locks only what moved.

## One package from the other channel

You do not have to move the whole machine to get one newer package.

```
nixarchy pkg add --unstable helix     # on a stable machine
nixarchy pkg add --stable   vlc       # on an unstable one
```

**This is expensive, and the number is not intuitive.** The two channels share
**nothing** in the nix store — not "less", nothing — even where the version is
identical. Measured: `btop` at the same version on both is **0 shared paths and
51 MB duplicated**; `vlc 3.0.23-2` is **1.5 GB**.

So it is a deliberate per-package decision, never a default. The command tells
you what channel the machine is on, refuses if you asked for the one you are
already using, and prints the two lines you need to add to your own `flake.nix`
— it does not edit that file for you, because adding an input is your decision.

**Packages only.** A NixOS *option* comes from the package set the system is
evaluated with, so `services.foo.enable` cannot be taken from the other
channel. Only packages cross.

## Omarchy: stable, edge or your own checkout

```
nixarchy channel omarchy              # which one this machine runs
nixarchy channel omarchy stable       # the release Omarchy, the default
nixarchy channel omarchy edge         # Omarchy's quattro branch, tested here first
nixarchy channel omarchy dev ~/omarchy  # your own Omarchy checkout
```

**Stable** is what every machine starts on: Omarchy's latest release, behind
nixarchy's `release` branch.

**Edge** is Omarchy's development branch, `quattro`. It is the next release
before it is one. Your flake follows nixarchy's `edge` branch instead of
`release`. That branch moves at most once a day, and **only after the
desktop boots and its checks pass** with that day's `quattro`. So edge can
stand still for a while, but it does not move to something broken.
`nixarchy version` shows the date it was cut. Features edge carries without a
NixOS port yet are listed in
[#1280](https://github.com/olafkfreund/nixarchy/issues/1280).

**Dev** builds Omarchy from your own git checkout, for working on Omarchy
itself. nixarchy's NixOS patches are applied to it, so a change of yours that
moves something nixarchy patches fails the rebuild and says where. Two
things to know:

- **Commit, then update.** The checkout is locked by commit, so uncommitted
  edits are not built. After a commit, `omarchy update --nixarchy` picks it up.
- Dev uses the **edge** branch's patch set, the one closest to Omarchy's
  development branch.

To go back, run `nixarchy channel omarchy stable`. The previous `flake.nix` is
kept as `flake.nix.pre-channel`, and the previous generation is still in the
boot menu.

## Checking where you are

```
nixarchy doctor
```

reports which nixpkgs channel and which Omarchy channel the machine follows, says plainly that nixarchy is tested
against unstable if you are on stable, and counts any packages you have taken
from the other channel — because a duplicated closure is invisible until a disk
fills.

## Related

- [Updates](updates) — what moves when, and what does not
- [Updating NixOS](updating-nixos) — the rebuild loop underneath all of this
- [Other packages](other-packages) — adding packages in the ordinary way
