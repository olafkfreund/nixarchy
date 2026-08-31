---
name: nixos-security
description: >
  REQUIRED for securing and hardening this NixOS machine — firewall rules,
  nftables, SSH access, sudo, user privileges, systemd service sandboxing, kernel
  hardening, VPN and remote access, and reviewing a configuration for weaknesses.
  Use when asked to open or close a port, lock down SSH, harden a service or the
  kernel, set up a firewall, audit the machine's exposure, restrict a user, or
  check what is listening on the network. Triggers: firewall, nftables, iptables,
  allowedTCPPorts, open port, close port, harden, hardening, sudo, wheel, sshd,
  PermitRootLogin, PasswordAuthentication, fail2ban, VPN, wireguard, tailscale,
  apparmor, audit, CVE, "is this secure", "what's exposed".
  For storing keys and passwords use `nixos-secrets`.
---

# NixOS Security Skill

NixOS starts in a good place: **the firewall is on by default, nothing listens
externally unless a module opens it, and the whole configuration is one readable
file tree.** Most hardening here is about not undoing that, plus a short list of
things worth adding.

Two habits that matter more than any individual option:

1. **Look at what is actually exposed before changing anything.** The config says
   what was intended; `ss` says what is true.
2. **Change one thing and keep the machine reachable.** A firewall or SSH change
   that locks you out of a remote box is the classic self-inflicted outage —
   `nixos-rebuild test` and a second open session are the seatbelt.

## Step 1: What Is Exposed Right Now

```bash
ss -tlnp                          # TCP listeners, and which process
ss -ulnp                          # UDP
sudo nft list ruleset             # the firewall as the kernel sees it
systemctl list-units --type=service --state=running
```

Read the **address** column, not just the port. `127.0.0.1:8080` is a local
service and not an exposure; `0.0.0.0:8080` or `*:8080` is reachable from the
network. Half of "should I firewall this?" questions dissolve at that line.

```bash
# Who can become root
getent group wheel
# Anything with a shell
getent passwd | awk -F: '$7 !~ /nologin|false/'
# Setuid binaries on the system
find /run/current-system/sw/bin -perm -4000 -type f 2>/dev/null
```

## Firewall

On by default. Enabling a service does **not** open its port — that is a feature.

```nix
networking.firewall = {
  enable = true;                          # default; never set this false as a "fix"
  allowedTCPPorts = [ 22 80 443 ];
  allowedUDPPorts = [ 51820 ];            # WireGuard
  allowedTCPPortRanges = [ { from = 8000; to = 8010; } ];
  trustedInterfaces = [ "tailscale0" ];   # skip filtering on a trusted overlay
  logRefusedConnections = false;          # default true; very noisy on a public host
  allowPing = true;
};
```

Prefer the module's own option when it has one — it tracks the port setting, so
changing the port does not silently leave a stale hole:

```nix
services.foo.openFirewall = true;
```

Per-interface rules, for a machine on more than one network:

```nix
networking.firewall.interfaces."enp1s0".allowedTCPPorts = [ 445 ];
```

**`networking.firewall.enable = false` is almost never the answer.** When a
service is unreachable, the sequence is: is it running, is it bound to the right
address, is the port open. Turning the firewall off to "test" it and then
forgetting is how machines end up exposed.

### nftables

The modern backend, and worth switching to on anything that needs real rules:

```nix
networking.nftables.enable = true;        # the firewall module then emits nftables
```

The standard options above keep working. For rules the module cannot express:

```nix
networking.nftables.tables."myfilter" = {
  family = "inet";
  content = ''
    chain input {
      type filter hook input priority 0; policy drop;
      ct state established,related accept
      iif lo accept
      ip saddr 192.168.1.0/24 tcp dport 5432 accept
    }
  '';
};
```

Use `networking.nftables.tables` rather than `ruleset` where you can — a table is
cleaned up automatically on reload, while a raw `ruleset` needs `flushRuleset` or
`extraDeletions` and leaves stale rules behind otherwise.

`networking.nftables.checkRuleset` is on by default and validates at build time.
Do not disable it to make a rebuild pass.

## SSH

```nix
services.openssh = {
  enable = true;
  ports = [ 22 ];
  openFirewall = true;
  settings = {
    PermitRootLogin = "no";
    PasswordAuthentication = false;
    KbdInteractiveAuthentication = false;
    X11Forwarding = false;
  };
};

users.users.alice.openssh.authorizedKeys.keys = [
  "ssh-ed25519 AAAAC3Nza... alice@laptop"
];
```

**Add the key before disabling password auth, and verify it works in a second
session before closing the first.** Doing it in one rebuild on a remote machine
is how people lock themselves out of a server they cannot physically reach.

`nixos-rebuild test` (not `switch`) for a remote SSH change: if it locks you out,
a power cycle brings back the previous configuration.

Brute-force protection, if the port is public at all:

```nix
services.fail2ban = {
  enable = true;
  maxretry = 5;
  ignoreIP = [ "192.168.1.0/24" ];
};
```

Better still, **do not expose SSH to the internet.** Tailscale or WireGuard gives
you remote access with nothing listening publicly:

