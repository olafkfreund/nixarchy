---
status: approved
issue: 1021
spec: spec/2026-09-27-1021-unchecked-derived-numbers.md
---

# Plan: guard every number `--fix` can write

Self-contained. The spec and intent do not need opening.

## Correction to the approved spec: three gaps, not seven

The spec's table said 7 of 37 quantities write more than they read. **That
count was wrong, and wrong in my favour.** The audit counted `[0-9]+` and
`[a-z]+` occurrences anywhere in the fix pattern's left-hand side, including
inside `(...)` groups — which are *preserved* through `\1`, not rewritten.

Re-run with those spans stripped:

| quantity | reads | writes | verdict |
|---|---|---|---|
| `pacman-scripts` | 1 | 2 | **covered** — `pacman-scripts-of` is its pair (#831's fix, working) |
| `apps-total` | 1 | 5 | **four unguarded** |
| `apps-untouched` | 1 | 2 | **one unguarded, proven** |
| `apps-indexed` | 1 | 2 | **one unguarded** |

`apps-nixpkgs-row` and `default-plugins-on` were false positives.
`default-plugins-on`'s fix is
`s/^([A-Z][a-z]+ ${dp})[a-z]+ are always on/\1…/` — the first `[a-z]+` sits
inside the group and survives; only one word is rewritten, and
`default-plugins-gated` checks the other.

**This is not a footnote, it is a design input.** The self-test in step 5 must
strip capture groups before counting, or it reproduces exactly the two false
positives above and gets switched off for crying wolf.

## The approved decisions, carried over

- **One quantity per number.** The file's own rule, stated at line 285 about
  #831, following the `pacman-scripts` / `pacman-scripts-of` template.
- **Guard both statements; do not delete one.** The four numbers appear twice
  in `other-packages.md`, as prose and as a table. Deleting the table would
  make the guard unnecessary and was rejected: the two serve different
  readers, and letting a check dictate the documentation is backwards.
- **`--fix` is untouched.** *"An auto-fixer that cannot refuse is worse than a
  check"* — nothing here makes it write more eagerly. It writes less blindly,
  because every number it rewrites becomes one `--check` can disagree about.
- **No derivation changes.** Only what is compared. If a new guard shows a
  computed value is wrong, that is a separate issue.
- **No workflow edit.** `checks.readme-counts` already exists and already runs.

## The demonstrated instance, for the PR

Before any change, in `README.md`:

    **57 of the 68 apps never touch this repo.**  ->  **57 of the 99 apps ...**
    $ .github/scripts/readme-counts.sh --check
    check exit=0

Unguarded, on a different line and a different quantity from the one that
started this issue. This is the break that must go red by the end.

## Steps

1. `.github/scripts/readme-counts.sh`: add `apps-untouched-of`, checking the
   second number of `**N of M apps never touch this repo.**` → verify by
   changing that number and watching `--check` name `apps-untouched-of`

2. Same file: add `apps-indexed-of` for the second number of its line →
   verify the same way

3. Same file: add `apps-row-nixpkgs`, `apps-row-modules`, `apps-row-ours` and
   `apps-row-unavailable`, each checking its own number in
   `| N apps in the selection | A from nixpkgs, B as NixOS modules, C built
   here, D with no equivalent |` → verify each individually; a pattern that
   matches the prose paragraph instead of the table passes for the wrong
   reason, so each break must name the quantity being tested and no other

4. Run `--check` on the unchanged tree: it must pass. Run `--fix` then
   `--check`: also pass, and `git diff` empty → verify no derivation moved

5. Same file: the self-test. For each quantity, count unescaped capture groups
   in the check pattern and count `[0-9]+`/`[a-z]+` in the fix pattern's LHS
   **with `(...)` spans stripped**; refuse when writes exceed reads and the
   quantity has no declared partner. `pacman-scripts` declares
   `pacman-scripts-of`. Keep it under ~20 lines; if it needs to be clever,
   abandon it and leave the table above as a comment → verify by step 6

6. Add a throwaway quantity that writes two and reads one with no partner,
   run the script, watch it refuse, remove it → the failing output goes in
   the PR

7. `nix build .#checks.x86_64-linux.readme-counts` → verify green

## Tests

`gh run list` before any build; p620 runs every runner.

```sh
.github/scripts/readme-counts.sh --check          # needs ./result
nix build .#checks.x86_64-linux.readme-counts --print-build-logs
nix run nixpkgs#shellcheck -- .github/scripts/readme-counts.sh
```

The script needs an omarchy tree at `./result` or `OMARCHY_TREE`; build it
once with `nix build .#omarchy --out-link result` and delete the link before
committing, because a stray `result` is untracked noise and `find` does not
follow it.

**Prove each guard fails first (§1).** Six breaks, one per new quantity, each
reverted with `git checkout HEAD -- <path>` and each proven to have landed
with `grep` before drawing a conclusion. Commit a known-good baseline before
starting the loop — the last time I skipped that step in this session I
destroyed uncommitted work with `git checkout HEAD --`.

| break | must fail with |
|---|---|
| `57 of the 68` → `57 of the 99` | `apps-untouched-of` |
| the second number of the indexed line | `apps-indexed-of` |
| `50 from nixpkgs` → `99 from nixpkgs` | `apps-row-nixpkgs`, and not `apps-other-nixpkgs` |
| `7 as NixOS modules` → `99` | `apps-row-modules` |
| `9 built here` → `99` | `apps-row-ours` |
| `2 with no equivalent` → `99` | `apps-row-unavailable` |
| a throwaway 2-write/1-read quantity with no partner | the self-test, naming it |
| removing `pacman-scripts`' partner declaration | the self-test, naming `pacman-scripts` |

The third row's "and not" matters: the prose paragraph states the same number,
so a loose anchor would make `apps-other-nixpkgs` fail instead and the new
guard would be untested while looking tested.

## Rollback

Every step is additive to one file. Revert the commit and the script returns
to comparing what it compared before; `--fix` behaviour is identical
throughout, so no document can have been written differently because of this.

No user-facing behaviour is involved at any point.
