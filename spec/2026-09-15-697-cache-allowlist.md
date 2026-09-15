---
status: draft
issue: 697
intent: intent/2026-09-15-697-cache-allowlist.md
---

# Spec: the binary cache holds what users and CI download, within 5 GB

## Measurements this design rests on

Sizes count only paths that cache.nixos.org and hyprland.cachix.org do not
already serve, since Cachix skips those. Measured on p620, 2026-09-15.

| candidate | new paths | cost |
|---|---|---|
| `omarchy` | 1 | 124 MiB |
| `checks.vm-toplevel` closure | 208 | 327 MiB, includes `omarchy` |
| `checks.reference-toplevel` closure | 208 | 316 MiB, nearly all shared with `vm-toplevel` |
| `microvm-agent` (KVM) closure | 46 | 424 MiB, of which 394 MiB is `qemu-host-cpu-only-for-vm-tests`, shared by all five KVM runners |
| `microvm-agent-tcg` closure | 44 | 29 MiB |
| a check result, `runCommand` or VM test | 1 | 96 bytes to 12 KB |

**Why check results are cheap.** A check result references nothing, so pushing
it uploads the result alone. This matters because `cachix push` has no option
to omit dependencies (`cachix push --help`): what is pushed is always the
closure. The design only works because check results have no dependencies.

**What one commit on `main` costs:**

| part | estimate |
|---|---|
| both toplevels, which include `omarchy` | about 350 MiB |
| five KVM runners, one shared QEMU plus about 30 MiB each | about 545 MiB |
| five TCG runners | about 145 MiB |
| check results | under 1 MiB |
| **total** | **about 1.05 GB** |

The apps built here (`apps` job) are not measured yet; the budget step measures
them rather than a number written here.

## Design

### 1. No job pushes by store diff

Every `cachix/cachix-action@v17` step gets `skipPush: true`. It still configures
the cache for pulling. Affected:

- `build.yml`: `lint`, `devenv-presets`, `omarchy`, `apps`, `system`, `box`
- `omarchy.yml` and `update.yml`: `bump`

From then on, the only way anything reaches nixarchy.cachix.org is one of the
two explicit pushes below.

