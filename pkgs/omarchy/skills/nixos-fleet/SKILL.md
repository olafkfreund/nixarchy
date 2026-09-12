---
name: nixos-fleet
description: >
  REQUIRED for one flake that configures several machines — the `hosts/<name>/`
  layout, what is shared and what is per-machine, adding a second or tenth
  machine, installing one from an existing repository, rebuilding one machine
  from another, and machines that pull their own configuration on a timer. Use
  when asked to add a laptop to an existing configuration, share a module between
  hosts, stop a change for one machine landing on another, deploy to a remote
  host, set up unattended upgrades across several machines, or work out why a
  machine is not picking up the configuration that was pushed. Triggers: hosts/,
  nixosConfigurations, multi-host, several machines, fleet, deploy, remote
  rebuild, --target-host, --build-host, system.autoUpgrade,
  programs.nixarchy.fleet, nixarchy-hardware.nix, nixarchy-apply, colmena,
  deploy-rs, clan, comin, GitOps, "same config on both machines".
  Git itself — remotes, CI, .gitignore, "back up my config" — belongs to
  `nixos-config-repo`; this skill owns the shape of a multi-host flake.
---

# NixOS Fleet Skill

Multi-host is where a configuration stops being a file and starts being a system.
NixOS handles it natively, so most of this skill is a layout and a set of traps
rather than a tool.

**Where this skill stops.** `nixos-config-repo` owns git: `git init`, remotes,
public vs private, `.gitignore`, CI on the flake, dubious ownership, and the
"back up my configuration" question. This skill owns what is *inside* the
repository once more than one machine lives in it. They are adjacent and must not
overlap — if the question is about pushing, cloning or CI, hand it over and stop.

**First, which machine is this?** Everything below is about a machine the
nixarchy installer wrote. If nixarchy was added to a NixOS configuration the user
already runs, **none of this restructures it** — their flake is theirs, and the
one option that could rebuild their machine from somewhere else is off unless
they turn it on. Do not convert a working single-host flake to this layout
uninvited.

## The shape

```
/etc/nixos
├── flake.nix              finds machines by reading ./hosts
├── flake.lock             one lock for every machine — deliberate
├── disk-config.nix
└── hosts/
    ├── desk/
    │   ├── default.nix                 username, disk, encryption
    │   ├── configuration.nix           timezone, keymap, and whatever is added
    │   ├── hardware-configuration.nix  generated on that machine
    │   ├── nixarchy-hardware.nix       what that machine IS, detected
    │   └── nixarchy-apps.nix           this machine's app selection
    └── laptop/…
```

`flake.nix` reads the directory rather than naming machines:

```nix
hosts = lib.attrNames (lib.filterAttrs (_: kind: kind == "directory") (builtins.readDir ./hosts));
```

**Adding a machine is adding a directory.** Copy one, change what differs, `git
add` it. There is nothing to edit in `flake.nix`, and an agent that opens it to
add a `nixosConfigurations.laptop` entry has misread the design. Directories
only: a stray `README` under `hosts/` would otherwise become a configuration that
fails to evaluate for reasons nothing explains.

**`git add` is not a tidiness rule.** A flake in a git worktree sees only tracked
or staged files, so an unstaged `hosts/laptop/` does not exist as far as
evaluation is concerned — and the error says the *path is missing*, not that it
is untracked. This costs people an hour every time. Stage first, then debug.

One `flake.lock` for the whole repository is a feature: every machine gets the
same nixpkgs on the same day, which is what makes "it works on my desktop" mean
anything about the laptop.

## Sharing without coupling

The failure to design against is **a change for one laptop landing on the
server**. Three places to put a thing, in order of how much they couple:

| put it in | who gets it |
|---|---|
| `hosts/<name>/configuration.nix` | that machine only |
| a module under `modules/` (or `common/`), imported by the hosts that want it | the hosts that opt in |
| the shared module list in `flake.nix`, applied to every host | everyone, always |

The middle row is the one to reach for, and it is ordinary NixOS — a file that is
a module, and an `imports` line in each host that wants it:

```nix
# modules/desktop.nix — no magic, just a module
{ pkgs, ... }:
{
  services.printing.enable = true;
  environment.systemPackages = with pkgs; [ firefox ];
}
```

```nix
# hosts/laptop/configuration.nix
{ ... }:
{
  imports = [ ../../modules/desktop.nix ];
  time.timeZone = "Europe/London";
}
```

Two rules that keep this from rotting:

- **Put a setting in the shared module only when every host that imports it
  genuinely wants that value.** "It is probably fine on the server too" is how a
  fleet acquires a printer daemon on a rack machine.
