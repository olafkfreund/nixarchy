---
status: draft
issue: 1719
spec: spec/2026-11-09-1719-commit-independent-shallow.md
coders:
  1: codex  # one refusal branch whose every edge (worktree, unknown answer, capture) matters
  2: coder  # a runCommand check in tests/nightly-digest.nix's shape, plus one flake entry
  3: coder  # two lines of YAML
reviewers:
  - codex  # line by line against this plan
  - agy    # an independent read of the diff
---

# Plan: the commit-independence guard can run on a hosted checkout

## Decisions carried from the approved intent and spec

1. **Full history in the nightly job.** In `.github/workflows/nightly.yml`,
   the `commit-independent` job's checkout (`:587`) becomes:

   ```yaml
         - uses: actions/checkout@v5
           with:
             # Why: .github/scripts/commit-independent.sh refuses a shallow clone (#1719).
             fetch-depth: 0
   ```

   Nothing else in the workflow changes: not the trigger, the timeout, the
   runner, or the `needs` lists of `digest` (`:602`) and `report` (`:632`).
   This is a CI-gate edit (§11), and the owner approved it in the intent.
2. **The script refuses a shallow tree.** In
   `.github/scripts/commit-independent.sh`, directly after the dirty-tree
   refusal (`:5-9`) and before `scratch_root=` (`:11`):

   ```bash
   shallow=$(git rev-parse --is-shallow-repository) || exit 1
   if [ "$shallow" != false ]; then
     echo 'commit-independent: shallow clone; fetch full history (actions/checkout fetch-depth: 0)' >&2
     exit 2
   fi
   ```

   - `git rev-parse --is-shallow-repository`, never `[ -f .git/shallow ]`,
     which always passes in a linked worktree.
   - `!= false`: anything but `false` refuses.
   - Exit 2 is "this tree cannot be measured", as for a dirty tree.
   - Captured, then tested (CLAUDE.md §5: `set -e` does not reach `$(...)`).
3. **`checks.commit-independent-shallow`** (`tests/commit-independent-shallow.nix`).
   It is a `runCommand` with `bash`, `git` and `coreutils`, and a stub `nix`
   on `PATH` that writes a marker file and exits 1.
   - **Case 1, shallow clone:** a two-commit fixture repository, then
     `git clone --depth 1 file://…`. Run the script there. Expect exit 2,
     `shallow clone` on stderr, and no marker.
   - **Case 2, a worktree of the shallow clone:** `git -C <clone> worktree
     add --detach <dir>`. Run the script from `<dir>`. Expect the same.
   - **Case 3, full clone:** `git clone file://…`. Expect exit 1, the marker
     present, and no `shallow clone` on stderr.
   - **Traps:**
     - Run the script as `bash ${../.github/scripts/commit-independent.sh}`;
       the sandbox has no `/usr/bin/env`.
     - Set `RUNNER_TEMP` per case to a fresh directory under `$TMPDIR`.
     - The marker file, `RUNNER_TEMP` and case 2's worktree all sit
       outside every tested repository, so "dirty tree" (also exit 2)
       cannot answer for "shallow clone".
     - Set git identity with `-c` or `GIT_AUTHOR_*` and `GIT_COMMITTER_*`,
       and `HOME=$TMPDIR`.
     - No `${` inside the Nix `''` string except interpolation, and no
       Python-style `''` (CLAUDE.md §5).
   - Registered in `flake.nix` beside the other script checks (for example
     after `nightly-digest`, `:2473`), with a one-line comment
     `# See tests/commit-independent-shallow.nix.` `generated-checks.sh`
     runs it on pull requests with no workflow edit (§4).

## Steps

1. **`.github/scripts/commit-independent.sh`**: decision 2 (Codex).
   - Verify: `bash -n .github/scripts/commit-independent.sh`; then, by hand,
     `git clone -q --depth 1 file://$PWD /mnt/data/vmtest/shallow1719` and
     run the script there: exit 2 with the message. Remove the clone with
     `rm -rf -- /mnt/data/vmtest/shallow1719` (a literal path).
   - Traps: no other line moves; the message is exactly the one in decision
     2, because step 2 matches it.
2. **`tests/commit-independent-shallow.nix`** and its `flake.nix` entry:
   decision 3 (coder).
   - Verify: `git add` the new file (§5: an untracked file "does not
     exist"), then, under `flock /mnt/data/vmtest/codex-build.lock`, build
     `.#checks.x86_64-linux.commit-independent-shallow`.
   - Traps: those listed in decision 3; `nix fmt` then
     `git diff --stat` (§5: a hook may reformat with `nixpkgs-fmt`).
3. **`.github/workflows/nightly.yml`**: decision 1 (coder).
   - Verify: `nix run nixpkgs#actionlint -- .github/workflows/nightly.yml`
     and `git diff` shows only those lines.
4. **Run, break, commit, PR** (session).
   - Cheap tier: `commit-independent-shallow`, `grep-q-pipefail`,
     `test-registration`, `nix fmt -- --ci`, statix, deadnix, actionlint.
   - §1 breaks, each shown failing:
     1. delete the refusal → cases 1 and 2 fail (the marker appears);
     2. replace it with `[ -f .git/shallow ]` → case 2 fails, case 1
        passes;
     3. invert it to refuse on `false` → case 3 fails.
   - The real script on this checkout: `commit-independent.sh <one cheap
     check>` prints `1 checks, none moved` (no refusal on a full clone).
   - One commit per step. The PR says `Closes #1719`, links the three
     artifacts, and says Determinate Nix's refusal cannot be reproduced here
     (local nix 2.34.9 accepts a shallow tree), so the next nightly is that
     proof. Then "@codex review". Merge commit.

## Tests

| check | tier | expect |
|---|---|---|
| `commit-independent-shallow` | cheap | passes; breaks 1-3 fail it |
| `grep-q-pipefail`, `test-registration` | cheap | pass |
| actionlint on `nightly.yml` | cheap | passes |
| the script on a `--depth 1` clone | cheap | exit 2 and the message |
| the script on this checkout, one check | cheap | `1 checks, none moved` |

Not run locally: Determinate Nix. The next nightly's `commit-independent`
job is the proof.

## Rollback

Revert the PR. The job goes back to a shallow checkout and fails as it did
on 2026-11-09.
