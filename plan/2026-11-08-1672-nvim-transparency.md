---
status: approved
issue: 1672
spec: spec/2026-11-08-1672-nvim-transparency.md
coders:
  2: codex  # the header provenance and one vendored file, exactly as extracted
  3: codex  # an edited-copy case with a two-condition guard whose either half must fail alone
  4: codex  # harness fixtures that must each fail with one guard removed
reviewers:
  - codex  # a guard that decides whose editor config gets a new file
  - agy    # an independent read of the same diff
---

# Plan: seeded Neovim configs get Omarchy 4.5's transparency files

## Decisions carried from the approved spec

1. **Vendor the file, not fetchurl (owner).** `lua/plugins/lualine-transparent.lua`
   is extracted once from `omarchy-nvim-2026.9.21-5-any.pkg.tar.zst`
   (Omarchy's pacman repository, `https://pkgs.omarchy.org/stable/x86_64/`,
   sha256 `b46d41973cacfcf2d8be371351336a3f689e2eb7b9bacdb7ca81939354cbcbc9`
   per its `omarchy.db`, MIT) and committed into
   `pkgs/omarchy-nvim/config/lua/plugins/`. The URL, version, archive sha256
   and in-archive path go in `pkgs/omarchy-nvim/default.nix`'s header. There
   is no fetch at build time. The derivation is unchanged (`src = ./config`).
   Only that one file is vendored.
