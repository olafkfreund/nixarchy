---
status: approved
issue: 1142
intent: intent/2026-10-01-1142-pacman-scripts-count.md
---

# Spec: the pacman-coupled script count measures upstream, not our comments

## Design

This follows the approved intent: denominator choice **(a)**, wording
unchanged.

### `.github/scripts/readme-counts.sh`

1. **Both numbers from upstream.** Replace `pac=` (line 199) so that, when
   `[ -d "$omarchy_src/bin" ]`:
   - `pac` is `grep -rlE '\b(pacman|yay)\b' "$omarchy_src/bin" | wc -l`
     (today 36);
   - `up_scripts` is `find "$omarchy_src/bin" -maxdepth 1 -type f | wc -l`
     (today 444).

   Otherwise both are left empty and the script refuses once, with
   `::error::pacman-scripts: no upstream omarchy tree ... -- refusing` and
   `fail=1`. `quantity` then refuses on the empty values too. The existing
   `omarchy_src` from #1140 is reused, with no second lookup.

2. **Merge the two refusals.** #1140's `repl_n` block already tests the same
   directory. Fold both counts under the one `if [ -d "$omarchy_src/bin" ]`,
   so a missing tree produces one error naming both counts, not two
   near-identical ones.

3. **`pacman-scripts`'s sed** rewrites `**N of M scripts**` as
   `**$pac of $up_scripts scripts**` instead of `$pac of $commands`.

4. **`pacman-scripts-of`** compares and fixes against `$up_scripts` instead
   of `$commands`. Its comment gains one line: this number is upstream's
   script count, deliberately not `$commands`, the 445 commands we ship,
   which the other four sentences state (#1142). That keeps #831's "444 here,
   445 elsewhere" from being read as drift.

5. **`$commands`** and its four other quantities are untouched.

### `README.md`

"Only **32 of 445 scripts** actually run" becomes "Only **36 of 444
scripts** actually run". The rest of the sentence is unchanged.

## Alternatives rejected

- **(b) "36 of 445".** The two numbers would count different populations.
  The intent chose (a).
- **`ls | wc -l` for the denominator.** `find -type f` excludes any
  subdirectory, and it does not trip shellcheck SC2012.
- **Leaving `pac` on the built tree and putting "pacman" back in #1139's
  comment.** That satisfies the proxy, which #1140 already rejected.

## Risks

- **An Omarchy bump changes both numbers.** `omarchy.yml`'s `--fix`
  rewrites them, and that is the property moving, as intended.
- **The 444/445 split could be "fixed" back** by a later reader. The comment
  at `pacman-scripts-of` is the guard.
- **A missing upstream tree** turns `build` red with a named error, never
  green.
- No module, package or closure changes.

## Verification

All cheap tier, run under the lock, as a bash script (§1).

1. `--check` exits 0 on the branch, reporting `pacman-scripts: 36` and
   `pacman-scripts-of: 444`.
2. **The check fails:** with README set to "32 of 444", `--check` exits
   non-zero naming `pacman-scripts`. With "36 of 445", it names
   `pacman-scripts-of`. Restore from the index after each, and prove each
   break landed with `git diff`.
3. **Comments don't count:** strip `pacman` and `yay` from the nine
   replacements in a copy of the built tree. `pacman-scripts` and
   `pacman-replaced` are unchanged, and `--check` exits 0.
4. **Refusal:** `OMARCHY_SRC_TREE=/nonexistent` exits non-zero with one
   upstream-tree error, then `quantity`'s "computed as empty" refusals.
5. After merge, rebase #1139. Its `omarchy` job passes.
