---
status: approved
issue: 913
author: olafkfreund
---

# Intent: ship the Plugin Browser, so Add Plugin opens a searchable, sandbox-audited marketplace

## Problem

**Setup → Plugins → Add Plugin** is upstream's stock row. It opens a
terminal that asks for a Git URL and runs `omarchy-plugin-add`. On nixarchy
that has two problems.

- **Nothing checks what a plugin runs before it is installed.** #361 found
  that plugins are validated for their shape, never for what they execute.
  The marketplace (plugins.omarchy.org, 3,977 community plugins on
  2026-09-23) is written for Arch. Many of those plugins call `pacman` or
  `yay`, read `/usr/share/omarchy`, or use FHS paths. They install cleanly,
  then break at runtime or tell the user to run a package manager this
  distro does not have. The user learns this after the install, not before.
- **You have to know the URL already.** There is no way to browse or search
  the marketplace from the desktop. The only discovery path is a web page,
  and that leads back to the unchecked prompt.

Something that solves both already exists.
[olafkfreund/nixarchy-plugin-browser](https://github.com/olafkfreund/nixarchy-plugin-browser)
(0.5.0) is a keyboard-driven shell panel.
- It searches the catalog and shows each plugin's marketplace preview.
- It audits a plugin in a bubblewrap sandbox and reports two verdicts: a
  security verdict, and a NixOS-compatibility verdict (FHS paths, imperative
  package managers, writes to `/etc`, bundled ELFs).
- It installs **disabled**, at the audited commit.
- On request it hands the findings to the default agent (the `nixarchy ask`
  path) to explain them, or to fix a disposable copy.

It has its own `flake.nix`. Its full desktop checklist passed on razer on
2026-09-23, recorded. But it reaches a machine only by hand: a clone, plus
`menu.extraEntries` and a keybinding file in one user's `nixos_config`.
Nobody else gets it.

## Proposed outcome

On a nixarchy machine, with no configuration by the user:

- **Setup → Plugins → Add Plugin opens the Plugin Browser panel.** The
  panel shows the marketplace, searchable from the keyboard.
- Opening a plugin shows its sandboxed audit and its NixOS verdict before
  anything is installed. Installing is an explicit keypress and lands the
  plugin disabled.
- **Super+Alt+U** opens the panel, as the other shipped panels have their
  own key.
- The audit works out of the box: `bubblewrap` is present wherever the panel
  is, so the audit never falls back or fails for lack of a sandbox.
- Adding a plugin by Git URL is still possible for someone who has one; the
  panel does not remove that capability.
- A machine that wires the plugin in by hand today (p620 and razer, through
  `nixos_config`) can drop that wiring and get the same result from nixarchy.

## Affected users and systems

- **Everyone on nixarchy:** the Add Plugin row, a new default panel, a new
  keybinding, and `bubblewrap` plus the plugin's CLI on the session PATH.
- **This repo:** `flake.nix` (a pinned input), `modules/home.nix` (the
  shipped-plugins table), `modules/apps.nix` (the menu row),
  `pkgs/omarchy/default.nix` (the binding), `docs/internals/flake.md`, the
  README's plugin and derived-number sections, and the checks that cover
  them.
- **olafkfreund/nixarchy-plugin-browser:** it becomes an upstream of
  nixarchy, and its commits are bumped the way the other panel inputs are.
- **`olafkfreund/nixos_config`** (p620, razer): its hand wiring
  (`hosts/common/nixos/omarchy-plugin-browser.nix`) becomes redundant, and
  is removed in a follow-up there, not here.
- **CI:** the shipped plugin passes the same plugin checks as the others,
  including the pacman/yay grep.

## Constraints

- **Security must not regress:**
  - the audit fails closed without bwrap;
  - installs stay disabled and pinned to the audited commit;
  - no plugin text reaches the agent's prompt;
  - both agent confirms default to No.
- **The agent hand-off runs with auto-approve on untrusted code.** Shipping
  it by default puts that one keypress (plus a confirm) in front of every
  user. That needs a deliberate decision (see the open questions), not a
  side effect of shipping the panel.
- **The input is pinned to a commit and follows nixpkgs,** like the other
  panel inputs, with a `# Why:` link to its `docs/internals/flake.md`
  section.
- **No new network access at build time.** The catalog and the previews
  are fetched at run time, only when the panel is opened, and only from
  plugins.omarchy.org.
- **A changed menu row needs a re-login to appear.** This was found on
  razer: the session keeps the login-time `OMARCHY_PATH` tree. The docs or
  release notes must say so; this change does not try to fix it.
- **Upstream's menu stays upstream's.** The override replaces one row by id
  and restates its icon, label and action, as nixarchy's other overrides do.

## Open questions

1. **On by default, or gated?** The proposal is on wherever nixarchy is, like
   pkg and microvm, because Add Plugin is on everywhere. The alternative is a
   `programs.nixarchy.*` switch, off by default.
2. **The agent hand-off (`e`/`f`).** Ship it on as today, with the warning
   and a No-default confirm, or ship the panel with the hand-off off by
   default behind a setting?
3. **Plugin id.** Keep `io.github.olafkfreund.nixarchy-plugin-browser`
   (precedent: `olafkfreund.github-actions`), or rename it to
   `nixarchy.plugin-browser` as the in-house panels are named? A rename
   orphans existing hand installs.
4. **Where "add by URL" lives.** A key inside the panel, or a second menu
   row ("Add Plugin from URL") that keeps the stock prompt.
