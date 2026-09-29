---
status: draft
issue: 1058
spec: spec/2026-09-29-1058-grep-q-pipefail.md
---

# Plan: A check does not fail because grep found what it was looking for

## Approved decisions

- **Scope:** `tests/manifest-has-kind.nix` plus the `tests/AGENTS.md`
  lesson. The other `| grep -q` occurrences (about 99) go to a follow-up
  issue, unfixed here.
- **Fix:** replace
  `printf '%s\n' "$fn" | grep -q 'function manifestHasKind'` with
  `[[ $fn == *'function manifestHasKind'* ]]`. With no pipe, there is no
  writer to kill. The message, exit code and negative control are unchanged.
- **The lesson** is a new `tests/AGENTS.md` section before "The cheap ones,
  which is where new checks usually belong", with a `# Why:` pointer at the
  changed line. It covers:
  - the mechanism: pipefail, line-by-line writes, `grep -q` exiting early;
  - the evidence: 4 `write()`s, `PIPESTATUS=141 0`, and 0 failures in 8,000
    local runs;
  - the safe spellings: `[[ ]]`/`case`, `grep -q pat <<<"$x"`, grep on a
    file, `grep -c`;
  - when it applies: pipefail on and a producer writing after the match.
- **Rejected:**
  - a here string (a later edit back to a pipe looks harmless);
  - `grep -c` (keeps the trap's shape);
  - `set +o pipefail` (hides real failures);
  - a tree-wide lint (99 hits, mostly false positives);
  - retrying (§10).

## Steps

1. **`tests/manifest-has-kind.nix:63`**: the `[[ ]]` test, and a one-line
   `# Why: tests/AGENTS.md#…` above it.
   - Run `nix fmt`, then check `git diff --stat` (the formatter hook, §5).
   - Watch that no heredoc lands in the Nix string (§5, the nixfmt reindent).
2. **`tests/AGENTS.md`**: the new section, with an `<a id>` anchor matching
   the pointer.
3. **Baseline commit**, then the §1 loop. Every local build runs only when
   `gh run list` shows nothing in flight.
   - **a. Break:** change the awk extract's pattern to a name that does not
     exist. Confirm with `git diff`. Evaluate the drvPath, build it, and
     expect `FAIL: manifestHasKind not found`. Restore with
     `git checkout HEAD --`.
   - **b. Build as shipped**, and expect `control: … (bits 1)` and
     `manifestHasKind: all four cases correct`.
   - **c. The mechanism, shown outside the check.** The old spelling with a
     forced delay gives `PIPESTATUS=141 0`. Recorded in the PR, since the
     check itself cannot reproduce scheduler timing.
4. **Follow-up issue:** the other occurrences, grouped by file (the list
   from `grep -rnE '\|\s*grep -[a-zA-Z]*q'`), with the two questions per
   site. Milestone "Keeping the lights on"; labels `ci` and `bug`.
5. **PR:** use the template, "Closes #1058", link the three files and the
   follow-up issue. Merge when green and `mergeable`.

## Tests

- `nix fmt -- --ci`, `statix check .`, `deadnix --fail .`: clean.
- `nix build .#checks.x86_64-linux.manifest-has-kind`: green as shipped, red
  with the extract broken.
- CI: the `omarchy` job builds it on the PR.

## Rollback

Revert the squash commit. The check goes back to the racy spelling, which is
correct except under a SIGPIPE race.