- **Use `lib.mkDefault` in shared modules for anything a host might reasonably
  override**, so the host file wins without `mkForce`. On lists and attribute
  sets use plain assignment instead — `mkDefault` on a merging type silently
  drops the whole contribution the moment a host adds one element.

Per-machine by nature, and never to be shared: `hardware-configuration.nix`,
`nixarchy-hardware.nix`, the disk layout, the hostname.

### `nixarchy-hardware.nix` — per machine, and copying it is the one thing not to do

The installer writes it from what it found: CPU vendor, GPU vendor, whether there
is a battery, whether the disk spins. Each line is a
[nixos-hardware](https://github.com/NixOS/nixos-hardware) module:

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

That is microcode, the media stack and `fstrim` — things otherwise discovered one
at a time. Everything they set is `lib.mkDefault`, so anything written elsewhere
wins, and the file is the user's to edit; nothing regenerates it behind them.

**Only the generic `common-*` modules are chosen automatically**, deliberately:
the machine-specific ones key on DMI product strings with no machine-readable
table anywhere, so matching them would be guessing, and importing
`dell-xps-13-9310` onto a 9315 is a machine that boots wrong in a way nobody
traces back to us. `nixarchy doctor` prints what the machine calls itself so the
user can search for a match and add it by hand. Plenty of machines have no module
at all.

**NVIDIA is never chosen automatically either** — open kernel modules versus the
legacy series, plus PRIME bus ids in decimal on a hybrid laptop. Get it wrong and
the machine has no screen. The doctor computes it and prints the lines; see the
`nixos-gpu` skill.

## Adding the second machine

```sh
nixarchy config repo                                      # 1. first machine into git
nixarchy-install --from github:you/config --host laptop   # 2. install the second from it
nixarchy config repo                                      # 3. on the new machine, push its hardware back
```

If `hosts/laptop/` already exists, the repository decides the disk, the username
and the rest, and only a password is asked for. If it does not, the usual
questions are asked and the machine is written into the repository beside the
others.

Step 3 is not optional bookkeeping: `hardware-configuration.nix` and
`nixarchy-hardware.nix` are generated *on* the machine, because hardware is the
one thing a repository written elsewhere cannot know.

Using somebody else's configuration is the same command with a machine name it
has never heard of — there is no template mechanism and there does not need to
be one. That is only safe to offer because the login hash is **not** in the
repository: it lives at `/var/lib/nixarchy/password.hash`, outside git, so a
configuration is safe to push and safe to hand to somebody.

> **`--from` runs their Nix as root.** Their `disk-config.nix` formats the disk.
> Same trust as `nix run github:...`, and worth saying out loud.

## `nixarchy-apply` on a fleet — know this before touching anything

`nixarchy-apply` copies `~/.config/nixarchy/apps.nix` into the flake and rebuilds.
**Where it copies to depends on the hostname:**

```sh
base="$flake"
[ -d "$flake/hosts/$(uname -n)" ] && base="$flake/hosts/$(uname -n)"
# → $base/nixarchy-apps.nix
```

So on a multi-host repository each machine's app selection lands in its own
`hosts/<name>/nixarchy-apps.nix` and affects nobody else — which is right, and
which also means:

- **The match is on `uname -n`.** A machine whose hostname does not equal its
  host directory name writes to the repository *root* instead, where the shared
  configuration is, and its app selection leaks to every host. Check
  `uname -n` against `ls hosts/` before debugging anything stranger.
- The Install menu's "enabled" versus "queued" status comes from that same copy,
  so a selection that has not been applied reads as queued on that machine only.
- Do not hand-edit another machine's `nixarchy-apps.nix` expecting that machine's
  menu to agree; it reads its own file.

## Pulling on a timer

```nix
programs.nixarchy.fleet = {
  enable = true;
  url = "github:you/config";
  dates = "daily";            # a systemd calendar expression
};
```

`nixos-rebuild` resolves the attribute from the hostname, so **one value serves
every machine** — no machine list anywhere. Underneath it is
`system.autoUpgrade` with `--refresh` (without it a flakeref naming a branch is
resolved from the evaluation cache and the machine "upgrades" to what it already
has, indefinitely) and a 45-minute randomised delay so fifty machines do not wake
at 03:00 to hammer the same remote.

> **The running system comes from the remote flake.** Local edits under
> `/etc/nixos` that were never pushed are reverted at the next pull, silently.
> That is the point of a fleet and it is also the way to lose an afternoon.
> Say this before enabling it for somebody.

Two consequences to state up front:

- **Secrets.** The machine pulls a public-ish repository and rebuilds as root, so
  nothing decryptable may be in it. agenix or sops-nix, with the private key
  placed on the machine out of band — the `nixos-secrets` skill owns this.
- **A machine that is off** misses its window. `persistent` is on (nixpkgs'
  default), so it catches up at the next boot rather than waiting a day — which
  is exactly what a laptop needs.

The failure this wrapper exists for: an unattended upgrade that starts failing
stops delivering configuration and **nothing says so** — a fleet that has quietly
stopped converging looks exactly like one that is up to date. So a failure
appends a timestamped line to a file that survives journal rotation:

```sh
cat /var/lib/nixarchy/upgrade-failed
systemctl status nixos-upgrade.service
journalctl -u nixos-upgrade.service -b
```

**Check that file first** when a machine is "not picking up" configuration. The
usual answers are: it was never pushed, the hostname does not match any host
directory, the file was never `git add`ed, or the upgrade has been failing for a
week.

## Pushing instead of pulling

Nothing in nixarchy is involved, and nothing needs to be:

```sh
nixos-rebuild switch --flake github:you/config#laptop --target-host root@laptop
nixos-rebuild switch --flake .#laptop --target-host root@laptop --build-host localhost
```

Where it stops, so nobody discovers it mid-deploy:

- **It needs root over SSH** on the target — a key for `root@`, or
  `--use-remote-sudo` with a user that has passwordless sudo.
- **It is one machine per invocation.** No roles, no tags, no parallelism, no
  ordering, no health check, no rollback on failure. A shell loop over hostnames
  is the honest version of "deploy the fleet" here.
- **A closure for a different architecture needs a builder for it.** Deploying to
  an aarch64 machine from x86_64 means `--build-host` on the target itself, or a
  configured remote builder, or binfmt emulation.
- The target must be reachable *and* have the disk space; a failed copy leaves
  the running system untouched, which is the good news.

For more than a handful of machines, or anything with roles and tags, point at a
tool built for it: [colmena](https://github.com/zhaofengli/colmena),
[deploy-rs](https://github.com/serokell/deploy-rs) or
[clan](https://clan.lol/). **nixarchy does not reimplement them and will not.**
The repository is an ordinary NixOS flake and all three take one, so adopting one
is additive and costs nothing here.

That is a settled decision, not an open question: `modules/fleet.nix` says so in
its header — `system.autoUpgrade` with a flake URL already *is* pull-based GitOps,
so the module is an opt-in wrapper that fixes the two things it gets wrong when
nobody is watching, and otherwise gets out of the way. No comin, no colmena, no
clan built in. **Do not propose adding one to nixarchy**; propose using one
alongside, if the user's fleet has outgrown a loop.

## Diagnosing

```sh
uname -n && ls /etc/nixos/hosts          # does this machine have a directory?
nix flake show /etc/nixos                # which nixosConfigurations actually exist
cd /etc/nixos && git status --short      # untracked = invisible to evaluation
nixos-rebuild build --flake /etc/nixos#laptop   # evaluate another host from here
nix eval /etc/nixos#nixosConfigurations.laptop.config.system.build.toplevel.drvPath
```

| Symptom | Cause |
|---|---|
| `path '…/hosts/laptop' does not exist`, but it is right there | Not `git add`ed. The flake sees tracked files only |
| `attribute 'laptop' missing` | No `hosts/laptop/` directory, or it is a file rather than a directory |
| A machine rebuilds to the wrong configuration | `uname -n` does not match its host directory name |
| An app selection appears on every machine | Same cause: `nixarchy-apply` fell back to the repository root |
| A pushed change never arrives | Timer never ran, or has been failing — `/var/lib/nixarchy/upgrade-failed` |
| Local edits keep disappearing | `fleet.enable` is on; the remote flake is the system of record |
| One machine gets a different nixpkgs | Its own `flake.lock`, i.e. it is not really in the same repository |
| `--target-host` fails on permissions | No root over SSH; `--use-remote-sudo` |

## Rules

- **Never restructure a single-host flake into `hosts/` uninvited.** It is a
  large diff in the one file a user cannot afford to have broken.
- **`git add` before evaluating, every time.** More fleet debugging time goes here
  than anywhere else.
- **Check `uname -n` against `ls hosts/` early.** It explains a whole class of
  "the wrong machine changed".
- **Never copy `hardware-configuration.nix` or `nixarchy-hardware.nix` between
  machines.** They describe the machine they were generated on.
- **Say what `fleet.enable` costs** — unpushed local edits are reverted silently —
  before turning it on for somebody.
- **No plaintext secrets in a repository a fleet pulls.** Send it to
  `nixos-secrets`.
- **Do not propose a deploy tool as a nixarchy feature.** Suggest running one
  alongside; the flake is an ordinary one.
- **Git questions go to `nixos-config-repo`.**
