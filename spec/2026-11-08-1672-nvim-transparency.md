---
status: approved
issue: 1672
intent: intent/2026-11-08-1672-nvim-transparency.md
---

# Spec: seeded Neovim configs get Omarchy 4.5's transparency files

## Design

### 1. The file (owner decisions 1 and 2)

The source is Omarchy's own repository, the one `default/pacman/pacman-stable.conf:19-20`
configures on Arch (`[omarchy]`, `Server = https://pkgs.omarchy.org/stable/$arch`).
Its `omarchy.db`, read on 2026-11-08:

| field | value |
|---|---|
| `%FILENAME%` | `omarchy-nvim-2026.9.21-5-any.pkg.tar.zst` |
| `%SHA256SUM%` | `b46d41973cacfcf2d8be371351336a3f689e2eb7b9bacdb7ca81939354cbcbc9` |
| `%LICENSE%` | MIT |

**Vendored, not fetched.** `lua/plugins/lualine-transparent.lua` is
extracted once from that archive and committed to
`pkgs/omarchy-nvim/config/lua/plugins/`. The plan's first step downloads the
archive, checks its sha256 against the table, finds the file's path inside
it (the migration reads `/usr/share/omarchy-nvim/config`, `1791723398.sh:6`),
and records both in `pkgs/omarchy-nvim/default.nix`'s header as provenance:
the URL, the version, the archive's sha256, and the path the file came
from. The derivation is unchanged (`src = ./config` copies it). There is
no fetch at build time, and nothing breaks if the repository drops that
version. `meta.description` notes the one newer file.

### 2. The migration row

`1791723398` moves from `declined` to `ported`, `run = "edited"`, with the
Pre-4.5 plan's first edit (its decision 1, deferred by its deviation 2):

- `/usr/share/omarchy-nvim/config` becomes `${omarchy-nvim-config}/share/omarchy-nvim`;
- `omarchy-pkg-present omarchy-nvim || exit 0` becomes a guard with two
  conditions, both required:
  1. `[[ ${NIXARCHY_NEOVIM:-} != off ]]`. The `user-migrations` hook
     (`modules/home.nix`, the `post-boot.d/user-migrations` entry) exports
     `NIXARCHY_NEOVIM=${cfg.neovim}`. Under `off` nothing is touched (owner
     decision 2).
  2. `~/.config/nvim/plugin/after/transparency.lua` exists **and** its
     sha256 is one of the three the script itself treats as "as Omarchy
     shipped it" (`1791723398.sh:44-52`). nixarchy's seeded copy is
     `bd833dc0…`, the first of them.

The seed writes no marker of its own (`modules/home.nix:464-470` copies the
tree and echoes a line), so the second condition is the closest real
signature: Omarchy's own file, unmodified. That narrows the claim. The
migration reaches **configs that carry Omarchy's unmodified
`transparency.lua`**: every config nixarchy seeded, and any copied from
Omarchy by hand, which is Omarchy's config too. A user's own LazyVim
config, or a seeded one whose `transparency.lua` the user edited, is left
alone.

`pkgs/omarchy/user-migrations.nix` gets the `1791723398` case back, and its
`omarchy-nvim-config` argument. The script's own symlink guards stay.

### 3. What arrives, by seed

Every nixarchy seed came from this vendored tree, which has carried
`plugin/after/transparency.lua` (hash `bd833dc0…`) since the package was added
(d753f840, #56, 2026-08-30), and never `lualine-transparent.lua`. So a
pre-4.5 nixarchy seed gets one file, `lualine-transparent.lua`. Its
`transparency.lua` matches a shipped hash, so the script "replaces" it with
the package's copy, which is the same v3.0.2 file (owner decision 2 vendors
only the one new file): a byte-identical rewrite. No nixarchy seed ever
lacked `transparency.lua`, so the case where both files arrive does not
occur here. The fixture still covers it as upstream's behaviour: without
`transparency.lua`, the guard skips.

### 4. Branch order

`pkgs/omarchy/user-migrations.nix`, the ledger's `run` field and the
harness exist only on `feat/1673-pre45-migrations` (the Pre-4.5 PR). This
branch stacks on it: the implementation merges `feat/1673-pre45-migrations`
in first, and merges `main` in once that lands (never a rebase of a pushed branch). Section 1 alone would
not need it, but the row in section 2 does, and they land together.

## Alternatives rejected

- **Fetch the archive at build time** (the intent's first wording). It
  is 33 MB for a 1 KB file, and a build that fails if the repository drops
  the version (owner decision 1).
- **Write the file by hand.** It has no upstream to follow.
- **Vendor the whole 4.5 tree.** No gap has been reported in the other
  files.
- **Keep the row declined.** Every nixarchy Neovim then lacks 4.5's lualine
  transparency.

## Risks

- **A vendored file does not follow upstream.** A later `omarchy-nvim`
  that changes `lualine-transparent.lua` is not picked up; the header's
  provenance says which version this is. That's the same arrangement as the
  rest of the v3.0.2 tree.
- **New seeds change.** LazyVim reads every file under `lua/plugins` as a
  spec, which is the intended effect, matching 4.5 on Arch.

## Verification

- `nix build .#omarchy-nvim-config` (package tier) contains the file.
- `checks.user-migrations` (on the stacked branch), `case_1672`:
  - a seeded config (the vendored tree, with `transparency.lua` at
    `bd833dc0…`) minus `lualine-transparent.lua` gets it; `transparency.lua`
    is unchanged; a second run changes nothing;
  - `NIXARCHY_NEOVIM=off`: the same fixture stays byte-identical;
  - a user's own LazyVim config (a `lua/plugins` directory, no Omarchy
    `transparency.lua`) stays byte-identical;
  - a seeded config with an edited `transparency.lua` stays byte-identical;
  - a symlinked `lua/plugins` is left alone;
  - `oracle_run` with upstream's original, its `/usr/share/omarchy-nvim/config`
    pointed at the fixture's package directory, matches the port on the
    seeded fixture.
- §1, per guard: drop condition 1 and the `off` case fails; drop condition
  2 and the own-config case fails; set the row back to `declined` and the
  seeded case fails.
- `checks.user-migrations-ledger`, `bin-ledger`, fmt, statix, deadnix.

## Decisions (owner, 2026-11-08, on the draft)

1. **Vendor the file, not fetchurl** (this replaces the intent's "fetched by URL"). `lua/plugins/lualine-transparent.lua` is extracted once from `omarchy-nvim-2026.9.21-5-any.pkg.tar.zst` and committed into `pkgs/omarchy-nvim/config`. The package URL and its sha256 from Omarchy's `omarchy.db` go in `pkgs/omarchy-nvim/default.nix`'s header as provenance. No 33 MB fetch at build time, and no build failure if the repository drops that version. The plan's first step verifies the file's path in the archive and records the archive hash it was taken from.
2. Under `neovim = "off"`, nothing is touched: the migration does not run for a config nixarchy does not manage.
