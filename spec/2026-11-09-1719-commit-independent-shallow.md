---
status: draft
issue: 1719
intent: intent/2026-11-09-1719-commit-independent-shallow.md
---

# Spec: the commit-independence guard can run on a hosted checkout

## Design

Two changes and one check, all from the approved intent's answers.

### 1. The nightly job checks out full history

`.github/workflows/nightly.yml`, job `commit-independent` (`:587`):

```yaml
      - uses: actions/checkout@v5
        with:
          # Why: .github/scripts/commit-independent.sh refuses a shallow clone (#1719).
          fetch-depth: 0
```

- The tree the guard evaluates is then a user's full clone. `revCount`
  exists and moves with the probe commit, so a check that read
  `self.revCount` would be named as moved rather than slip through.
- `release.yml`, `weekly.yml` and `omarchy-edge.yml` already check out with
  `fetch-depth: 0`. The cost is a full-history fetch on a hosted runner,
  for a job with a 90-minute budget whose evaluation is the expensive part.
- The trigger, timeout and runner stay the same, and so do the `needs` lists
  of `digest` and `report` (§11).

### 2. The script refuses a shallow tree itself

`.github/scripts/commit-independent.sh`, directly after the dirty-tree
refusal (`:5-9`) and before `git worktree add` (`:18`):

```bash
shallow=$(git rev-parse --is-shallow-repository) || exit 1
if [ "$shallow" != false ]; then
  echo 'commit-independent: shallow clone; fetch full history (actions/checkout fetch-depth: 0)' >&2
  exit 2
fi
```

- `git rev-parse --is-shallow-repository`, not `[ -f .git/shallow ]`: in a
  linked worktree `.git` is a file, and the `shallow` file is in the common
  git directory. The script makes such a worktree and is often run from one.
- `!= false`, not `= true`: an answer that is neither (an older git, a
  changed format) refuses rather than proceeds.
- Exit 2 is the script's existing code for "this tree cannot be measured",
  as the dirty-tree refusal uses. Exit 1 stays "a check moved" or a failure.
- Captured first, then tested (§4, `mapfile` and `$(...)` lessons): a failed
  `rev-parse` exits 1 rather than reading as "not shallow".

### 3. A check for the refusal

`tests/commit-independent-shallow.nix`, registered as
`checks.commit-independent-shallow` in `flake.nix`. `generated-checks.sh`
then runs it on every pull request with no workflow edit (§4).

It is a `runCommand` with `git` and `bash`, and a stub `nix` that fails
loudly if it is ever called:

- **Case 1, shallow:** make a repository with two commits, `git clone
  --depth 1 file://…` it, and run the script there. Expect exit 2 and the
  message `shallow clone`, with the stub `nix` never called.
- **Case 2, a shallow repo's worktree:** run it from a `git worktree add` of
  the shallow clone. Expect the same refusal. This is the case
  `[ -f .git/shallow ]` would miss.
- **Case 3, full clone:** run it on a full clone. The refusal must not fire.
  Expect the stub `nix` to be reached (a marker file it writes), proving the
  script got past the check.

Each case sets `RUNNER_TEMP` to a directory under the build's `$TMPDIR`. The
script's default, `/mnt/data/vmtest`, does not exist in a sandbox, and the
script would refuse on that first.

The stub `nix` keeps the check hermetic. The sandbox has no nix daemon, and
the cases only ask whether the script reaches nix.

## Alternatives rejected

- **`?shallow=1` in the script's URLs.** It makes the hosted run pass on a
  tree with no `revCount`, which is not a user's tree (the intent's
  constraint). The owner approved `fetch-depth: 0`.
- **Copying `release.yml`'s `[ -f .git/shallow ]`.** It always passes in a
  worktree (above).
- **A separate workflow step for the refusal, as `release.yml` has.** The
  script also runs locally, where local nix accepts a shallow tree, so the
  refusal belongs where every caller passes.
- **Running the whole guard in the check.** It evaluates every check in the
  flake, which a sandbox cannot do, and that is the 66-minute nightly job's
  work anyway.

## Risks

- **A full-history fetch is slower.** It is seconds to minutes against a
  90-minute budget, and the first hosted run will report it. The job is
  hosted, so no install slot or p620 load is involved.
- **The guard may then find a real moved proof.** That is its purpose. A
  red `commit-independent` after this lands is a finding to read, not a
  regression of this change.
- **Determinate Nix might refuse something else** once the tree is full.
  The first hosted run after merge answers that. It cannot be reproduced
  locally (below).

## Verification

- `checks.commit-independent-shallow` passes. §1 breaks, each shown failing:
  1. delete the refusal → cases 1 and 2 fail (the stub `nix` is reached);
  2. replace it with `[ -f .git/shallow ]` → case 2 fails, case 1 passes;
  3. invert it to `= true` refusing on `false` → case 3 fails.
- The real script refuses a `git clone --depth 1` of this repository with
  exit 2 and the message (the intent's local proof), and on the full
  checkout it proceeds as before: `commit-independent.sh <one cheap check>`
  reports `1 checks, none moved`.
- `nix fmt -- --ci`, statix, deadnix, `checks.grep-q-pipefail`,
  `checks.test-registration`, and actionlint on `nightly.yml`.
- Not reproducible locally: Determinate Nix's own refusal (local nix 2.34.9
  accepts the shallow tree). The next nightly's `commit-independent` job is
  that proof, and the PR says so.
