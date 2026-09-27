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

### From the menu, if you would rather not read the rest

**Setup → Remote desktop → Allow connections** opens a terminal that reports
the four things this needs — an SSH host key, a rule in `.sops.yaml`, the
encrypted password, the service itself — and offers the next one you are
missing. It does the mechanical steps and stops at the one edit it will not
make for you, which is the two lines below.

`nixarchy remote --status` is the same report with nothing offered.

The rest of this section is what that command is doing, and it is worth
reading once.

### Getting the password there

One command does all of it:

```sh
nixarchy secret new hypr-rdp-password
```

That derives this host's age recipient, writes `.sops.yaml` at the root of your
flake if there is not one, and opens `hosts/<host>/secrets.yaml` in your
editor. The file is plain YAML while you edit it and encrypted when you save:

```yaml
hypr-rdp-password: something-long
```

Avoid a double quote, a backslash or a newline in the value. It is written into
a TOML string, and one that breaks the quoting makes hypr-rdp fail to parse its
config -- a safe failure, since it exits rather than starting, but a confusing
way to find out.

You need sshd enabled first, and one rebuild after it. The secret is encrypted
to the machine's own SSH host key, and that key is generated on first boot --
so on a machine installed from the ISO this is always the second rebuild, not
the first. Without sshd there is no key at all, and `nixarchy secret` says so
rather than letting you meet it as a build error.

Then **declare the secret and point the service at it**, in
`hosts/<host>/configuration.nix`:

```nix
sops.secrets.hypr-rdp-password.sopsFile = ./secrets.yaml;

programs.nixarchy.services.hypr-rdp = {
  enable = true;
  passwordSecret = "hypr-rdp-password";
};
```

`passwordSecret` is the attribute name under `sops.secrets` -- not the password
and not a path to it.

Put this in `configuration.nix` rather than in `~/.config/nixarchy/services.nix`.
The menu's file is copied into `hosts/<host>/nixarchy/` by `nixarchy apply`, so
a relative `./secrets.yaml` written there would resolve one directory too deep.
Enabling from the menu is fine; the secret's two lines belong beside the file
they name.

Finally `git add` the encrypted file and rebuild. A flake in a git worktree
sees only tracked files, so an unstaged `secrets.yaml` does not exist as far as
evaluation is concerned, and the error says the path is missing rather than
that it is untracked.

### The second machine

`.sops.yaml` says which recipients can decrypt which file, and `nixarchy
secret new` writes it only when it is absent. On your second machine it exists
and has no rule for that host, so the command stops rather than editing it — a
creation rule spliced in by pattern-matching is one that can silently stop
matching, and you would find out when a secret refused to decrypt.

`nixarchy secret enroll` is the supported way through:

```sh
nixarchy secret enroll
```

It appends this host's rule structurally, leaves every other host's rule
alone, and rekeys nothing. That last part is the design rather than a
limitation: secrets here are **per host**, so `hosts/<host>/secrets.yaml` is
encrypted to that machine alone, and enrolling only lets this one create its
own. A machine that is compromised is then one machine's secrets rather than
every machine's.

A fleet is therefore `enroll`, `new`, the two lines, rebuild — once per
machine, with a different password on each.

If it reports that the policy already has a rule for this host with a
*different* recipient, this machine's SSH host key has changed; a reinstall
that kept the hostname does exactly that. It refuses rather than appending a
second rule, because sops takes the first one and the machine would then
encrypt to a key it cannot read back.

Changing the password later means `nixarchy secret edit`, a rebuild, and then
`systemctl --user restart hypr-rdp`. sops-nix restarts system units and this is
a user unit, so nothing restarts it for you.

[The Secrets page](secrets) covers the rest of the command -- what exists on
this machine, what reads it, and the second kind of secret, which goes to your
clipboard rather than to a service.

## Reaching it: three shapes

### From the menu, over an SSH tunnel — the one to use

Nothing to configure on the machine being connected to. On the machine you are
connecting *from*, install a client once:

