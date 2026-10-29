---
status: draft
issue: 1513
author: olafkfreund
---

# Intent: a sandbox that runs the nixarchy desktop, for an agent to drive

## Problem

`hyprland-ai-mirror` (#1504) gives an MCP agent a disposable desktop it can
drive without asking, but that desktop is bare Hyprland. It has no omarchy
shell, bar, plugins, theme or keybindings, and none of the `omarchy-*`
commands. Anything that depends on the nixarchy desktop itself can't be
tried in a sandbox. That covers a bar widget, a plugin, a theme, a
keybinding, an omarchy command, or how an app behaves inside that session.
Today it gets tried on the real desktop, where every action needs a human to
confirm and a mistake lands on the user's own session, or it isn't tried at
all.

## Proposed outcome

`nixarchy vm create <name> --template <new>` followed by
`nixarchy vm run <name>` boots the stock nixarchy desktop headless: the
omarchy shell and bar, the default plugins, a theme, and the default
keybindings. It has ai-mirror inside, reachable from the host over vsock
exactly as `hyprland-ai-mirror` is. An agent can then:

- call `index` and get nixarchy's keybindings and plugins back, not bare
  Hyprland's;
- open the launcher, a bar widget or an omarchy command;
- take screenshots that show the nixarchy desktop.

The VM is disposable like the other templates. Stopping it is the kill
switch.

## Affected users and systems

- nixarchy: `data/microvm-templates.nix`, `modules/microvm/templates/`,
  `flake.nix` (`lib.mkMicrovm` and `checks.microvm-template`), and
  `docs/manual/sandboxes.md`.
- Anyone running `nixarchy vm` gets a new template. Nothing changes for
  existing templates or hosts.
- p620 is where it will be measured.

## Constraints

- **The catalogue's bar.** `data/microvm-templates.nix` says "a template is
  exactly a NixOS module … no nixarchy vocabulary … A template imports
  nothing else nixarchy ships." This template can't meet that rule, because
  its whole point is to import nixarchy. Either the rule gets a named
  exception or the template lives somewhere else (open question 1).
- **No host GL.** The guest renders in software, as in #1506. The Quickshell
  bar and animations will be slower than on the real desktop. That's fine
  for functional testing, not for judging smoothness.
- **Same consent model as #1504.** Starting the VM is the consent, and the
  real desktop's gate is untouched. Whoever reaches the vsock port gets the
  guest's user, sudo and network, so the docs keep the "not on a shared
  machine" warning.
- **One closure per template.** The runner is shared by every VM made from
  it, so nothing may depend on the VM's name.
- **CI cost.** `checks.microvm-template` builds every template for KVM and
  TCG. A full desktop closure makes that check much heavier.
- **No secrets, no host services.** It's the stock desktop, not a copy of
  p620 (option B was rejected in conversation).

## Open questions

1. **Where does it live?** A catalogue template that is an exception to the
   bar and imports `nixosModules.nixarchy`? Or a microvm variant of the
   existing smoke VM (`vm/configuration.nix` and `installer/host.nix`),
   outside the catalogue's rule?
2. **Is it in `checks.microvm-template`?** If not, what proves it still
   builds?
3. **Which nixarchy?** The VM's runner is pinned to the nixarchy rev that
   built the `nixarchy vm` CLI. Should "try a nixarchy branch in the
   sandbox" be in scope, or come later?
