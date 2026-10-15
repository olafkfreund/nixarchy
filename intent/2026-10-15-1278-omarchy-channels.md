---
status: approved
issue: 1278
author: olafkfreund
---

# Intent: Omarchy edge and dev channels, separate from the nixpkgs channel

## Problem

Users ask to test Omarchy **edge** and **dev** on nixarchy. Nixarchy follows
only Omarchy's stable release tags (`flake.nix` pins
`github:basecamp/omarchy/v4.0.4`), and nothing lets a user choose otherwise.

On Arch an Omarchy channel is a pacman repository, `pkgs.omarchy.org/<channel>`,
and `omarchy-channel-set` switches it. That changes two things together:

- **The Omarchy source.**
  - stable: a release tag.
  - edge: the tip of `quattro`, packaged as `omarchy-dev`.
  - dev: a local `~/omarchy` checkout linked over the install.
- **The Omacom package set.** On 2026-10-15:
  - edge held 258 packages to stable's 237;
  - 52 packages were newer on edge;
  - 33 existed only on edge.

  `quattro`'s `install/omarchy-base.packages` names packages `v4.0.4` does
  not: hype, monologue, omasnap, omarchy-hyprland-titlebars, owe-lockfeed,
  signed, disktree-bin and more.

Nixarchy lacks all three pieces:

1. **No way to choose the Omarchy source.**
   - `nixarchy channel` and the menu's Channel rows switch **nixpkgs**
     (stable or unstable, #529).
   - The RC and Dev rows are hidden.
   - `omarchy-channel-current` prints `dev` on every nixarchy machine,
     because `OMARCHY_PATH` is a store path.
2. **No edge packages.** Several packages edge needs have no nix package here.
3. **No checks against anything but a stable tag.**
   - `.github/workflows/omarchy.yml` builds and briefs only `releases/latest`.
   - The one recorded build against `quattro` (`docs/internals/design.md`,
     "What is left") brought `coexist` and `plugin` up to a black desktop.
     Nobody found out why.

## Proposed outcome

- **Users can choose an Omarchy channel:**
  - **stable**, the default, as today;
  - **edge**, a recent `quattro` that has passed nixarchy's checks;
  - **dev**, the user's own Omarchy checkout, built with nixarchy's patches.
- **The Omarchy channel is independent of the nixpkgs channel.** Every pairing
  is a valid machine, for example nixos-unstable with stable Omarchy, or
  nixos-unstable with edge Omarchy. Switching one never moves the other.
- **The machine can say which Omarchy channel it is on.** Both
  `omarchy-channel-current` and the doctor answer correctly.
- **Edge only moves when it works.** A user on edge gets the newest `quattro`
  that built and passed nixarchy's checks, never a tip that is broken on NixOS.
- **Maintainers see edge breakage before a release reaches stable**, with a
  report naming what broke: a patch anchor, a missing package, or a check.

## Affected users and systems

- **Users:** anyone who opts in. A stable user's machine does not change.
- **Code that would change:**
  - `flake.nix`;
  - `pkgs/omarchy` (patches, the channel scripts);
  - `pkgs/omarchy/nix-bin/nixarchy-channel`, or a sibling command;
  - `modules/apps.nix` (menu rows);
  - the doctor;
  - `.github/workflows/omarchy.yml`, or a new workflow;
  - packages for the edge-only Omacom apps.
- **CI:** p620's self-hosted runners for edge's VM checks; hosted runners for
  builds.
- **Docs:** the manual's updates page.

## Constraints

- **Mode A stays untouched.** A machine importing the module with nothing
  opted in evaluates exactly as before.
- **The stable path does not change** for users who do nothing:
  - same pin;
  - same `omarchy.yml` bump;
  - same release cadence.
- **The nixpkgs channel and the Omarchy channel are separate settings,** with
  separate commands and separate menu rows.
- **Only lines nixarchy wrote get rewritten** in the user's flake, the rule
  `nixarchy-channel` and `nixarchy-unfreeze` follow. A reshaped flake gets the
  edit printed, not guessed.
- **No edge closures in nixarchy.cachix.org.** It is the free tier, 5 GB with
  an allowlist (#697).
- **Edge's VM checks respect p620's two install slots** and the tier rule in
  CLAUDE.md §6. They must not starve pull-request installs.
- **Changing CI gates or workflows needs a human** (CLAUDE.md §11). The plan
  proposes; the owner merges.
- **Every new check is proven to fail first** (CLAUDE.md §1).

## Open questions

1. **Where edge lives.** Two candidates:
   - a git branch of nixarchy that a bot moves forward (how nixos-unstable
     works);
   - a second flake input selected by an option.

   This decides how the patch set diverges between stable and edge. Resolve
   it in the spec.
2. **Dev's shape.** Two candidates:
   - a rebuild from the checkout with Omarchy's input overridden (patches
     apply, rebuild per change);
   - a live link like upstream's.

   The live link bypasses the patches that make Omarchy work on NixOS.
3. **How far to go on edge-only packages.** Package all 33 edge-only apps
   up front, or only those `quattro` itself requires to boot?
4. **What edge users see when edge stalls.** A warning after N days without
   a move, or nothing?
