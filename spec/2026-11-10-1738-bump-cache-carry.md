---
status: draft
issue: 1738
intent: intent/2026-11-10-1738-bump-cache-carry.md
---

# Spec: a nixpkgs bump that needs the cargo carry builds and caches without a hand push

## Measured first (open question 2)

A throwaway workflow on `probe/1738-lazy-trees` ran the same setup as CI
(`.github/actions/setup-nix`, `ubuntu-26.04`). Runs 42867448589 and
42868054654. The same commands also ran on p620 for contrast.

| | p620, Nix 2.34.9 | hosted runner, Determinate Nix 3.22.5 (Nix 2.35.2) |
|---|---|---|
| `nix config show` `lazy-trees` | off | **`true`** |
| `nix flake metadata --json .` → `.path` | `/nix/store/d22q3ll8…-source` | **`null`** (the key is absent) |
| `nix flake archive --json .` → `.path` | the flake source | `/nix/store/qqd53imw…-source` |
| derivations in `vm-toplevel`'s graph whose `inputs.srcs` holds that path | 2 (`activate`, the toplevel) | **2** |

So the cause is confirmed. Lazy trees leave `flake metadata` with no `path`,
and `cachix-push.sh:172` reads exactly that. On both Nixes, the source path
that `flake archive` returns is the one the built system takes as a source.
That rules out the case the intent feared, a materialized path nothing
references. The referrer-based exclusion stays valid; only the read has to
change.

Two things the probe found, for whoever repeats it:
- Derivation JSON (`version` 4 on both) nests derivations under
  `.derivations`, and gives sources as `.inputs.srcs` with store-path
  **basenames**. A test against full `/nix/store/…` strings matches nothing.
- `builtins.getFlake (toString ./.)` returns a third, different path. It is
  not the source the build used.

## Design

### 1. The exclusion set reads the source from `flake archive` (open question 2a)

In `.github/scripts/cachix-push.sh`, bump mode (line 172):

```bash
src=$(nix flake archive --json . 2>/dev/null | jq -r '.path // empty') || skip_all "could not archive the flake source"
```

This replaces `nix flake metadata --json . | jq -r .path`. It answers the
same on both Nixes, and it matches the path the build referenced (measured
above). Everything after it is unchanged: the `.#omarchy` tree root, the
referrers-closure, and the empty-set refusal.

### 2. A guard against an exclusion set that excludes nothing commit-specific

After the exclusion set is built, bump mode also refuses, through the
existing `skip_all` with its warning, when the set holds nothing but the
roots. The source is its own referrer, so a set of exactly `{src, tree}`
means no built path referenced them. That is the materialized-path failure
from the intent, and it must not turn into "push everything".

Then, per entry, before pushing: when the entry's own output references the
source (the toplevels do), it must appear in the exclusion set, and the
script refuses otherwise. This is the real-`nix` assertion the intent asks
for. It runs on CI's own runner, with CI's Nix, on every bump push. A
lazy-trees change that breaks the referrer relation then refuses loudly
instead of uploading commit-specific paths.

### 3. One job produces the carried packages (open question 1a)

