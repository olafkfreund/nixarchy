---
name: nixos-services
description: >
  REQUIRED for configuring, debugging and troubleshooting services and daemons on
  this NixOS machine — systemd units, databases, web servers, containers, secrets,
  firewall, storage and users. Use when a service will not start, a unit is
  failing or crash-looping, a port is unreachable, a permission is denied, a
  container will not run, a rebuild fails to evaluate, or you need to find what a
  NixOS option is actually called. Triggers: systemctl, journalctl, unit failed,
  service won't start, permission denied, firewall, port, nginx, postgresql,
  docker, podman, oci-containers, secrets, agenix, sops, mount, disk full, user,
  group, StateDirectory, systemd.services, "worked before the rebuild".
  For installing a package, use `nixos`; for GPU or AI services, use those skills.
---

# NixOS Services Skill

Two things that are ordinary elsewhere and are the whole job here:

1. **Prefer the module over the package.** A package puts a binary on `PATH`. The
   NixOS module also creates the systemd unit, the user, the state directory with
   the right ownership, the firewall hole and sane defaults. `services.foo.enable`
   is one line and does all of it correctly.
2. **You cannot edit a unit file.** Everything under `/etc/systemd/system` is a
   read-only store symlink. Changing service behaviour means changing the Nix that
   generates the unit, then rebuilding. `systemctl edit` will not stick.

Everything below is route 2 in the `nixos` skill: edit the flake, then rebuild.

## Find the Option Before Writing It

Guessing an option name costs a full rebuild to find out. Three ways, cheapest
first:

```bash
nixarchy-search postgres        # fzf over this system's packages AND options
man configuration.nix           # offline, complete, searchable with /
nixos-option services.nginx     # what is set right now, and where it came from
```

**The authoritative source is the module on this disk**, which matches the
nixpkgs this machine actually builds against — unlike search.nixos.org, which
tracks a channel that may be ahead or behind, and unlike a model's memory, which
is frequently a year stale. Options get renamed and removed often:

```bash
# every option a module defines, with defaults
nix eval --json /etc/nixos#nixosConfigurations.$(hostname).options.services.ollama \
  --apply 'builtins.attrNames' 2>/dev/null

# or read the module directly
find /nix/store/*-source/nixos/modules -name 'ollama.nix' 2>/dev/null | head -1
```

A module's `imports` list usually starts with `mkRenamedOptionModule` and
`mkRemovedOptionModule` entries — that block is a changelog of exactly the
mistakes an out-of-date example will make, and reading it takes five seconds.

## Enabling a Service

```nix
services.nginx = {
  enable = true;
  recommendedProxySettings = true;
  virtualHosts."example.com" = {
    enableACME = true;
    forceSSL = true;
    locations."/".proxyPass = "http://127.0.0.1:3000";
  };
};

services.postgresql = {
  enable = true;
  ensureDatabases = [ "myapp" ];
  ensureUsers = [{
    name = "myapp";
    ensureDBOwnership = true;
  }];
};
```

`ensureDatabases`/`ensureUsers` run on every activation and are idempotent, but
they only *create* — they never alter an existing database or drop anything.

### The firewall is on by default

Enabling a service does not open its port. Most modules offer `openFirewall`;
prefer it over a hand-written rule, because it tracks the port option:

```nix
services.foo.openFirewall = true;
# or, when the module has no such option:
networking.firewall.allowedTCPPorts = [ 8080 ];
```

If a service is running and `curl localhost:PORT` works but another machine gets
a timeout, this is why — every time. For real rule sets, nftables and exposure
review, use the `nixos-security` skill.

## Writing Your Own Unit

When no module exists:

```nix
systemd.services.my-thing = {
  description = "My thing";
  wantedBy = [ "multi-user.target" ];
  after = [ "network-online.target" ];
  wants = [ "network-online.target" ];   # `after` alone does not pull it in

  serviceConfig = {
    ExecStart = "${pkgs.my-thing}/bin/my-thing --port 8080";
    Restart = "on-failure";
    RestartSec = 5;

    # DynamicUser gives you a per-service user for free, plus these paths
    DynamicUser = true;
    StateDirectory = "my-thing";         # /var/lib/my-thing, correctly owned
    RuntimeDirectory = "my-thing";       # /run/my-thing
  };
};
```

Points that bite:

- **`ExecStart` must be an absolute store path.** A bare `my-thing` is not on the
  unit's `PATH`. Use `${pkgs.my-thing}/bin/my-thing`, or set `path = [ pkgs.foo ];`
  on the service for anything the script shells out to.
- **`wantedBy` is what makes it start.** Without it the unit exists and nothing
  ever pulls it in.
- **Let systemd create state directories.** `StateDirectory` beats a `preStart`
  `mkdir`, and it gets the ownership right under `DynamicUser`.
- **`network-online.target` needs `wants` as well as `after`**, and requires
  `systemd.network`/NetworkManager's wait-online to be enabled to mean anything.

To adjust a unit a module already generates, extend rather than replace:

```nix
systemd.services.nginx.serviceConfig.MemoryMax = "2G";
```

### Timers instead of cron

```nix
systemd.timers.my-backup = {
  wantedBy = [ "timers.target" ];
  timerConfig = {
    OnCalendar = "daily";
    Persistent = true;      # run on boot if the machine was off at the time
  };
};
systemd.services.my-backup.serviceConfig = {
  Type = "oneshot";
  ExecStart = "${pkgs.my-backup}/bin/backup";
};
```

## Secrets

