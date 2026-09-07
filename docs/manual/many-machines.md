---
title: Many machines, one repo
---

# Many machines, one repo

Everything below is about a machine the nixarchy installer wrote. If you added
nixarchy to a NixOS configuration you already run, **none of this touches it**
— your flake is yours, nothing here changes its shape, and the one option that
could rebuild your machine from somewhere else is off unless you turn it on.

## The shape

`/etc/nixos` is a git repository, and each machine is a directory in it:

```
/etc/nixos
├── flake.nix              finds machines by reading ./hosts
├── flake.lock
├── disk-config.nix
└── hosts/
    ├── desk/
    │   ├── default.nix                username, disk, encryption
    │   ├── configuration.nix          timezone, keymap, and whatever you add
    │   ├── hardware-configuration.nix generated on that machine
    │   ├── nixarchy-hardware.nix      what that machine IS, detected
    │   └── nixarchy-apps.nix          this machine's app selection
    └── laptop/…
```

Adding a machine is adding a directory. There is nothing to edit in
`flake.nix` — it reads `./hosts` and builds one `nixosConfiguration` per
directory it finds.

**`git add` is not a tidiness rule.** A flake in a git worktree sees only
tracked or staged files, so an unstaged `hosts/laptop/` does not exist as far
as evaluation is concerned — and the error says the path is missing, not that
it is untracked.

## The loop

**1. Get the first machine into git.**

```
nixarchy config repo
```

It commits, creates the remote, adds a CI workflow and pushes. Everything it
does is idempotent, so a repository you set up half by hand gets the other
half rather than an argument.

**2. Install the second machine from that repository.**

```
nixarchy-install --from github:you/config --host laptop
```

If `hosts/laptop/` is already there, the repository decides the disk, the
username and the rest, and you are asked only for a password. If it is not,
you are asked the usual questions and the machine is written into the
repository beside the others.

**3. Commit its hardware back.**

`hardware-configuration.nix` is generated on the machine, because hardware is
the one thing a repository written elsewhere cannot know. So is
`nixarchy-hardware.nix` beside it — see below. Run `nixarchy config repo` on the
new machine to push both.

### `nixarchy-hardware.nix`, and why it is per-machine

Written by the installer from what it found on the machine: CPU vendor, GPU
vendor, whether there is a battery, whether the disk spins. Each line is a
module from [nixos-hardware](https://github.com/NixOS/nixos-hardware), which
carries 439 of them:

```nix
{ inputs, ... }:
{
  imports = [
    inputs.nixos-hardware.nixosModules.common-cpu-intel-cpu-only
    inputs.nixos-hardware.nixosModules.common-gpu-intel
    inputs.nixos-hardware.nixosModules.common-pc-laptop-ssd
  ];
}
```

That is CPU microcode, the Intel media stack, and `fstrim` — things you would
otherwise have found out you needed one at a time. Everything they set is
`lib.mkDefault`, so anything you write elsewhere wins, and the file is yours to
edit: nothing regenerates it behind you.

**Only the generic `common-*` modules are chosen for you**, and that is a
deliberate line. The other 412 key on DMI product strings with no
machine-readable table anywhere, so matching them automatically would mean
guessing — and importing `dell-xps-13-9310` onto a 9315 is a machine that boots
wrong in a way nobody traces back to us. `nixarchy doctor` prints what your
machine calls itself so you can search for it; add any match to this file by
hand. Plenty of machines have no module at all — there are thirteen ThinkPad T14
modules and no T15 — and the generic ones are then the whole story.

**NVIDIA is never chosen for you either.** The choice is between the open kernel
modules and the `legacy_580` series, split at PCI device id `0x1e00`, and on a
hybrid laptop it also needs both PRIME bus ids in decimal. Get any of that wrong
and the machine has no screen, which is not a failure a first boot can explain.
The doctor computes all of it and prints the lines for you to paste.

Copying this file from another machine is the one thing not to do — it describes
that machine's hardware, not this one's.

**4. Let them keep themselves current.**

```nix
programs.nixarchy.fleet = {
  enable = true;
  url = "github:you/config";
};
```

A timer pulls and rebuilds. `nixos-rebuild` picks the configuration matching
the machine's hostname, so **one value serves every machine** — you do not
list them anywhere.

> **The running system comes from the remote flake.** Local edits under
> `/etc/nixos` that you never pushed are reverted at the next pull, silently.
> That is the point of a fleet, and it is also the way to lose an afternoon.

If an upgrade fails, the machine writes a timestamped line to
`/var/lib/nixarchy/upgrade-failed`. That exists because the documented way
unattended upgrades go wrong is that they start failing and then stop
delivering configuration, and nothing says so — a fleet that has quietly
stopped converging looks exactly like one that is up to date.

## Pushing instead of pulling

Nothing in nixarchy is involved. `nixos-rebuild` does it:

```
nixos-rebuild switch --flake github:you/config#laptop --target-host root@laptop
```

For more than a handful of machines, or for anything with roles and tags,
use a tool built for it — [colmena](https://github.com/zhaofengli/colmena),
[deploy-rs](https://github.com/serokell/deploy-rs) or
[clan](https://clan.lol/). nixarchy does not reimplement them and does not
need to: the repository is an ordinary NixOS flake and they all take one.

## Using somebody else's configuration

There is no template mechanism, and there does not need to be one. Point the
installer at their repository with a machine name it has never heard of:

```
nixarchy-install --from github:them/config --host mine
```

The questions are asked as usual, your machine is written in beside theirs,
and everything else they wrote — themes, extra modules, their app selection —
comes with it. Then `git remote set-url origin <yours>` and it is your
repository.

This is only safe to offer because the login hash does not live in the
repository. It is at `/var/lib/nixarchy/password.hash`, outside git, so a
configuration is safe to push and safe to hand to somebody.

> **`--from` runs their Nix as root.** Their `disk-config.nix` is what
> formats your disk. This is the same trust as `nix run github:...`, and it
> is worth saying out loud rather than leaving implied. The installer asks
> before it clones.

## Unattended

See [unattended installs](unattended-installs).