2. **Under `neovim = "off"`, nothing is touched (owner).**
3. **Row `1791723398`** moves from `declined` to `ported`, `run = "edited"`,
   with two edits to the copy:
   - `/usr/share/omarchy-nvim/config` becomes `${omarchy-nvim-config}/share/omarchy-nvim`;
   - `omarchy-pkg-present omarchy-nvim || exit 0` becomes a guard that
     requires **both** `[[ ${NIXARCHY_NEOVIM:-} != off ]]` (the
     `user-migrations` hook exports `NIXARCHY_NEOVIM=${cfg.neovim}`) **and**
     `~/.config/nvim/plugin/after/transparency.lua` with a sha256 among the
     three the script treats as "as Omarchy shipped it"
     (`1791723398.sh:44-52`; nixarchy's seed is `bd833dc0…`).
4. **Claim, narrowed:** the migration reaches configs that carry Omarchy's
   unmodified `transparency.lua`, which is every nixarchy seed and any hand
   copy of Omarchy's config. A user's own LazyVim config, or an edited
   `transparency.lua`, is left alone. The seed writes no marker of its own
   (`modules/home.nix:464-470`).
5. **What arrives:** every nixarchy seed has had `transparency.lua`
   (`bd833dc0…`) since d753f840 (#56), and never `lualine-transparent.lua`.
   So a seed gets one new file, plus a byte-identical rewrite of
   `transparency.lua` (the package carries the same v3.0.2 file).
6. **Branch order:** `pkgs/omarchy/user-migrations.nix`, the ledger's `run`
   field and the harness live on `feat/1673-pre45-migrations` (#1692). This
   branch merges that one, or `main` once #1692 has merged, before step 3.
   Never a rebase of a pushed branch.

## Steps

1. **Download and confirm** (session, before any edit). In the scratchpad,
   with nothing run from the download directory:
   `curl -fsSL -o $S/omarchy-nvim.pkg.tar.zst https://pkgs.omarchy.org/stable/x86_64/omarchy-nvim-2026.9.21-5-any.pkg.tar.zst`.
   `sha256sum` must equal decision 1's hash; stop if it does not. List the
   contents with `tar --zstd -tf` and confirm the path of
   `lualine-transparent.lua`. The migration expects it under
   `usr/share/omarchy-nvim/config/lua/plugins/`. Extract that one file to
   the scratchpad, and record its sha256 and its first line for step 2.
   Stop and report if the path differs from what the migration reads.
   Traps: never run anything from the extracted tree; this is data only.

2. **Vendor** (Codex): copy the extracted file to
   `pkgs/omarchy-nvim/config/lua/plugins/lualine-transparent.lua`,
   byte-identical (its sha256 must match step 1's). Add a header paragraph
   to `pkgs/omarchy-nvim/default.nix` naming the URL, version, archive
   sha256, in-archive path and the date it was taken, and why this one file
   comes from the binary package. Extend `meta.description` to note it.
   Verify: `sha256sum` of the vendored file against step 1;
   `nix build .#omarchy-nvim-config` (package tier) contains it.
   Traps: §5, a flake sees only tracked files, so `git add` before
   building. Keep the header in the file's register, as plain explanation.

3. **Stack, then the row** (session merges, Codex edits): `git merge
   origin/feat/1673-pre45-migrations` (or `origin/main` once #1692 has
   merged), and resolve any conflict by keeping both sides. Then:
   - `data/user-migrations.nix` row `1791723398`: `decision = "ported"`,
     `run = "edited"`, with a real reason ending in `(#1672)`;
   - `pkgs/omarchy/user-migrations.nix`: re-add the `omarchy-nvim-config`
     argument, and a `1791723398)` case with decision 3's two
     `--replace-fail` edits. The second replaces the
     `omarchy-pkg-present omarchy-nvim || exit 0` line with the two-condition
     guard, the hash list copied from the script's own `case`;
   - `modules/home.nix`, the `post-boot.d/user-migrations` hook: add
     `export NIXARCHY_NEOVIM=${cfg.neovim}`.

   Verify: `nix build .#omarchy.userMigrations`, then read its
   `scripts/1791723398.sh`: both edits are present, and no
   `omarchy-pkg-present` is left.
   Traps: `--replace-fail` fails the build on a reworded upstream line,
   which is wanted. A guard written with `$(sha256sum ...)` inside `[[ ]]`
   under `set -e` must not abort on a missing file, so test `-f` first.

4. **Fixtures** (Codex): `case_1672` in `tests/user-migrations/run`, per the
   spec's verification list: a seeded config gets the file and a second run
   changes nothing; `NIXARCHY_NEOVIM=off` leaves it byte-identical; a user's
   own LazyVim config is byte-identical; an edited `transparency.lua` is
   byte-identical; a symlinked `lua/plugins` is left alone; `oracle_run`
   matches on the seeded fixture.
   Verify: `checks.user-migrations` passes. §1, three breaks, one at a
   time:
   - drop the `off` condition: the `off` case fails;
   - drop the hash condition: the own-config case fails;
   - set the row back to `declined`: the seeded case fails.

   Capture each.
   Traps: `same_tree` compares hashes and link targets, so a fixture needs a
   real symlink (§1, "a content test is not an ownership test").

5. **Run, commit, PR** (session): cheap tier (`user-migrations`,
   `user-migrations-ledger`, `bin-ledger`, `grep-q-pipefail`, fmt, statix,
   deadnix), package tier (`omarchy-nvim-config`, `omarchy.userMigrations`),
   VM tier (`plugin`, which runs the runner against the real shell).

## Tests (by §6 tier)

| tier | check | expect |
|---|---|---|
| cheap | `user-migrations`, `user-migrations-ledger`, `bin-ledger`, `grep-q-pipefail`, fmt, statix, deadnix | pass; three §1 breaks fail |
| package | `omarchy-nvim-config`, `omarchy.userMigrations` | the file is vendored; the edited copy carries both guards |
| VM | `plugin` | pass |

## Rollback

Revert the merge commit. A config the migration already updated keeps
`lualine-transparent.lua`. LazyVim loads it as one more spec, which the
user can delete. The marker stops it from coming back.

## PR notes

`Closes #1672`. The body links the intent, the spec and this plan, names
the archive and its hash, says which steps Codex did, and carries the
three §1 outputs. Comment "@codex review". Merge with a merge commit
(`--merge`). While #1692 is open, the PR's base is
`feat/1673-pre45-migrations`; it moves to `main` once #1692 merges.

## Deviations (Codex plan review and step 1, 2026-11-08)

1. **Step 1 passed.** The archive sha256 is `b46d4197...cbcbc9`, matching `omarchy.db`, and the file is at
   `usr/share/omarchy-nvim/config/lua/plugins/lualine-transparent.lua`
   (sha256 `d59f78b5...75bcb7`, 21 lines). **Found:** the package's
   `plugin/after/transparency.lua` is `2f4ab7aa...`, not our seed's
   `bd833dc0...`. The migration replaces an unmodified copy (`bd833dc0`
   is on its list), so upstream gives a seeded config both files. Whether
   to vendor the newer `transparency.lua` too is the owner's call: it
   changes decision 1's "only that one file".
2. **Step 3's verification** also asserts the built hook exports
   `NIXARCHY_NEOVIM`, and that the ledger row reads `ported`/`edited` (jq
   on the ledger JSON), so a missed edit fails.
3. **Step 4's fixture** is the vendored seed minus the new file, and asserts
   `transparency.lua` is byte-identical afterwards unless the owner chooses
   to vendor the new one (then it must equal the new one).
4. **Merge conflicts are resolved by reading both sides**, not by "keep
   both". A duplicated ledger row or runner entry is a bug.
