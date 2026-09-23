---
status: draft
issue: 912
author: olafkfreund
---

# Intent: nixarchy-flatsnap ships with nixarchy

Closes #912.

## Problem

Software that nixpkgs does not carry, or carries late, is often published as a
Flatpak or a Snap. nixarchy has half of an answer. `data/flatpaks.nix` declares
a curated handful of Flatpaks through nix-flatpak. Anything outside that list
means `flatpak install` in a terminal, which `flatpaks.uninstallUnmanaged` then
deletes at the next rebuild. Snap has no route at all, because nixpkgs has no
snapd service.

[nixarchy-flatsnap](https://github.com/olafkfreund/nixarchy-flatsnap) closes that
gap as an Omarchy menu plugin:
- paste a Flathub or Snapcraft link, an app ID, or an `install` line;
- read the app's permissions or confinement;
- queue it, and apply.

The result is declarative:
- Flatpaks go into `services.flatpak.packages`.
- Snaps go into a small reconciler on top of nix-snapd.

It is tested end to end on razer, through the real `nixarchy-apply`.

It is not part of nixarchy, though. Using it today means:
- adding a flake input;
- importing the right one of its two NixOS modules — `default` brings
  nix-snapd, `flatsnap` does not, and picking wrong fails evaluation with
  "`services.snap.enable` … is already declared";
- declaring the plugin in Home Manager;
- enabling it.

Its *Install → Flatpak & Snap* row reaches the menu only through
`programs.nixarchy.menu.extraEntries`, because `menu-verbs` (correctly) refuses
a `nixarchy-plugin` row for a plugin nixarchy does not ship. That is five steps
of wiring for one of the first things a new user wants to do: install an app
that is not in nixpkgs. Every other install path on the menu (packages,
services, options) works out of the box.

## Proposed outcome

On a nixarchy machine, with no configuration beyond `programs.nixarchy.enable`:

- *Install → Flatpak & Snap* is in the Omarchy menu and opens the panel, the
  same way *Install → Packages* opens nixarchy-pkg.
- Pasting an app, queuing it and applying installs it, and un-declaring it and
  applying removes it, with no flake edits by the user.
- Nothing about Snap runs until a Snap is declared. Today, with the plugin on
  and nothing declared, there is no snapd daemon, no setuid `snap-confine`, and
  no extra unit. That must hold for every nixarchy user after this ships.
- Someone who does not want it turns it off with one option, like the other
  default plugins (`programs.nixarchy.defaultPlugins.flatsnap = false`).

## Affected users and systems

- **Every nixarchy user**, if the plugin is on by default. At minimum they get:
  - the plugin files;
  - one menu row;
  - an evaluated-but-inert NixOS module.
- **Flakes that already import nix-snapd themselves.** `olafkfreund/nixos_config`
  does, for every host (`flake.nix:451`). Whatever nixarchy does about nix-snapd
  decides whether their next update evaluates at all.
- **`modules/home.nix`** `defaultPluginSet`, **`modules/nixos.nix`** imports,
  **`modules/apps.nix`** menu rows, **`flake.nix`** inputs,
  **`docs/internals/flake.md`**, **`tests/options.nix`**, and possibly the
  **manual** (`docs/manual/`).
- **nixarchy-flatsnap itself.** Its module adds the same menu row through
  `extraEntries`. Once nixarchy owns the row, that has to stop or become
  identical.
- **Hosts to prove it on:** razer (a standing test host).

## Constraints

- **Must not break a flake that already imports nix-snapd.** A second import of
  its module declares `services.snap` twice, and evaluation fails. This is the
  single hardest constraint here, and it is why the plugin ships two module
  outputs.
- **Must not start snapd for users who declare no Snap.** The plugin's
  `snaps != [ ] || pendingRemoval != [ ]` gate must survive being imported by
  default.
- **Must not import nix-flatpak a second time.** nixarchy already does, and the
  plugin's `flatsnap` output relies on the host's copy.
- **Pinned like every other plugin input:** a commit on main, bumped the way
  `docs/internals/flake.md` describes. That needs olafkfreund/nixarchy-flatsnap#2
  merged first.
- **#906 lands first, or is folded in.** Without `flatsnap` in
  `nixarchy-apply`'s loop, the panel's apply writes a file that is never copied.
  The plugin's preflight refuses with a clear message, but shipping a plugin
  whose apply cannot work is not acceptable.
- **Security posture is visible, not buried.** nix-snapd has no AppArmor and a
  setuid `snap-confine`, so "strict" Snaps on NixOS are weaker than on Ubuntu.
  Shipping this by default puts that one menu row away from every user. The
  panel already says so on every Snap; the nixarchy manual should say it too.
- The usual nixarchy rules apply: every new check is built by a PR-triggered
  workflow, `tests/options.nix` covers both states of any new option, and
  nothing is written outside `~/.config/nixarchy/`.

## Open questions

1. **Who imports nix-snapd?**
   - **(a)** nixarchy imports it, the way it imports nix-flatpak. Stock nixarchy
     gets Snap support, but every flake that imports nix-snapd itself (including
     `nixos_config`) must drop its own import in the same update, or it fails to
     evaluate.
   - **(b)** nixarchy imports only the plugin's `flatsnap` module, and Snap works
     only where the host brings nix-snapd. There is no breakage, but on stock
     nixarchy the Snap half of the panel queues things that never install, unless
     the panel detects that and says so.
   - **(c)** nixarchy imports nix-snapd behind a flake-level switch. This is
     possible only as a separate module output, because imports cannot depend on
     option values.

   *Recommendation:* (a), with a release note and the `nixos_config` change in
   the same rollout. It is the only option where "works out of the box" is true
   for Snap, and nix-flatpak is the precedent.
2. **On by default, or opt-in?** nixarchy-pkg is always on. The plugin UI and an
   inert module cost nothing, and snapd stays off until a Snap is declared.
   *Recommendation:* on by default, with `defaultPlugins.flatsnap = false` as the
   opt-out, gated only on `programs.nixarchy.enable`.
3. **Where the menu row lives.** Move `install.flatsnap` into nixarchy's own rows
   (`menu-verbs` then accepts it, because the plugin is shipped), and drop the
   plugin's `extraEntries` row in a plugin release. The alternative is to keep
   both identical, since `types.anything` merges equal values, but that is two
   sources of one row. *Recommendation:* move it.
4. **#906: separate or folded in?** *Recommendation:* merge #906 first. It is
   useful and safe on its own, and it keeps this PR to the shipping change.
5. **Manual page.** Add `docs/manual/flatpak-and-snap.md` (install, keys, the
   Snap confinement caveat, and `--purge` on removal), or a section of the
   existing packages page? *Recommendation:* its own page, listed in the `nav`.
