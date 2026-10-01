---
status: approved
issue: 1140
spec: spec/2026-10-01-1140-pacman-replaced-count.md
---

# Plan: the replaced-pacman-scripts count measures upstream, not our comments

## Approved decisions, carried from the spec

- `repl_n` counts the nix-bin scripts whose **upstream** counterpart, in
  `inputs.omarchy`, calls pacman or yay. Our replacements' comments no
  longer count.
- The upstream tree comes from `OMARCHY_SRC_TREE`, or else from
  `nix flake archive --json --no-write-lock-file "$root"`. Archive once, and
  read `nix-skills` from the same JSON.
- A missing upstream tree is a loud refusal: `::error::`, `fail=1`, and an
  empty `repl_word`, so `quantity` refuses too. Never a silent zero.
- `pac` ("32 of 445") is unchanged.
- The README sentence becomes "Nine of those are replaced outright, in
  `pkgs/omarchy/nix-bin/`: package management, the update check, migrations
  and the default agent." `Nine` is already in the vocabulary.
- Rejected: restoring "pacman" in a comment, writing "Five", and deriving
  the count from the bin-ledger.

Two files and three editing steps, so per the model split I implement this
myself; no coder handoff.

## Steps

1. **`.github/scripts/readme-counts.sh`, the archive and the upstream
   tree.** Just before `pac=` (around line 191):
   - When `OMARCHY_SRC_TREE` or `NIX_SKILLS_TREE` is unset, run
     `nix flake archive` once into a variable (`archive_json`).
   - Set
     `omarchy_src=${OMARCHY_SRC_TREE:-$(jq -r '.inputs.omarchy.path // empty' <<<"$archive_json")}`.
   - Change the later `nix_skills_tree` block to read `.inputs["nix-skills"]`
     from `archive_json` instead of archiving a second time. Keep its
     existing comment.

   → verify: `bash -n`, and `shellcheck` on the script.

2. **The same file, the `repl_n` grep.** Grep `"$omarchy_src/bin"` instead of
   `"$omarchy/share/omarchy/bin"` for `$tmp/pac`. Add the two-line note on
   why the source is upstream. If `[ -d "$omarchy_src/bin" ]` fails:
   - emit `::error::pacman-replaced: no upstream omarchy tree at '<path>' -- refusing`;
   - set `fail=1` and `repl_n=""`.

   Make `word_for ""` return empty, which it already does via `*)`, so the
   `quantity` guard refuses too.

   → verify: Tests 3 and 4.

3. **`README.md`.** Replace the sentence exactly as decided above.

   → verify: Tests 1 and 2.

4. **Commit and PR.**
   - Commit with the subject "The README's replaced-pacman count is read
     from upstream Omarchy, not from our replacements' comments".
   - In the PR, link intent, spec and plan, `Closes #1140`, and include the
     failing output from Tests 2 and 4.

5. **After merge.** Rebase #1139 (`fix/1130-update-indicator`) onto main and
   push. Its `omarchy` job must pass with no change to its comment.

## Tests

All are cheap tier, one at a time under
`flock /mnt/data/vmtest/codex-build.lock`, in a bash script (§1).

`OMARCHY_TREE` is the built package
(`nix build .#omarchy --out-link result`), which the script needs for its
other counts.

1. `readme-counts.sh --check` exits 0 on the branch.
2. **Break:** sed README "Nine of those" to "Six of those", then `git diff`
   to prove it landed. `--check` must exit non-zero, naming
   `pacman-replaced`. Restore with `git checkout HEAD -- README.md`.
3. **Comment independence:** copy the built tree to a temp dir, strip
   `pacman` from its `share/omarchy/bin/omarchy-{pkg-*,update-available,default-agent,migrate}`,
   and grep to prove it is gone. Then
   `OMARCHY_TREE=<copy> --check` must still exit 0 for `pacman-replaced`.
   The `pac` count may move, since it still reads the built tree by design.
   Judge only `pacman-replaced`'s line.
4. **Refusal:** `OMARCHY_SRC_TREE=/nonexistent --check` must exit non-zero
   with the `pacman-replaced` refusal.
5. `nix fmt -- --ci`, `statix` and `deadnix` stay clean. No `.nix` file is
   touched.

## Rollback

Revert the squash commit. README goes back to "Six" and the script back to
the built-tree grep. #1139 then needs another route to green.
