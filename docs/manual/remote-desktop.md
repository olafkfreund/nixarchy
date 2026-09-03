---
title: Remote desktop
---

# Remote desktop

nixarchy can serve the Hyprland session you are already logged into over RDP,
so a Windows laptop's built-in `mstsc`, or any other RDP client, opens your
actual desktop. It is off, and enabling it is four decisions rather than one
switch. This page is those decisions.

## What it is not

**It is not remote login.** [hypr-rdp](https://github.com/MuNeNiCK/hypr-rdp)
is a client of a compositor that is already running. If nobody is logged in at
that machine, there is no session and nothing to connect to — the daemon is
not even started, because its unit is part of `graphical-session.target` and
conditioned on `WAYLAND_DISPLAY`. Reboot the machine remotely and you have
locked yourself out until someone logs in.

**It is not the way to administer a machine.** For that the answer here is the
same as it has always been: Tailscale and SSH, both of which nixarchy already
carries, neither of which needs a desktop to be running. RDP earns its place
only when you want *the desktop itself* — a browser session, a GUI tool, a
screen someone else is looking at.

**It is not a privacy boundary.** Left alone, hypr-rdp creates a headless
output that resizes to your client, so the physical monitors keep showing what
they showed. That is a convenience, not isolation: it is one session, and
whoever is sitting at that machine is in it with you.

## What enabling it opens

Nothing beyond the machine itself, until you change `bind`.

| | |
|---|---|
| Port | 3389/tcp, the RDP default |
| Interface | `127.0.0.1` — this machine only |
| Firewall | unchanged; `openFirewall` is a separate option and defaults to `false` |
| Authentication | a username and password checked by hypr-rdp, over TLS. hypr-rdp offers NLA when credentials are set, and this module never starts it without them |
| Runs as | your user, inside your graphical session, and dies with it |

The username defaults to `nixarchy` and is deliberately not your login name —
a name the client already knows is half of a guess. It is checked by hypr-rdp
against the password below and has nothing to do with your Linux account.

## The password, and why the rebuild fails without one

Enabling this from the menu and rebuilding **fails**, on purpose, with an
assertion naming the steps below. That is not a missing feature.

hypr-rdp fails open. Given no password it logs a warning and then serves your
session with no authentication at all — verified in v0.1.5, `src/config.rs`,
where the credentials are resolved with `unwrap_or_default()` and nothing
returns. So this module is the only thing between an unset secret and an open
desktop, and it refuses twice: an assertion at evaluation when no secret is
named, and an `ExecStartPre` at runtime that reads the rendered config back
and exits non-zero unless both the username and the password are non-empty. A
secret that exists but renders empty gets past the first and not the second.

It also cannot take the password from your configuration, because hypr-rdp
reads it from exactly two places: an inline string in its TOML config, or
`-p` on the command line. `/proc/*/cmdline` is world-readable, so the flag is
out; the Nix store is world-readable, so committing the string is out. What
happens instead is that [sops-nix](https://github.com/Mic92/sops-nix) renders
the config file at activation from an encrypted secret, mode 0400, owned by
you, under `/run` — never in the store and never in git.

### Getting the password there

You need `services.openssh.enable = true` first, and one rebuild after it. The
secret is encrypted to the machine's own SSH host key, and that key is
generated on first boot — so on a machine installed from the ISO this is
always the second rebuild, not the first. Without sshd there is no key at all
and sops-nix says so rather than guessing.

**1. Read this host's public key as an age recipient.**

```sh
nix-shell -p ssh-to-age --run 'ssh-keyscan localhost 2>/dev/null | ssh-to-age'
```

**2. Name it in `.sops.yaml` at the root of your flake repository.** Create the
file if it is not there:

```yaml
keys:
  - &desk age1qz...           # the key from step 1
creation_rules:
  - path_regex: hosts/desk/secrets\.yaml$
    key_groups:
      - age:
          - *desk
```

Add your own age key as a second recipient here if you have one. Encrypted to
the host alone, the file can only ever be decrypted on that host, as root —
which is fine until you want to change the password from your laptop.

**3. Write the password in.**

```sh
nix-shell -p sops --run 'sops edit hosts/desk/secrets.yaml'
```

The file's content is plain YAML before sops encrypts it, and the key is the
name you are about to declare:

```yaml
hypr-rdp-password: something-long
```

Avoid a double quote, a backslash or a newline in it. The value is written
into a TOML string, and one that breaks the quoting makes hypr-rdp fail to
parse its config — a safe failure, since it exits rather than starting, but a
confusing way to find out.

**4. Declare the secret and point the service at it,** in
`hosts/desk/configuration.nix`:

```nix
sops.secrets.hypr-rdp-password.sopsFile = ./secrets.yaml;

programs.nixarchy.services.hypr-rdp = {
  enable = true;
  passwordSecret = "hypr-rdp-password";
};
```

`passwordSecret` is the attribute name under `sops.secrets` — not the password
and not a path to it.

Put this in `configuration.nix` rather than in `~/.config/nixarchy/services.nix`.
The menu's file is copied into `hosts/<host>/nixarchy/` by `nixarchy-apply`, so
a relative `./secrets.yaml` written there would resolve one directory too deep.
Enabling from the menu is fine; the secret's two lines belong beside the file
they name.

**5. `git add` the encrypted file, then rebuild.** A flake in a git worktree
sees only tracked files, so an unstaged `secrets.yaml` does not exist as far as
evaluation is concerned, and the error says the path is missing rather than
that it is untracked.

Changing the password later means editing the encrypted file, rebuilding, and
then `systemctl --user restart hypr-rdp`. sops-nix restarts system units and
this is a user unit, so nothing restarts it for you.

## Reaching it: three shapes

### Localhost, over an SSH tunnel

Nothing to configure. Leave `bind` alone and forward the port from the client:

```sh
ssh -L 3389:localhost:3389 you@desk
```

then point the RDP client at `localhost:3389`. Zero exposure, one already-open
port, and the authentication that matters is your SSH key. If you only ever
connect from machines you can SSH to, stop here.

### Over your tailnet — the one to want

```nix
programs.nixarchy.services.tailscale.enable = true;
programs.nixarchy.services.hypr-rdp.bind = "0.0.0.0:3389";
```

The daemon listens on every interface, the firewall still refuses everything
arriving on the LAN, and `trustInterface` — on by default with Tailscale here
— trusts `tailscale0`. So your own machines reach it and the coffee shop does
not, with no port opened anywhere. Connect to the machine's tailnet address on
3389.

The cost is stated rather than hidden: a trusted interface bypasses the
firewall for *everything* arriving on it. On a tailnet of machines you own,
that is the point. On one you share with other people, they can reach 3389 too
— use Tailscale ACLs, or keep to the SSH tunnel.

### On the LAN

```nix
programs.nixarchy.services.hypr-rdp.openFirewall = true;
```

This opens 3389 in `networking.firewall.allowedTCPPorts` — to every device on
every network this machine joins, which is the part worth pausing on.

3389 is among the most scanned ports that exist. hypr-rdp has no rate limiting
and no lockout, so a guess costs an attacker nothing and a successful one is
your whole desktop: your browser sessions, your SSH agent, your sudo prompt.
There is no `fail2ban` wiring here either — hypr-rdp's logs are not stable
enough at v0.1.x to write a filter against.

If you do it anyway, scope it to the interface rather than opening it
everywhere. Leave `openFirewall` off and write the rule yourself:

```nix
networking.firewall.interfaces.enp3s0.allowedTCPPorts = [ 3389 ];
```

A laptop that joins other networks should not use either.

## The certificate warning

The first connection shows a certificate warning in every client, and it is
not a bug. hypr-rdp generates a self-signed pair into `~/.config/hypr-rdp/` on
first start and reuses it afterwards. Clients trust nothing about it; what they
can do is remember it, which is why the pair is generated once and left alone —
regenerating it on every rebuild would change the fingerprint your client
pinned, and ask you the same question forever.

So: accept it once, on a connection you have reason to trust, and be suspicious
if it changes. That is pinning, and it is the honest strength of the guarantee
— it detects a swapped machine on later connections, not a wrong one on the
first.

nixarchy does not automate trust here, because automating it without a real CA
is theatre. If you have a certificate, bring it:

```nix
programs.nixarchy.services.hypr-rdp = {
  certFile = "/var/lib/certs/desk.pem";
  keyFile = "/var/lib/certs/desk.key";
};
```

Both or neither — hypr-rdp bails on one without the other rather than falling
back, so the module refuses that pair at evaluation instead of letting the unit
fail at every start.

## Mirroring a real monitor

The default headless output is usually what you want: it resizes to the
client's window and does not disappear when a monitor is switched off. To mirror
a screen someone may be sitting in front of instead:

```nix
programs.nixarchy.services.hypr-rdp.output = "DP-1";
```

## What this does not protect against

- **The software itself.** hypr-rdp is a pre-1.0 Rust daemon parsing RDP off
  the wire, roughly one primary author, unaudited, not in nixpkgs. That is not
  a slight — it is the only thing that serves this compositor family at all,
  and it is why the integration is opt-in and tailnet-first rather than on. A
  listening socket you did not need is the one to be stingy with.
- **A guessed or reused password.** There is no lockout. On the promoted paths
  nothing can guess at it; on the LAN, everything can.
- **Anyone already in your session.** A connected client is you: same
  clipboard, same keyboard, same browser logins, same sudo.
- **Someone at the physical machine.** Headless is a second output, not a
  private one.
- **A rebooted machine.** No session, no daemon, no way back in without
  something else — SSH, and a person, or wake-on-LAN and a display manager
  that autologs in, which is its own trade.

See also: [Security](security) for the firewall and SSH generally, and
[Many machines, one repo](many-machines) for where `hosts/<name>/` comes from.