A new job, `carry`, in `.github/workflows/build.yml`, on hosted
`ubuntu-26.04`. It **always runs, and never uses a job-level `if:`.** A
skipped job makes every job that `needs:` it skip too, and a skipped required
check passes the merge gate (#1144, CLAUDE.md §4).

- **The status**, with `pkgs/review.sh:519`'s own expression, which evaluates
  the carry against the flake's pinned nixpkgs:
  `nix eval --impure --json --expr "let p = (builtins.getFlake \"git+file://$PWD\").inputs.nixpkgs.legacyPackages.x86_64-linux; in (import $PWD/pkgs/cargo-system-libs.nix { inherit (p) lib; prev = p; }).status"`.
- **The names** are the keys whose value is `needed`. None means the step
  prints `no cargo carry is needed` and the job succeeds in under a minute.
  That is every `main` push and every ordinary PR.
- **For each needed name**, and for `codex-acp` when `codex` is needed
  (the carry carries it with codex), build the carried package as the
  machines get it, from the flake's own overlay:
  `(builtins.getFlake "git+file://$PWD").inputs.nixpkgs.legacyPackages.x86_64-linux.extend (builtins.getFlake "git+file://$PWD").overlays.default`.
  Then hand the output paths to `cachix-push.sh`.
- **The push** goes through `cachix-push.sh` unchanged in policy:
  - `closure_context` still decides. Only `main` and this repo's dated
    `update/nixpkgs-*` PRs push, so an ordinary PR builds and pushes nothing;
  - only packages `cargo-system-libs` marks `needed`, which are already in
    the allowlisted `vm-toplevel` closure (intent, Constraints);
  - unfree stays off, because the carried packages are codex, codex-acp and
    omp, all free.
- **Ordering:** `system-build`, `system-checks`, `system-session`, `omarchy`,
  `box` and the `options` matrix gain `needs: carry`, and run when it
  succeeds. A failed `carry` fails them through the jobs' existing `needs`
  handling. The `!cancelled()` jobs keep their own gate logic, so a failed
  carry is red, not skipped.
- **Cost on a non-bump run:** one hosted job of about a minute, evaluation
  only, before the others start.

### 4. Tests (`tests/cache-budget.nix`)

- The stub's `flake metadata` case is replaced by `flake archive`, returning
  `{"path":"/nix/store/src-flake"}`.
- A case with `"path":null` from `flake archive`: bump pushes nothing and
  warns.
- A case where the referrers-closure is only the roots: bump refuses, and
  warns that no built path referenced the source (design 2).
- A case where an entry references the source but is absent from the
  exclusion set: bump refuses that entry.
- The existing "a bump PR pushes the closure minus what references the
  source" case stays the positive control.

## Alternatives rejected

- **Turn lazy trees off in `setup-nix`** (`lazy-trees = false` in
  `extra-conf`). It fixes the read and changes every job's evaluation for one
  script's sake. It also hides the problem until a runner without that
  setting appears. Reading the path the way lazy trees supports is the
  smaller change.
- **Exclude by derivation** (intent 2b). Not needed: the measurement shows
  the referrer relation holds. Design 2's guard catches the day it stops
  holding.
- **Build the carried packages in `flake-update.yml`** (intent 1b). That
  pushes from a workflow that has not built the bump, and splits the bump's
  CI across two files.
- **A job-level `if:` on `carry`.** It skips dependents on every non-bump
  run (#1144).

## Risks

- **`flake archive` copies the flake source**, plus its inputs, into the
  store and prints them. On a runner with the inputs already fetched, that
  costs seconds. The output's `.path` is the top-level source; the inputs are
  under `.inputs`, which is ignored.
- **`needs: carry` serializes about a minute** in front of the heavy jobs on
  every run. That is accepted for a fix to a whole-pipeline timeout. A
  `carry` failure on a non-bump run, an evaluation error say, would block
  every PR. It is an evaluation `main` already does in the nightly
  (`review.sh`), so it fails only when `review.sh` would too.
- **The cache budget:** the carried closure is already counted by
  `cache-budget.sh` (it lies inside `vm-toplevel`), and pushing it early adds
  nothing to the budget.

## Verification

- **Cheap, locally:** `checks.cache-budget` with the new cases. §1 breaks:
  - restore the `flake metadata` read → the stub case returning only
    `flake archive` fails;
  - delete design 2's roots-only guard → the roots-only case fails;
  - delete the per-entry check → the unexcluded-entry case fails.
- **Hosted runner, with real Determinate Nix:** re-run the probe branch with
  `cachix-push.sh`'s exclusion computation alone, no push. It must report an
  exclusion set holding the toplevel. This is the real-`nix` measurement, on
  the environment CI uses, before the PR.
- **actionlint** on `build.yml`. Also confirm `checks.cache-budget` and the
  check-coverage guard still see every job.
- **On the PR itself**, an ordinary PR: `carry` prints `no cargo carry is
  needed`, and every job runs as before.
- **On the next dated bump PR:**
  - the run log shows `carry` building the needed packages once;
  - `pushing … left out as commit-specific` lines from `system-build`;
  - no job compiles codex;
  - no hand push.

  A bump with no carry needed shows `no cargo carry is needed` and the
  exclusion push lines.
- `install` is not affected. No self-hosted job gains `needs: carry`.
