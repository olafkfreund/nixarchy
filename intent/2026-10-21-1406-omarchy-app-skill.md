---
status: draft
issue: 1406
author: olafkfreund
---

# Intent: the omarchy-app skill tells an agent on nixarchy how to build and run an app the NixOS way

## Problem

Omarchy 4.5 adds the `omarchy-app` agent skill: "Build a new desktop app
for Omarchy the way Omarchy's own apps are built (Hype, Monologue,
Omacut)". It covers C++ and Qt Quick, `qmake6` and `make`, the live theme,
and "installed as an Arch package so it shows up in the app launcher". It
reaches stable with #1403, and `provision-user` links it into every
agent's skills directory (`~/.claude/skills`, `~/.agents/skills`,
`~/.pi/agent/skills`).

The coding half is portable. The install half is Arch-only:

- **`SKILL.md:32-34`:** if `qmake6` is missing, the skill says to install
  the set with `omarchy-pkg-add`. On nixarchy that command refuses by
  design.
- **`SKILL.md:41-50` and `:146`:** `bin/install` runs `makepkg -fsi` on a
  `pkgbuild/PKGBUILD`, "so the app lands in the launcher". There is no
  makepkg here, and a pacman-installed package would not survive a
  rebuild.
- **`SKILL.md:169-181` ("README and release"):** publishing goes through
  `omacom/omarchy-pkgs` and `install/omarchy-base.packages`. That is
  upstream's release process, and it does not apply to a user's own app.
- **`templates.md`:** seven PKGBUILD, makepkg or pacman references in the
  `bin/install` template and the `pkgbuild/` files.

`pkgs/AGENTS.md#the-agent-skills-upstream-writes-for-arch` already states
the rule: an Arch-shaped skill is "an agent confidently doing imperative
things a rebuild then wipes -- the one failure mode that looks like
success". Every other upstream skill is replaced or patched for NixOS,
and `checks.skill-parity` records it section by section, but only for
the `omarchy` → `nixarchy` skill.

## Proposed outcome

An agent asked to "make me an app" on nixarchy:

- writes the same C++/Qt Quick app with the same theme conventions, so
  the portable half is unchanged;
- builds it with the toolchain from a Nix dev shell (`qmake6`, `make`,
  the Qt 6 modules the template uses), not `omarchy-pkg-add`;
- "installs" it the nixarchy way: a `package.nix` (or `flake.nix`) the
  user adds to their configuration, so it lands in the launcher through
  a rebuild, and `nix run` for trying it;
- is never told to run `makepkg`, `pacman`, or `omarchy-pkg-add`.

## Affected users and systems

- Anyone whose agent loads skills (`claude`, `codex`, `pi`, and so on) on
  a 4.5 machine: edge now, and `main` once #1405 merges.
- `pkgs/omarchy/default.nix` (the skills block, ~:1180-1260),
  `pkgs/omarchy/skills/`, possibly `data/skill-parity.nix`, and
  `docs/manual/ai.md`'s skill table, whose row #1403 wrote.

## Constraints

- **The build fails if upstream rewords a line we depend on**
  (`--replace-fail`, or a whole-file replacement recorded like
  skill-parity). Otherwise the next bump ships Arch instructions again,
  silently.
- **Keep upstream's portable guidance verbatim** (shape, conventions,
  the Qt Quick traps), so an upstream improvement there still arrives.
- **§1:** a check fails while the skill still names
  `makepkg`/`PKGBUILD`/`pacman`/`omarchy-pkg-add` as something to run.
- Waits for #1405, since `main` needs the 4.5 tree.

## Open questions

1. **How to adapt it.** Three options:
   - **(a) Patch in place:** replace the install sections of `SKILL.md`
     and the `bin/install` and `pkgbuild/` templates with Nix
     equivalents, using `--replace-fail` anchors and a
     `pkgs/omarchy/skills/omarchy-app/` overlay file for the Nix
     templates.
   - **(b) Replace the whole skill** with a nixarchy-written one, the way
     the `omarchy` skill is.
   - **(c) Drop the skill** on nixarchy.

   I propose **(a)**. About 80% of the skill is portable and worth
   receiving from upstream; only the install path is wrong.
2. **The check.** Extend `skill-parity` to cover this skill, or a simple
   build-time grep that refuses `makepkg|PKGBUILD|pacman|omarchy-pkg-add`
   as an instruction in any shipped skill? I propose the grep, across
   **all** shipped skills. It also catches the next upstream skill that
   arrives Arch-shaped, which is the general version of this bug (§2).
