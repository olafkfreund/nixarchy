---
status: approved
issue: 1140
intent: intent/2026-10-01-1140-pacman-replaced-count.md
---

# Spec: the replaced-pacman-scripts count measures upstream, not our comments

## Design

There are two edits.

### `.github/scripts/readme-counts.sh`

1. **Resolve the upstream tree.** Next to the existing `NIX_SKILLS_TREE`
   lookup, resolve an upstream tree the same way:
   `OMARCHY_SRC_TREE` if it is set, otherwise
   `nix flake archive --json --no-write-lock-file "$root" | jq -r '.inputs.omarchy.path // empty'`.
   This is the command §5 names for an input's path. The script already runs
   it once for `nix-skills`. Archive once and read both inputs from the same
   JSON, rather than paying for a second archive.

2. **Count from upstream.** `repl_n` greps `"$upstream/bin"` instead of
   `"$omarchy/share/omarchy/bin"`. The intersection with
   `pkgs/omarchy/nix-bin/` is unchanged. The count becomes: nix-bin scripts
   whose upstream counterpart calls pacman or yay.

3. **Refuse loudly.** If the upstream tree is empty, or has no `bin/`, emit
   `::error::pacman-replaced: no upstream omarchy tree -- refusing`, set
   `fail=1`, and leave `repl_word` empty. The existing `quantity` guard then
   refuses too ("computed as empty"). That is §4's rule: never a silent zero.

4. **`pac` stays as it is.** It still reads the built tree; the approved
   intent's open question 1 left it out of this change.

5. Add a two-line comment at the `repl_n` line. It says the grep reads
   upstream because the built tree holds our replacements, whose comments
   are not evidence (§7: a note at the line it protects).

### `README.md`

"Six of those are replaced outright, in `pkgs/omarchy/nix-bin/`: the ones
the menus drive." becomes "Nine of those are replaced outright, in
`pkgs/omarchy/nix-bin/`: package management, the update check, migrations and
the default agent." That follows intent open question 2: the description is
true of all nine. `Nine` is already in `word_for` and in the `pacman-replaced`
alternation, so the script needs no new vocabulary (§4, "teach it the new
word").

## Alternatives rejected

- **Put "pacman" back in the `omarchy-update-available` comment.** It turns
  #1139 green by satisfying the proxy, and leaves the trap armed for the next
  comment edit.
- **README says "Five" via `--fix`.** False: the script is still replaced.
- **Derive "replaced" from `data/bin-ledger.nix` rows with
  `class = "replace"`.** The ledger records what we did, not whether upstream
  touched pacman. It answers a different question and would need its own
  filter on the reason text, which is a second proxy.
- **Also move `pac` to upstream (36 of 444).** That is deferred under intent
  open question 1, and filed as a follow-up only if the owner asks.

## Risks

- **`flake archive` in CI.** It already runs in the same step for
  `nix-skills`, so it adds no new network or permission dependency. If it
  fails, both counts refuse, which is red, not green.
- **An Omarchy bump that changes which upstream scripts call pacman.** The
  count moves, and `omarchy.yml`'s `--fix` rewrites the word. That is the
  intended behaviour; it is the property, not a comment, changing.
- **An upstream count above twelve or below six** falls outside the
  alternation. The script refuses ("nothing matches its pattern"). That is
  §4's fail-closed case, visible and fixed by widening the alternation.
- No module, package, closure or installed machine changes. Nothing for the
  install or VM checks to see.

## Verification

All cheap, run under the build lock (owner tiers):

1. Build the omarchy tree (`nix build .#omarchy --out-link result`). Then
   `readme-counts.sh --check` passes on the branch, with README saying
   "Nine".
2. **The check fails (§1):** set README back to "Six" and `--check` fails,
   naming `pacman-replaced`. Restore it with `git checkout HEAD -- README.md`.
3. **The comment no longer counts:** delete the word "pacman" from every
   comment in `pkgs/omarchy/nix-bin/*`, rebuild the tree, and `--check` still
   says Nine. Restore with `git checkout HEAD --`. Prove each break landed with
   `git diff` before reading the result (§1).
4. **The refusal fires:** `OMARCHY_SRC_TREE=/nonexistent` makes `--check`
   exit non-zero with the `pacman-replaced` refusal.
5. After merge, rebase #1139 onto main. Its `omarchy` job passes without any
   edit to its comment.

The failing output from 2 and 4 goes in the PR.