**Why `skipPush` rather than removing the action.** The action sets up the
substituter with authentication, and every job needs to pull. `continue-on-error`
stays where it is (#235).

### 2. One allowlist, one push script, used only on `main`

`.github/scripts/cache-allowlist.sh` prints the allowlist, one flake installable
per line, each with the reason it is on the list as a comment in the script:

| installable | reason |
|---|---|
| `.#omarchy` | every user downloads it |
| `.#checks.x86_64-linux.vm-toplevel` | installs and CI boot this closure |
| `.#checks.x86_64-linux.reference-toplevel` | the installed system's closure, what an offline install copies |
| `.#microvm-<t>` for every template in `data/microvm-templates.nix` | `nixarchy vm run` downloads it instead of building QEMU |
| `.#microvm-<t>-tcg` for every template | `checks.microvm-boot` downloads it every night |
| every app in `data/apps.nix` with `ours = true` | users who enable one download it; built nowhere else |

The template and app entries are read from the data files, not written out by
hand, so adding a template adds its runners.

`cachix-push.sh` keeps its current contract (named closures, a loud warning on
failure, not fatal) and gains one guard: it pushes closures only when
`GITHUB_REF` is `refs/heads/main`. Anywhere else it prints
`not main; closures are pushed from main only` and exits 0.

**Callers.** The existing `.#omarchy` push in `omarchy` and the toplevel push in
`system` stay where they are; they already run after those builds. `system`
also pushes the runners after `checks.microvm-template` has built them, and
`apps` pushes its apps. Every caller passes the list from
`cache-allowlist.sh <group>`, so nothing is named in YAML.

### 3. Check results are pushed from every ref, and only check results

`build-unless-proven.sh`, after a successful build, pushes each check it built
through `cachix-push.sh --proof <check>...`. Proof mode:

- **Paths.** It resolves the result path with `nix eval --raw`.
- **Refusal.** If the result's closure is more than one path, or more than
  1 MiB, it refuses with `::warning::`. A check whose result references
  something would upload a closure, which is exactly how the cache filled.
- **Refs.** It pushes on pull requests as well as `main`: a few KB per check,
  and a pull request's re-runs are what benefit.

`install-check.yml`'s own proof push already does this by hand for `install`,
`free-space` and `installer-refusal`. It moves to `--proof`, so that step has
one implementation.

**Why pull requests push proofs.** The approved intent said pull requests push
nothing, and the measurements refine that: a PR's proofs cost kilobytes, and
without them every re-run of a PR rebuilds every check. That is the failure
that blocked #693.

### 4. The budget, measured every time it could change

`.github/scripts/cache-budget.sh` builds (in practice, substitutes) every entry
of `cache-allowlist.sh`, takes the union of their closures, drops every path
cache.nixos.org or hyprland.cachix.org serves, and sums what is left. It
prints the total and the ten largest paths. Over the budget, it fails with
`::error::`, naming the entries that grew.

- **Budget: 2 GB for one commit's allowlist.** Pushes from different commits
  overlap only partly: `omarchy` alone is a new 124 MiB path on every commit,
  because it depends on the flake's rev (#212). So the cache holds the latest
  commit plus two or three predecessors until the least recently used ones age
  out. With about 1.05 GB per commit, 2 GB leaves room for the allowlist to
  grow about twofold, and 5 GB still holds the current and previous commit
  plus their check results.
- **Where it runs.** A step at the end of `build.yml`'s `system` job, on pull
  requests and `main`. That job has already built both toplevels and the
  runners; `omarchy` and the apps are substituted. On a pull request it fails
  before a large addition merges. Not `continue-on-error`: this step is the
  gate.
- **Test.** `checks.cache-budget` runs the real script against a stubbed `nix`
  and `curl`: three entries under the budget pass, one oversized entry fails
  naming it, upstream-served paths are not counted, and a path shared by two
  entries is counted once.

### 5. Keeping allowlisted paths alive

Cachix evicts by last download, and a push is not a download. #696's nightly
`runners` job already re-pushes MicroVM runners it finds missing. This
generalises it: the nightly `cache` job probes every `cache-allowlist.sh`
entry's result path on `main`, and the `runners` job (renamed `repush`)
rebuilds and pushes whatever is missing. It fails only if an entry is still
missing after the push. No NAR downloads for keep-alive: a missing entry is
put back, which costs a nightly build only on the nights it happens.

**Dependency.** Built on #696. This PR is opened after #696 merges, or on its
branch if you prefer.

### 6. The p620 job move is dropped

`ci/generated-checks-self-hosted` was a fallback for a cache that held no check
results. With §3 it does, so the branch is deleted and no PR is opened. It
stays recoverable from the reflog until then.

## Alternatives rejected

- **`pushFilter` on cachix-action.** A regex that excludes derivations "may
  still push them as part of another path's closure" (cachix-action README), so
  a filter cannot promise what the cache holds.
- **Keeping the store-diff push on `main` only.** `main` builds VM test drivers,
  disk images and the ISO pieces too. That is the same fill, from one branch.
- **Pull requests push nothing at all.** Every re-run of a PR rebuilds every
  check. Proofs cost kilobytes; the rebuild is what blocked #693.
- **A hand-kept size limit per entry.** It goes stale on the next commit.
- **Downloading each allowlisted NAR nightly to count as use.** About 1 GB of
  bandwidth every night to prevent an eviction the repush already repairs.
- **Moving the `omarchy` job to p620.** It works around missing proofs instead
  of keeping them, and puts PR load on the runners that the installs use.
- **Dropping the KVM runners from the allowlist.** 545 MiB fits within the
  budget, and the alternative is every `nixarchy vm run` user building QEMU.

## Risks

- **A check whose result references its inputs** would be refused by proof
  mode and then rebuilt on every run. The refusal is a visible warning naming
  the check, so it is found, not silent.
- **The budget step adds evaluation to `system`.** Every entry is already built
  in that job or substitutable, so the cost is `nix path-info` plus about 3,000
  narinfo lookups. The implementation measures this and parallelises the
  lookups if it takes over a minute.
- **The first days after merge.** The cache is still full of old store-diff
  pushes. Least-recently-used eviction removes them over time, and nothing here
  needs manual deletion. Until then, a repush may evict another stale path,
  which is the intended direction.
- **A wrong allowlist entry** (an attr that no longer exists) fails
  `cache-allowlist.sh` in the budget step on the pull request that removed it,
  not silently on `main`.
- **Hosts.** Only CI changes. p620 runs the nightly repush and the self-hosted
  install jobs, which already push proofs.

## Verification

1. **Fixture checks, each seen failing (§1).** `checks.cache-budget` must go red
   on an oversized entry, on a double-counted shared path, and on counting an
   upstream path. Proof mode must refuse a result with a dependency, tested by
   extending `checks.template-runners` or a new fixture.
2. **A real budget number.** `cache-budget.sh` run on p620 against this branch
   prints a total near the estimate above; the number goes into the PR.
3. **No store-diff push left.** A grep in `build.yml`'s existing guard step: every
   `cachix/cachix-action` block has `skipPush: true`. This is a new assertion;
   it must fail when one block has `skipPush` removed.
4. **Lint.** `actionlint` and `shellcheck` clean; `nix fmt`, `statix` and
   `deadnix` clean.
5. **After merge.** The first `main` build's push steps log the allowlist and
   `pushing … (N paths)`, and the next nightly's `cache` job reports every entry
   served.
