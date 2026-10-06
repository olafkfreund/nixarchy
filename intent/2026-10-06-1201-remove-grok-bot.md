---
status: draft
issue: 1201
author: olafkfreund
---

# Intent: remove grok-bot from nixarchy

## Problem

`grok-bot` (`pkgs/apps/grok-bot.nix`) packages the Grok Bot Electron app from
a `.deb` on Cursor's CDN. It costs more than it gives:

- **It is unfree.** `nix flake check --no-build` on `main` stops with
  `Refusing to evaluate package 'grok-bot-0.24.0' ... unfree license`, so the
  flake cannot be checked with the standard command. `build.yml` needs
  `NIXPKGS_ALLOW_UNFREE=1` in "Build every app the flake ships itself"
  because of it.
- **It cannot be kept current.** It is pinned to a CDN commit hash with no
  update script. `update.yml` cannot bump it, and `pkgs/review.sh` can only
  report how old the pin is.
- It is the only reason for some of that special handling, and nobody here
  uses it.

The maintainer has decided it goes.

## Proposed outcome

- No `grok-bot` package, overlay attribute, flake package output, or
  `Install > AI > Grok Bot` row that installs anything.
- `nix flake check --no-build` evaluates on `main` with no unfree override,
  unless something else unfree is also exposed.
- A user who enabled Grok Bot from the menu can still rebuild, and is told
  clearly that it was removed.
- The `grok` coding agent (`grok-cli`, `omarchy-default-agent grok`,
  `modules/apps.nix:1237`, `modules/nixos.nix:631`) is untouched. It is a
  different program.

## Affected users and systems

- Installed machines that have `grok-bot.enable = true` in
  `~/.config/nixarchy/apps.nix`.
- `pkgs/apps/grok-bot.nix`, `flake.nix` (overlay `:806`, packages `:1266`),
  `data/apps.nix` (the entry and three comments that count AI rows),
  `.github/workflows/build.yml`, `.github/workflows/update.yml`,
  `pkgs/review.sh`, `docs/manual/ai.md`, `docs/internals/flake.md`.
- The menu-mapping check (`.github/scripts/check-menu-mapping.py`), which
  expects every upstream Omarchy `install.*` row to map to an app entry.

## Constraints

- A user with `grok-bot.enable = true` must not get an evaluation error that
  stops their rebuild. They get a warning or a clear message instead.
- The upstream Omarchy menu still has an `install.ai.grok-bot` row. The
  menu-mapping check must stay green, and the row must say why it is gone
  rather than vanishing silently (the pattern `data/apps.nix` already uses
  for `unavailable` entries).
- Unrelated unfree apps offered in the menu keep working.
- Must not land in the same release as #1200 untested. It goes through the
  normal PR checks.

## Open questions

1. **Keep a menu row marked unavailable, or drop the entry entirely?**
   Keeping it with `unavailable = "..."` matches sublime and brave-origin and
   keeps the menu-mapping check honest.
2. **How to handle an existing `grok-bot.enable = true`?** `unavailable`
   entries generate no option today, so the setting becomes an unknown
   option and evaluation fails. The options are a removed-option shim with a
   warning, or extending the `unavailable` mechanism so that enabling such an
   app warns instead of failing. The second would also cover sublime and
   brave-origin users.
3. **`build.yml`'s `NIXPKGS_ALLOW_UNFREE=1`:** remove it, or keep it because
   other unfree apps (if any) still need it? This is answered by checking which
   flake outputs are unfree once grok-bot is gone.