```nix
programs.nixarchy.apps.freerdp.enable = true;
```

then **Setup → Remote desktop → Connect to a machine**. It lists your
`~/.ssh/config` hosts and the Linux machines on your tailnet, forwards a free
local port over SSH, and opens the desktop. Zero exposure, one already-open
port, and the authentication that matters is your SSH key. The tunnel closes
when you close the client.

The list is machines you can *SSH to* — not machines known to be serving a
desktop. hypr-rdp shares a session someone is already logged into, so a
machine with nobody at it has nothing to show.

`sdl-freerdp` is what it launches. FreeRDP ships three clients and deprecated
its Wayland one in favour of the SDL3 build, which is also the one that needs
no Xwayland. `xfreerdp` is in the same package if you prefer it, and the menu
row appears when either is installed.

By hand, if you would rather:

```sh
ssh -L 3389:localhost:3389 you@desk
sdl-freerdp /v:localhost:3389 /u:nixarchy /dynamic-resolution
```

`/dynamic-resolution` is worth the typing: the headless output resizes to your
window, so the session follows the client instead of letterboxing.

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

## Letting an agent drive another machine

Not through RDP. Accessibility does not cross it — the remote desktop arrives
as pixels, so an agent looking at an RDP window sees the client's own chrome
and nothing inside the session. It would be reduced to screenshots and
coordinates.

[ai-mirror](https://github.com/olafkfreund/ai-mirror), which nixarchy already
carries, is the surface that works. It is an MCP server spoken over stdin and
stdout, so an agent reaches a remote one by running it there:

```nix
command = "ssh";
args = [ "desk" "ai-mirror" "mcp" ];
```

That gives the agent the other machine's real accessibility tree and window
list — `a11y_find` by name, not a guess at a pixel.

### What that grants, before you paste it

**It is as strong as your SSH access to that machine, and no stronger.**

Locally, ai-mirror will not let an agent turn control on: it asks, and a
dialog on your screen is answered by whoever is at the keyboard. That gate
holds for an agent reaching ai-mirror through MCP alone. It does not hold
here. `ai-mirror control confirm` is an ordinary command, so an agent with a
shell on that account answers its own dialog — and `ssh desk ai-mirror mcp`
*is* a shell on that account.

A forced-command key in `authorized_keys` does not fix it either. It
restricts that key; it does not remove the ordinary key you already have to
that machine, which is the same key the Connect row tunnels with.

So on the far machine the dialog is a **notice, not a gate**. Read it that
way.

### What actually helps

**Do not give the agent the key.** This is the only thing that changes the
picture, and it is not a setting: a key for your fleet that is not loaded
into `ssh-agent` and not readable by the account your agent runs as. An agent
that cannot reach the machine cannot drive it, and everything above stops
mattering.

**Ask for less.** Observation — the accessibility tree, the window list, a
screenshot — needs no control grant at all. An agent that only looks is a
much smaller thing to hand over, even though nothing enforces the difference.

**Read the log.** Every request, answer and stop is a line in
`$XDG_RUNTIME_DIR/ai-mirror/audit.jsonl` on the machine that was driven. It is
the one durable artifact here, and it is on the far machine, so:

```sh
ssh desk 'cat "$XDG_RUNTIME_DIR/ai-mirror/audit.jsonl"'
```

Single-quoted on purpose: the variable has to expand on the far machine,
and `ssh desk cat "$XDG_RUNTIME_DIR/..."` would expand it here instead and
look in the wrong place.

An empty file means one of two things — nothing happened, or that machine
rebooted, since `$XDG_RUNTIME_DIR` does not survive one. Do not read empty as
all-clear.

None of this is turned on for you. `programs.nixarchy.aiMirror.mcp` writes
ai-mirror's *local* entry and nothing remote, and there is deliberately no
option for the above: a switch named for remote agent control would promise a
control that is not there.

See also: [Security](security) for the firewall and SSH generally, and
[Many machines, one repo](many-machines) for where `hosts/<name>/` comes from.
