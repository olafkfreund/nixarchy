---
title: Stable or unstable
---

# Stable or unstable

Omarchy lets you pick a release channel. So does nixarchy — **Update ▸ Channel**
in the menu, or:

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
that the desktop comes up. Nothing starts a VM on stable, because the install
job is already the slowest thing in the project and doubling it would slow every
change for everyone.

So: fewer people run stable here, and the automated evidence behind it is
thinner. If you want the combination that is actually exercised, that is
unstable.

## What each one means

| | stable | unstable |
|---|---|---|
| nixpkgs | `nixos-26.05` | `nixos-unstable` |
| home-manager | `release-26.05` | tracks master |
| package versions | frozen until the next release | move continuously |
| tested by nixarchy | evaluation only | everything |

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

## Checking where you are

```
nixarchy doctor
```

reports which channel the machine follows, says plainly that nixarchy is tested
against unstable if you are on stable, and counts any packages you have taken
from the other channel — because a duplicated closure is invisible until a disk
fills.

## Related

- [Updates](updates) — what moves when, and what does not
- [Updating NixOS](updating-nixos) — the rebuild loop underneath all of this
- [Other packages](other-packages) — adding packages in the ordinary way
