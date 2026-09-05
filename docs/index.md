---
title: nixarchy
layout: home
---

[Omarchy](https://omarchy.org) — the Hyprland desktop — vendored for NixOS, with
its menus rewired to Nix instead of pacman.

Omarchy 4.x is not a dotfiles repo, it is an application: 429 shell commands, a
QuickShell desktop shell, 22 themes, and Hyprland configured through the Lua API
introduced in 0.55. nixarchy packages that tree as a derivation and replaces the
parts that assume Arch, rather than reimplementing it in Nix.

Tracking an upstream release is a source bump, not a re-port.

## Install it on a blank machine

```
nix build github:olafkfreund/nixarchy#iso
sudo dd if=result/iso/nixarchy-*.iso of=/dev/sdX bs=4M status=progress oflag=sync
```

Boot it. No boot menu and no login prompt — the installer is what comes up. It
asks the questions Omarchy asks, in the same order, encrypts the disk unless you
opt out, and is done in a few minutes.

![Installing nixarchy](img/installer/install.gif)

What you end up with is **a flake you own** at `/etc/nixos`: a git repository
holding the disk layout, the configuration and your app selection. A rebuild
straight after installing builds nothing, because everything the installer did
is written there rather than done behind it.

The ISO still downloads rather than carrying its own closure, so an install
needs a network — [see the manual](manual/getting-started) for that and the
other limits. Already running NixOS? Then you want the flake, not the ISO, and
that is on the same page.

## Search everything, install declaratively

Omarchy's Install menu offers 56 applications. **Install ▸ Search** offers the
rest of NixOS — one fuzzy picker over **137,599 rows**: every nixpkgs package,
every NixOS option, and the app selection, with each entry's type, default and
documentation in a preview pane.

```
nixarchy > tailscale
app  tailscale                          Tailscale (Service)
pkg  tailscale                          Node agent for Tailscale, a mesh VPN …
opt  services.tailscale.enable          Whether to enable Tailscale client daemon
opt  services.tailscale.authKeyFile     A file containing the auth key …
```

The three kinds are not interchangeable, and the rows say so: the app row gets
you `services.tailscale` with its daemon, the package row gets you the CLI and
nothing running. Picking routes to whichever writer is right — an app is
enabled as an app, a package is validated and appended, an option is written as
a line of its own. Booleans and enums get a value picker; anything more
complicated is written commented out with its type and docs beside it, because
an option's value is arbitrary Nix and a form that pretended otherwise would
write plausible-looking wrong configuration.

Nothing is built until you apply. The index comes from *this machine's* nixpkgs
and options rather than from search.nixos.org, so it can never offer something
the machine will then refuse to build.

This is the whole model in twenty seconds — a pick becomes a line in a file
you own, and only then a rebuild:

![nixarchy-app-enable helix writes a declaration into ~/.config/nixarchy/apps.nix — grep shows the uncommented line — then nixarchy-apply copies it into the flake and offers the rebuild](img/features/install.gif)

See **[other packages](manual/other-packages)** for the whole flow.

## An agent that knows this machine

Omarchy symlinks its agent skills into every harness's skill directory. Upstream
ships one, written for Arch; nixarchy ships ten, written for NixOS — the desktop,
packages, GPUs, services, secrets, performance, security, log triage, and getting
the configuration into git.

That matters more than it sounds. A model asked how to install a package on NixOS
will confidently invent an answer; the same model handed the `nixos` skill routes
to `nixarchy-pkg-add` and a rebuild. The skills were written against the modules
on disk rather than from memory, which is how they caught two options current
models still write and that no longer exist.

**Menu ▸ Trigger ▸ Ask** turns them into ten things you can click — *What's
wrong?*, *Make it faster*, *Am I exposed?*, *Disk is full* — each routed to the
skill that answers it, through whichever agent you have chosen.

![The Ask menu](img/desktop/menu-ask.jpg)

```nix
programs.nixarchy.localAi.enable = true;
```

runs the whole thing locally against Ollama, with the accelerator derived from
the GPU your configuration already declares. It refuses to build without one,
and the refusal explains why with the measurements behind it.

See **[the AI page](manual/ai)**.

## → [The nixarchy manual](manual/)

What is different here, and only that. Omarchy's manual covers the desktop; this
one covers the port — packages, updates, rollback, the firewall, the agent
skills, and the NixOS philosophy underneath all of it.

New to NixOS? Start with
**[the philosophy](manual/philosophy)** and **[updating NixOS](manual/updating-nixos)**.

## Elsewhere

| Where | What is there |
|---|---|
| [Source and README](https://github.com/olafkfreund/nixarchy) | installation, module options, design notes, what is left |
| [Omarchy's own manual](https://omarchy.org/manual/) | the desktop itself — 38 of its 51 pages are true here unchanged |
| [Issues](https://github.com/olafkfreund/nixarchy/issues) | including the epic for a bare-metal installer, which does not exist yet |