**Never put a secret in a `.nix` file** — the store is world-readable and every
build input ends up in it. Look for the module's `*File` variant:

```nix
services.foo.environmentFile = "/run/secrets/foo.env";
```

For anything beyond a single hand-placed file — encrypted-in-the-repo secrets,
agenix, sops-nix, rotation, leak handling — use the **`nixos-secrets` skill**.

## Containers

```nix
virtualisation.docker.enable = true;          # or virtualisation.podman
users.users.<name>.extraGroups = [ "docker" ];  # docker group == root. Say so.

virtualisation.oci-containers.containers.myapp = {
  image = "myapp:1.2.3";                      # pin a tag; :latest is not reproducible
  ports = [ "127.0.0.1:8080:8080" ];          # bind to localhost unless LAN is intended
  volumes = [ "/var/lib/myapp:/data" ];
  environmentFiles = [ "/run/secrets/myapp.env" ];
};
```

`oci-containers` generates a systemd unit per container, so `systemctl status
docker-myapp` and `journalctl -u docker-myapp` work the usual way. Podman is the
better default when nothing needs the Docker socket — rootless, and no
root-equivalent group.

## Troubleshooting

If you do not yet know *which* service is at fault, run the sweep in the
`nixos-doctor` skill first. Once you have a unit name, start here:

```bash
systemctl status foo.service                 # state, PID, last lines, exit code
journalctl -u foo -b --no-pager | tail -50   # this boot's logs for the unit
journalctl -u foo -f                         # follow while you reproduce
systemctl cat foo                            # the ACTUAL generated unit — read this
systemd-analyze verify foo.service           # syntax and dependency problems
```

`systemctl cat` is the one people skip and the one that answers most questions:
it shows the unit Nix actually produced, which is frequently not the unit you
thought your options produced.

```bash
systemctl list-units --failed        # everything broken right now
systemd-analyze blame                # what made the boot slow
ss -tlnp | grep 8080                 # is anything listening, and as whom
sudo nft list ruleset | grep 8080    # did the firewall actually open it
```

### Reading the failure

| Symptom | Cause |
|---|---|
| `status=203/EXEC` | `ExecStart` path wrong or not executable. Use the full store path |
| `status=200/CHDIR`, `217/USER` | `WorkingDirectory` or `User` does not exist |
| Permission denied on a data dir | Wrong owner. Use `StateDirectory` rather than creating it yourself |
| Unit is `inactive (dead)`, no logs | `wantedBy` missing — nothing ever started it |
| Crash-loop, then `start request repeated too quickly` | Real error is in the *first* failure. Scroll up in the journal |
| Runs, unreachable from another machine | Firewall, or it is bound to `127.0.0.1` |
| Config change had no effect | Not rebuilt, or the module ignores it. Check `systemctl cat` |
| Worked before the rebuild | `nix profile diff-closures --profile /nix/var/nix/profiles/system` |
| `Read-only file system` writing to `/etc` or `/nix` | Correct and by design. Declare the file in Nix |

### Rebuild failures

| Message | Meaning |
|---|---|
| `The option 'services.foo.bar' does not exist` | Renamed or removed. Read the module's `imports` block |
| `attribute 'foo' missing` | Wrong package attribute. `nixarchy-search` it |
| `infinite recursion encountered` | A `config` value used to compute something it also defines |
| `path '/nix/store/...' does not exist` for a file you just wrote | Untracked in git. `git add` it |
| `A definition for option ... is not of type ...` | Wrong shape — a string where a list or path is wanted |
| Two modules set the same option | `lib.mkForce` / `lib.mkDefault` to break the tie, deliberately |

Check an edit evaluates **without** a password prompt or an activation:

```bash
nixos-rebuild build --flake "${NIXARCHY_FLAKE:-/etc/nixos}"
```

Then `test` before `switch` for anything risky — `test` does not touch the boot
menu, so a reboot returns to the last known-good system.

## Disk, Mounts and Users

```nix
fileSystems."/data" = {
  device = "/dev/disk/by-uuid/xxxx";     # by-uuid, never /dev/sdb1 — it moves
  fsType = "ext4";
  options = [ "nofail" ];                # so a missing disk does not block boot
};

users.users.alice = {
  isNormalUser = true;
  extraGroups = [ "wheel" "networkmanager" ];
  # hashedPasswordFile, not password or hashedPassword — the store is public
};
```

**`nofail` on any non-essential mount.** Without it a disk that is absent or slow
drops the boot into emergency mode, which on a headless machine means it is gone.

Disk full is usually the Nix store:

```bash
df -h /nix
sudo nix-collect-garbage -d          # deletes EVERY old generation — ask first
sudo nix-collect-garbage --delete-older-than 30d    # keeps a rollback window
```

The first form destroys the rollback safety net. Prefer the second, and never run
either as a reflex.

## Rules

- **Read `systemctl cat` and the journal before theorising.** The generated unit
  and the actual error beat any guess about what the module does.
- **Verify the option name against the module on this disk** before writing it.
  Renames and removals are the most common cause of a failed eval.
- **Prefer the module to a hand-written unit**, and extend a generated unit rather
  than replacing it.
- **Never write a secret into a `.nix` file.** Use a `*File` option; see the
  `nixos-secrets` skill.
- **`build` and `test` before `switch`** for anything that could break boot,
  networking or the display.
- **Never garbage-collect to free space without asking** — it deletes the
  generations that make rollback possible.
- When a service is broken after a rebuild, the fastest fix is
  `sudo nixos-rebuild --rollback switch`, then diff the closures to find out why.
