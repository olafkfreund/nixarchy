---
status: draft
issue: 1672
intent: intent/2026-11-08-1672-nvim-transparency.md
---

# Spec: seeded Neovim configs get Omarchy 4.5's transparency files

## Design

### 1. The file (intent decisions 1 and 2)

The source is Omarchy's own repository, the same one `default/pacman/pacman-stable.conf:19-20`
configures on Arch (`[omarchy]`, `Server = https://pkgs.omarchy.org/stable/$arch`).
Its `omarchy.db` lists, read on 2026-11-08:

| field | value |
|---|---|
| `%FILENAME%` | `omarchy-nvim-2026.9.21-5-any.pkg.tar.zst` |
| `%CSIZE%` | 34305549 (about 33 MB) |
| `%SHA256SUM%` | `b46d41973cacfcf2d8be371351336a3f689e2eb7b9bacdb7ca81939354cbcbc9` |
| `%LICENSE%` | MIT |

`pkgs/omarchy-nvim/default.nix` gains a `fetchurl` of
`https://pkgs.omarchy.org/stable/x86_64/omarchy-nvim-2026.9.21-5-any.pkg.tar.zst`
with that hash in SRI form. Its `installPhase` extracts exactly one path,
the package's `lualine-transparent.lua` (under `usr/share/omarchy-nvim/config/`,
the prefix migration `1791723398.sh:6` reads), with `tar --zstd -xf ... -O <path>`
into `$out/share/omarchy-nvim/lua/plugins/lualine-transparent.lua`. A missing
path fails the build. `zstd` joins `nativeBuildInputs`.

The rest of the v3.0.2 tree stays `src = ./config`, unchanged. The header
gains a paragraph naming the URL, the version and why one file comes from
the binary package. `meta.description` notes the one file.

### 2. The migration row

`1791723398` moves from `declined` to `ported`, `run = "edited"`, with the
edit the Pre-4.5 plan approved first (its decision 1) and later deferred to
this issue (its deviation 2):

- `/usr/share/omarchy-nvim/config` becomes
  `${omarchy-nvim-config}/share/omarchy-nvim`;
- `omarchy-pkg-present omarchy-nvim || exit 0` becomes
  `[[ -d $package && -f $config/plugin/after/transparency.lua ]] || exit 0`.

  The second half is new. Upstream adds `lualine-transparent.lua` to any
  config with a `lua/plugins` directory (`1791723398.sh:56-58`). On Arch
  that is safe, because owning `omarchy-nvim` means running its config.
  Here a user's own LazyVim config also has `lua/plugins`, and LazyVim
  loads every file there as a spec. `plugin/after/transparency.lua` exists
  only in Omarchy's config, which nixarchy seeds, so requiring it keeps the
  migration to seeded configs.

`pkgs/omarchy/user-migrations.nix` gets that `case` back, and its
`omarchy-nvim-config` argument. The script's own guards stay: it exits when
`~/.config/nvim` is absent, and preserves a symlinked file or parent.

### 3. Who it reaches

Only configs nixarchy seeded. Under `programs.nixarchy.neovim = "theme-only"`
(the default, `modules/home.nix:652-672`), the seed copies into an absent
`~/.config/nvim` only (`:464`). So a new seed gets the file from the package,
and a pre-4.5 seed gets it from the migration. A user's own config is untouched,
because it lacks Omarchy's `plugin/after/transparency.lua` (section 2's
guard). The migration also exits when `~/.config/nvim` is absent, and its
symlink guards and the seed's refusal stay. `off` stops the seed only, so
under `off` an older seeded config is still updated, which is the same
config `theme-only` would update.

### 4. Branch order

`pkgs/omarchy/user-migrations.nix`, the ledger's `run` field and the
harness exist only on `feat/1673-pre45-migrations` (the Pre-4.5 PR). This
branch stacks on it: the implementation merges `feat/1673-pre45-migrations`
in first, and rebases onto `main` once that merges. Section 1 alone would
not need it, but the row in section 2 does, and they land together.

## Alternatives rejected

- **Write the file by hand** from the migration's description. It has no
  upstream to follow, which the package header already warns about.
- **Vendor the whole 4.5 `omarchy-nvim` tree.** No gap has been reported in
  the other files (intent decision 2).
- **Keep the row declined.** Every nixarchy Neovim then lacks 4.5's
  lualine transparency.

## Risks

- **A binary repository can drop an old version.** If
  `pkgs.omarchy.org` stops serving `2026.9.21-5`, the fetch 404s and
  `omarchy-nvim-config` fails to build. That doesn't happen silently; it's
  a red build, and `checks.cache-entries`' repush only helps if the path was
  cached. The fallback is to vendor the extracted file into `./config`,
  citing this version and hash in the header.
- **33 MB fetched for a 1 KB file**, once per cold store. The output
  carries one file, so the closure does not grow.
- **The seeded config changes for new homes.** LazyVim reads every file
  under `lua/plugins` as a spec, which is the intended effect, and matches
  4.5 on Arch.

## Verification

- `nix build .#omarchy-nvim-config` (package tier) contains the file, and
  its first line matches the package's. §1: point the extraction at a
  wrong path and the build fails.
- `checks.user-migrations` (on the stacked branch): a `case_1672` fixture
  with a seeded `~/.config/nvim` lacking `lualine-transparent.lua` gets it.
  A second run changes nothing, and a symlinked `lua/plugins` is left alone.
  A user's own LazyVim config (a `lua/plugins` directory, no
  `plugin/after/transparency.lua`) stays byte-identical. That last case
  is the one the new guard exists for: with the guard removed, it fails.
  `oracle_run` with upstream's original, its `/usr/share/omarchy-nvim/config`
  pointed at the fixture's package directory, differs only by that path.
  §1: the row back to `declined` fails the case.
- `checks.user-migrations-ledger`, `bin-ledger`, fmt, statix, deadnix.
