---
title: nixarchy
---

# nixarchy

[Omarchy](https://omarchy.org) — the Hyprland desktop — vendored for NixOS, with
its menus rewired to Nix instead of pacman.

Omarchy 4.x is not a dotfiles repo, it is an application: 429 shell commands, a
QuickShell desktop shell, 22 themes, and Hyprland configured through the Lua API
introduced in 0.55. nixarchy packages that tree as a derivation and replaces the
parts that assume Arch, rather than reimplementing it in Nix.

Tracking an upstream release is a source bump, not a re-port.

## → [The nixarchy manual](manual/)

What is different here, and only that. Omarchy's manual covers the desktop; this
one covers the port — packages, updates, rollback, the firewall, the agent
skills, and the NixOS philosophy underneath all of it.

New to NixOS? Start with
**[the philosophy](manual/philosophy)** and **[updating NixOS](manual/updating-nixos)**.

## Elsewhere

| | |
|---|---|
| [Source and README](https://github.com/olafkfreund/nixarchy) | installation, module options, design notes, what is left |
| [Omarchy's own manual](https://omarchy.org/manual/) | the desktop itself — 38 of its 51 pages are true here unchanged |
| [Issues](https://github.com/olafkfreund/nixarchy/issues) | including the epic for a bare-metal installer, which does not exist yet |
