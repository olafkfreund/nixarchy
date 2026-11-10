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

### 2. Known commit-specific entries must be excluded (revised after review)

The first draft had two guards: a "roots only" refusal, and "an entry that
references the source must be excluded". Review found both wrong.

- **The roots-only refusal would break design 3's job.** That job builds
  standalone packages, and none of them references the source. Its
  exclusion set is legitimately just the roots.
- **The per-entry rule is a tautology on real `nix`.** Forward references
  and `--referrers-closure` read the same table, so it can never fail. And
  when the source path is the wrong one, its condition is false, so it stays
  silent on exactly the bug it was for.

So the guard asserts a fact that does not depend on the source path being
right. **An entry known to be commit-specific must be in the exclusion set.**

- `vm-toplevel` and `reference-toplevel` are commit-specific by
  construction: they embed the flake revision (`etc-nixarchy-version`,
  `installer/cd.nix`'s `inputSources`).
- `cachix-push.sh` takes those attribute names in a `commit_specific` list,
  defined beside the `system` group in `cache-allowlist.sh`, so a new
  toplevel lands in one place.
- In bump mode, for each such entry, its output path must be a line of the
  exclusion file (`grep -qxF`, a whole-line match), or the script refuses
  with `skip_all`.
- If the archived source is not what the build referenced, the toplevel is
  not among its referrers, so the guard fires. That is the lazy-trees
  failure, and this guard can fail on it.
- Entries not on the list, such as the carried packages, get no such
  requirement, so design 3's push is untouched.

The existing empty-set refusal stays as it is.

### 3. One job produces the carried packages (open question 1a)

A new job, `carry`, in `.github/workflows/build.yml`, on hosted
`ubuntu-26.04`. It **always runs, and never uses a job-level `if:`.** A
skipped job makes every job that `needs:` it skip too, and a skipped required
check passes the merge gate (#1144, CLAUDE.md §4).

- **When it does work:** whenever the carry is `needed` for the pin being
  tested. Since #1741 merged, that includes `main` and every ordinary PR,
  until nixpkgs ships the fix. The first draft said no carry was needed
  there; review showed that was false. On those refs it still builds, and
  `closure_context` decides the push: `main` pushes, so ordinary PRs then
  substitute from the cache instead of compiling; an ordinary PR never pushes.
- **The status**, with `pkgs/review.sh:519`'s own expression, which evaluates
  the carry against the flake's pinned nixpkgs:
  `nix eval --impure --json --expr "let p = (builtins.getFlake \"git+file://$PWD\").inputs.nixpkgs.legacyPackages.x86_64-linux; in (import $PWD/pkgs/cargo-system-libs.nix { inherit (p) lib; prev = p; }).status"`.
- **The names** are the keys whose value is `needed`. None means the step
  prints `no cargo carry is needed` and the job succeeds in under a minute.
- **For each needed name**, plus every other key the carry's `packages`
  returns for that pin (it adds `codex-acp` only when `prev ? codex-acp`, so
  this follows the helper and assumes nothing), build the carried package as the
  machines get it, from the flake's own overlay:
  `(builtins.getFlake "git+file://$PWD").inputs.nixpkgs.legacyPackages.x86_64-linux.extend (builtins.getFlake "git+file://$PWD").overlays.default`.
  Then hand the output paths to `cachix-push.sh`.
- **The push** goes through `cachix-push.sh` unchanged in policy:
  - `closure_context` still decides. Only `main` and this repo's dated
    `update/nixpkgs-*` PRs push, so an ordinary PR builds and pushes nothing;
  - only packages `cargo-system-libs` marks `needed`. That they lie inside
    the allowlisted `vm-toplevel` closure is **checked, not assumed**: before
    pushing, the job asserts that each carried output's `.drv` appears in
    `vm-toplevel`'s derivation graph (`nix derivation show -r` on its
    `drvPath`, matching the basename). That is evaluation only, no build. A
    package built through a different package set would not match, and the
    job refuses to push it;
  - unfree stays off, because the carried packages are codex, codex-acp and
    omp, all free.
- **Ordering and failure:** `system-build`, `system-checks`,
  `system-session`, `omarchy`, `box` and the `options` matrix add `carry`
  to their existing `needs` (`gate` stays).
  - A failed dependency normally **skips** a job, and the jobs under
    `if: !cancelled()` would instead run on. Neither is the wanted outcome.
  - So each of those jobs' existing first step, the gate-result check that
    already fails when `gate` did not succeed (#1134), also fails when
    `needs.carry.result != 'success'`, naming carry.
  - A plain job (no `!cancelled()`) with `needs: carry` is skipped by
    GitHub on a carry failure, and a skipped required check passes the merge
    gate (#1144). Every job given `needs: carry` therefore gets the same
    `!cancelled()` and first-step check.
  - The aggregate `system` job (`build.yml:1981`) reports those jobs'
    results as it does today, so a carry failure reaches it as their failure.
  - On cancellation, a cancelled workflow cancels `carry` and its
    dependents, which report `cancelled` as today (§6).
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
- **The first draft's guards** (roots-only, and "references source implies
  excluded"). They are described in design 2: one breaks the carry push, and
  the other cannot fail.

## Risks

- **`flake archive` copies the flake source**, plus its inputs, into the
  store and prints them. On a runner with the inputs already fetched, that
  costs seconds. The output's `.path` is the top-level source; the inputs are
  under `.inputs`, which is ignored.
- **`needs: carry` serializes about a minute** in front of the heavy jobs
  when no carry is needed. While one is needed and not yet cached, the first
  run compiles it, about 20 minutes, once, instead of six times in parallel. That is accepted for a fix to a whole-pipeline timeout. A
  `carry` failure on a non-bump run, an evaluation error say, would block
  every PR. It is an evaluation `main` already does in the nightly
  (`review.sh`), so it fails only when `review.sh` would too.
- **The cache budget:** the carried closure is already counted by
  `cache-budget.sh` (it lies inside `vm-toplevel`), and pushing it early adds
  nothing to the budget.

## Verification

- **Cheap, locally:** `checks.cache-budget` with the new cases:
  - **commit-specific excluded:** the stub's exclusion set holds the
    toplevel, and the push proceeds;
  - **commit-specific missing:** the stub's referrers omit the toplevel, and
    bump refuses;
  - **package-only entry**, the carry case: the exclusion set is roots only,
    the entry is not on the list, and the push proceeds.

  §1 breaks:
  - restore the `flake metadata` read → the stub case returning only
    `flake archive` fails;
  - delete design 2's check → the commit-specific-missing case fails;
  - make the check apply to every entry → the package-only case fails.
- **Hosted runner, with real Determinate Nix:** this is still outstanding,
  because the probe measured derivation `inputs.srcs`, not the
  referrers-closure of built outputs that the script uses. So re-run the
  probe branch with the same checkout and invocation as `system-build`:
  build `vm-toplevel`, then run the exclusion computation alone, with no
  push. It must report an exclusion set holding `vm-toplevel`'s output path.
  That is the real-`nix` measurement, on CI's environment, before the PR.
  If it does not hold, this spec returns for a decision (intent 2b).
- **A deliberate `carry` failure on the PR branch** (a temporary commit
  making the step exit 1). Every dependent goes red naming carry, and none is
  skipped. The commit is then dropped.
- **actionlint** on `build.yml`. Also confirm `checks.cache-budget` and the
  check-coverage guard still see every job.
- **On the PR itself**, an ordinary PR with the carry active on `main`:
  `carry` builds the carried packages, or substitutes them once `main` has
  pushed, and pushes nothing. Every job runs as before.
- **On the next dated bump PR:**
  - the run log shows `carry` building the needed packages once;
  - `pushing … left out as commit-specific` lines from `system-build`;
  - no job compiles codex;
  - no hand push.

  A bump with no carry needed shows `no cargo carry is needed` and the
  exclusion push lines.
- `install` is not affected. No self-hosted job gains `needs: carry`.

## Review (2026-11-10, after the first approval)

Codex (gpt-6.1-sol) and agy (model not reported) reviewed the approved
draft. Their findings, all confirmed against `cachix-push.sh` and
`build.yml`, changed design 2 and parts of design 3. So this revision is a
draft again, for re-approval:

- design 2's two guards: the first breaks carry, the second is a tautology.
  Replaced;
- `needs: carry` failure handling was wrong: skip, or run on under
  `!cancelled()`. Now explicit;
- "no carry on `main`/ordinary PRs" was false since #1741. Corrected;
- allowlist membership was asserted. Now checked;
- `codex-acp` was assumed. Now follows the helper;
- the hosted verification of the referrers-closure is still outstanding,
  and named.