```nix
services.tailscale.enable = true;
networking.firewall.trustedInterfaces = [ "tailscale0" ];
# then bind sshd to the tailnet only, or drop 22 from allowedTCPPorts entirely
```

## Users and sudo

```nix
users.mutableUsers = false;                  # accounts come only from the config
users.users.alice = {
  isNormalUser = true;
  extraGroups = [ "wheel" ];
  hashedPasswordFile = "/run/secrets/alice";  # never `password` or `hashedPassword`
  openssh.authorizedKeys.keys = [ "ssh-ed25519 ..." ];
};

security.sudo.wheelNeedsPassword = true;      # keep this true
```

Groups that are effectively root — say so plainly when adding a user to one:

| Group | Why it is root-equivalent |
|---|---|
| `wheel` | sudo |
| `docker` | can mount the host filesystem into a container as root |
| `libvirtd` | similar, via VM disk access |
| `disk` | raw block device access |

`users.mutableUsers = false` means `passwd` no longer works — the password *must*
come from `hashedPasswordFile`. Setting it without providing one locks everyone
out at the next boot. Check before enabling it.

## Hardening a service

Modules for well-maintained services are usually sandboxed already. Check before
adding anything:

```bash
systemctl cat foo | grep -E 'Protect|Private|Restrict|NoNewPriv|Capability'
systemd-analyze security foo.service       # scored report, worst settings first
```

`systemd-analyze security` is the fastest honest answer to "is this service
locked down", and it names the exact options to add. For a unit you wrote:

```nix
systemd.services.my-thing.serviceConfig = {
  DynamicUser = true;
  ProtectSystem = "strict";
  ProtectHome = true;
  PrivateTmp = true;
  PrivateDevices = true;
  NoNewPrivileges = true;
  RestrictAddressFamilies = [ "AF_INET" "AF_INET6" ];
  RestrictNamespaces = true;
  LockPersonality = true;
  MemoryDenyWriteExecute = true;
  SystemCallFilter = [ "@system-service" ];
  SystemCallArchitectures = "native";
  CapabilityBoundingSet = [ "" ];
  StateDirectory = "my-thing";
};
```

Add these **incrementally and test after each**. `ProtectSystem = "strict"` and
`MemoryDenyWriteExecute` break real programs (anything JIT-compiling — Java,
JavaScript, some Python) and the failure is often an obscure crash rather than a
clear permission error.

## Kernel and system hardening

```nix
boot.kernel.sysctl = {
  "kernel.dmesg_restrict" = 1;              # non-root cannot read the kernel log
  "kernel.kptr_restrict" = 2;
  "kernel.yama.ptrace_scope" = 1;           # a process cannot trace another user's
  "net.ipv4.conf.all.rp_filter" = 1;
  "net.ipv4.conf.all.accept_redirects" = 0;
  "net.ipv6.conf.all.accept_redirects" = 0;
  "net.ipv4.conf.all.log_martians" = 1;
};

security.protectKernelImage = true;
security.lockKernelModules = true;          # no module loading after boot
security.forcePageTableIsolation = true;
security.apparmor.enable = true;
```

`security.lockKernelModules = true` breaks anything that loads a module on demand
— VirtualBox, some VPNs, USB devices whose driver was not loaded at boot. If a
device stops working after enabling it, that is why.

There is a `<nixpkgs/nixos/modules/profiles/hardened.nix>` profile. **Do not
import it on a desktop.** It picks the hardened kernel, disables user namespaces
(breaking Flatpak, Chrome's sandbox, and rootless containers), and costs
noticeable performance. It is built for servers with a narrow, known workload.

## Auditing a configuration

```bash
# Ports opened anywhere in the config
grep -rn "allowedTCPPorts\|allowedUDPPorts\|openFirewall" --include='*.nix' .

# The three most common own-goals
grep -rn "firewall.enable *= *false" --include='*.nix' .
grep -rn "PermitRootLogin\|PasswordAuthentication" --include='*.nix' .
grep -rnE '(password|token|secret|key)\s*=\s*"' --include='*.nix' .

# What the running system exposes, from outside
nix shell nixpkgs#nmap -c nmap -sT -p- <host>
```

Only scan machines you own. Say that, and mean it.

Keeping up with fixes matters more than any single hardening option:

```nix
system.autoUpgrade = {
  enable = true;
  flake = "/etc/nixos";
  dates = "weekly";
  allowReboot = false;         # true only where an unattended reboot is acceptable
};
```

## Rules

- **Look at `ss -tlnp` and `nft list ruleset` before theorising about exposure.**
- **Never disable the firewall to debug connectivity.** Check bind address first.
- **Never lock down SSH in one step on a remote machine.** Key first, verify in a
  second session, then disable passwords — and use `test`, not `switch`.
- **Name the risk when adding someone to `docker`, `libvirtd` or `disk`.** Those
  are root, in a costume.
- **Do not import the hardened profile onto a desktop** without saying what it
  breaks.
- **Add sandboxing options one at a time.** `systemd-analyze security` tells you
  which are missing and is a better guide than a copied block.
- Secrets are their own problem — never inline one to make a security change
  work. See the `nixos-secrets` skill.
- If a change could lock the user out, say so *before* running it, not after.
