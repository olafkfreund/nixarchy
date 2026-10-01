---
status: approved
issue: 1142
spec: spec/2026-10-01-1142-pacman-scripts-count.md
---

# Plan: the pacman-coupled script count measures upstream, not our comments

## Approved decisions, carried from the spec

- `pac` = the upstream scripts that mention pacman or yay
  (`grep -rlE '\b(pacman|yay)\b' "$omarchy_src/bin" | wc -l`, today 36).
- `up_scripts` = `find "$omarchy_src/bin" -maxdepth 1 -type f | wc -l`
  (today 444).
- Both reuse #1140's `omarchy_src`, with no second lookup. Both sit under the
  one existing `if [ -d "$omarchy_src/bin" ]`. A missing tree is a single
  `::error::` that names `pacman-scripts` and `pacman-replaced`, sets
  `fail=1`, and leaves the values empty so `quantity` refuses too.
- `pacman-scripts` and `pacman-scripts-of` use `$up_scripts`, not
  `$commands`. A comment at `pacman-scripts-of` says the 444/445 split is
  deliberate (#1142). `$commands` and its four other quantities are
  untouched.
- The README reads "Only **36 of 444 scripts** actually run". Nothing else
  in the sentence changes.
- Rejected: "36 of 445"; `ls | wc -l`; restoring "pacman" in #1139's
  comment.

Two files and three editing steps, so I implement it myself (model split).

## Steps

1. **`.github/scripts/readme-counts.sh`, the counts.** Delete the `pac=`
   line (199). In the existing `if [ -d "$omarchy_src/bin" ]` block, compute
   `pac` and `up_scripts` beside `repl_n`. In the `else` branch:
   - reword the error to name both counts;
   - set `pac=""` and `up_scripts=""`.

   The `pac` comment "mktemp, not a fixed /tmp name" stays with `tmp=`.

   → verify: `bash -n`, `shellcheck`.

2. **The same file, the quantities.**
   - In `pacman-scripts`'s sed, change `'"$commands"' scripts` to
     `'"$up_scripts"' scripts`.
   - Change `pacman-scripts-of`'s value and sed from `$commands` to
     `$up_scripts`.
   - Add the comment line about the deliberate split.

   → verify: Tests 1 and 2.

3. **`README.md`.** Change `**32 of 445 scripts**` to `**36 of 444 scripts**`.

   → verify: Test 1.

4. **Commit and PR.**
   - Commit with the subject "The README's pacman-coupled script count is
     read from upstream Omarchy, not from our replacements' comments".
   - In the PR, link the three artifacts, `Closes #1142`, and include the
     failing output.

5. **After merge.** Rebase #1139 in `wt-1130` onto main and push with
   `--force-with-lease`. Its `omarchy` job must pass.

## Tests

All cheap tier, as a bash script, under
`flock /mnt/data/vmtest/codex-build.lock`, with `OMARCHY_TREE` set to the
built `.#omarchy`. Stage everything first, and restore each break from the
index (`git show :README.md > README.md`).

1. `--check` exits 0, reporting `pacman-scripts: 36`,
   `pacman-scripts-of: 444` and `pacman-replaced: Nine`.
2. **Breaks**, each confirmed with `git diff` before it is read:
   - README "32 of 444": `--check` is non-zero, naming `pacman-scripts`.
   - README "36 of 445": `--check` is non-zero, naming `pacman-scripts-of`.
3. **Comment independence:** strip `pacman` and `yay` from the nine
   replacements in a copy of the built tree. `--check` exits 0.
4. **Refusal:** `OMARCHY_SRC_TREE=/nonexistent` exits non-zero, with one
   upstream-tree error naming both counts.

## Rollback

Revert the squash commit.
