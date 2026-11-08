---
status: draft
issue: 1672
author: olafkfreund
---

# Intent: seeded Neovim configs get Omarchy 4.5's transparency files

## Problem

Omarchy 4.5's migration `1791723398` brings two files into a seeded
`~/.config/nvim`: `plugin/after/transparency.lua` and
`lua/plugins/lualine-transparent.lua`. Its own comment says
`~/.config/nvim` "is copied once from omarchy-nvim, so it misses the
package's later changes".

nixarchy's `omarchy-nvim-config` (`pkgs/omarchy-nvim/default.nix`) is not
that package. It is Omarchy's in-tree `config/nvim` at v3.0.2, byte for
byte, because the `omarchy-nvim` pacman package "has no published source"
(the file's own header). That tree has `transparency.lua` and no
`lualine-transparent.lua`. So:

- the migration cannot run here: it exits 1 without the second file, so the
  Pre-4.5 batch declined it (#1673, plan deviation 2);
- every nixarchy Neovim, new or old, lacks the lualine transparency that
  4.5 users on Arch get.

## Proposed outcome

- `omarchy-nvim-config` ships `lua/plugins/lualine-transparent.lua`, from
  a source the repository can name and pin.
- The migration row moves from `declined` to `ported` (edited copy, as in
  the Pre-4.5 plan's original decision), so pre-4.5 seeded configs get both
  files, through the script's own symlink guards.

## Affected users and systems

- Everyone with `programs.nixarchy.neovim != "off"`.
- `pkgs/omarchy-nvim/`, `data/user-migrations.nix`,
  `pkgs/omarchy/user-migrations.nix`, `tests/user-migrations/`.

## Constraints

- The seed refuses an existing `~/.config/nvim` (`modules/home.nix:~464`),
  so only the migration reaches existing users, and only where it finds
  the files missing.
- A home-manager-linked config is the user's (#1304); the script's own
  symlink guards stay.
- Licensing: the tree is MIT; whatever source is used must be one the
  package can cite.

## Open questions

1. **Where the file comes from.** One option is Omarchy's pacman repository
   package `omarchy-nvim` (a binary `.pkg.tar.zst`, MIT, fetched by URL and
   hash, with this one file extracted). The other is to write the file by
   hand from the migration's description. The first follows upstream
   exactly, but pins a binary repository's URL. The second has no upstream
   to follow, which the header already warns about. The recommendation is
   the first, pinned by hash, with the URL in the header.
2. Bring the whole 4.5 `omarchy-nvim` tree up to date while there, or only
   this one file? The recommendation is the one file: the rest has had no
   reported gap.
