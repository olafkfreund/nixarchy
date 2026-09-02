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
the one thing a repository written elsewhere cannot know. Run
`nixarchy config repo` on the new machine to push it.

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
