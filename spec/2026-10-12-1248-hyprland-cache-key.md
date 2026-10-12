---
status: approved
issue: 1248
intent: intent/2026-10-12-1248-hyprland-cache-key.md
---

# Spec: nixarchy trusts Hyprland's binary cache with the key Hyprland publishes

## What the investigation found

**The key was never Hyprland's.** Nothing points to a rotation:

- GitHub code search finds the published key in 2,440 files and the old one
  in 24. Those 24 sit in nixarchy, its forks, the owner's own repositories
  and five others that look copied from them.
- The Cachix API lists one signing key for the cache.

So treat it as a bad copy at `c5a2d566`, not as something Hyprland will do
again.

**Hyprland was never built from source because of this.** The intent feared
it was, and that is wrong. `nixarchy.cachix.org` holds the Hyprland that
nixarchy ships, signed with nixarchy's own key. On 2026-10-12, both caches
answered 200 for `irfl45bj…-hyprland-0.56.0+date=2026-10-03_9dc5398`, and
the copy in ours carries a `nixarchy.cachix.org-1:` signature. Every machine
has been downloading Hyprland from our cache instead of from hyprwm's.

What the bug actually costs:

- **Hyprland depends on our 5 GB free tier.** If a Hyprland path is evicted
  from it, machines build that path, even though hyprwm's cache has it.
- **The budget may undercount.** `cache-budget.sh` subtracts every path that
  `hyprland.cachix.org` serves, on the premise that Cachix does not store
  those for us. The signed copy above suggests it does. This is outside this
  task: see Risks.

## Design

### 1. One key, in all six places

Replace `hyprland.cachix.org-1:a7pgxzMz7+chwVL3/pzj6jIITemDosxrE9/Kb+PfYvE=`
with `hyprland.cachix.org-1:a7pgxzMz7+chwVL3/pzj6jIBMioiJM7ypFP8PwtkuGc=`
in:

- `flake.nix:12`
- `modules/nixos.nix:1062`
- `.github/actions/setup-nix/action.yml:51`
- `installer/cd.nix:819`
- `installer/install.sh:51`
- `installer/vm.nix:57`

The six copies stay copies, because they live in Nix, bash and YAML.
Section 2's check holds them equal. That settles intent question 3.

### 2. `checks.cache-keys`: one offline check that verifies the key

A new `tests/cache-keys.nix`, a `runCommand` shaped like
`tests/grep-q-pipefail.nix`. It runs over a `lib.fileset.toSource` of
`flake.nix`, `modules`, `installer`, `pkgs`, `tests` and `.github`. The
`intent/`, `spec/` and `plan/` directories are left out, because they quote
the old key.

The check fails in either of two cases:

1. **The copies disagree.** It collects every `<cache>.cachix.org-1:<key>` in
   that tree. For each cache it expects exactly one distinct value, and the
   error names every file and value when there is more than one. It applies
   to both `hyprland` and `nixarchy`, since it costs the same.
2. **The key does not verify a real signature.** For each cache,
   `tests/fixtures/cache-keys/` holds one `.narinfo` taken from that cache.
   The check rebuilds the narinfo fingerprint
   (`1;<path>;<narHash>;<narSize>;<refs>`) and verifies that cache's `Sig`
   with the key it found in the tree. A short Python script does this with
   `python3Packages.pynacl`.

   This is what catches this bug, on every pull request, with no network.
   A narinfo's signature never expires, so the fixtures do not go stale when
   Hyprland moves.

`flake.nix` gets one `checks.cache-keys` entry. `omarchy`'s generated step
builds it, so no workflow edit is needed (§4).

The fixtures:

- **Hyprland:** the narinfo for the path above, fetched from
  `hyprland.cachix.org` and committed.
- **nixarchy:** one narinfo from `nixarchy.cachix.org` with a nixarchy `Sig`.

### 3. Fix the claims that rest on the wrong premise

- **`docs/internals/flake.md:118`:** the "built or fetched" cell names both
  caches. It says Hyprland is fetched from `hyprland.cachix.org`, with
  `nixarchy.cachix.org` as the second source. Until #1248 it came only from
  ours.
- **`setup-nix/action.yml`:** its comment says "verified, not assumed -- so
  with this the compositor is a download". It gets one honest sentence: the
  key was wrong until #1248, and the download came from nixarchy's cache.
  This line sits in the file whose value changes anyway.
- **`tests/AGENTS.md`:** one paragraph on the general lesson. A trust key is
  a value nothing exercises when a second cache serves the same paths, so
  check it by verifying a signature, not by comparing it with itself.
- **Left alone:**
  - `build.yml:1309` says Hyprland is "in hyprland.cachix.org and in ours".
    That is true, and the file is CI config.
  - `cache-allowlist.sh:15`'s budget premise is the Risks item below, not
    this fix.

### Coexistence (§14)

`nix.settings.trusted-public-keys` is a list, so it merges:

- **A user who already lists the correct key** gets it twice, which Nix
  ignores.
- **A user who lists the old key** keeps it. It is inert, because it
  verifies nothing.

Nothing collides, so there is no fixture to add to
`tests/coexistence/fixtures.nix`. A fixture that cannot fail is ruled out
by §1.

### Mode A

The module copy stays behind `programs.nixarchy.binaryCaches`, exactly as
now.

## Alternatives rejected

- **A nightly network check** that runs `nix store verify` against the live
  cache (intent question 2). The fixture check catches this bug, the wrong
  key in the tree, offline and per pull request. A network check would add
  only rotation detection, rotation has never happened (see above), and it
  would need a `nightly.yml` edit plus a decision about a missing narinfo.
  If Hyprland ever rotates, the symptom is this bug again: slower installs
  and a red fixture once someone refreshes it. Cheap to add then.
- **One source of truth** generated into bash and YAML: a build step for six
  lines that change once in three years. The equal-copies check does the
  same job.
- **Fixing it only in the three files the issue names:** that would leave
  the installer, the VM harness and CI on the wrong key.
- **Dropping `hyprland.cachix.org`, since ours serves Hyprland anyway:** that
  ties Hyprland's availability to our eviction-prone free tier, which is the
  weakness this fix removes.

## Risks

- **Trust root.** The new key comes from Cachix's API and Hyprland's wiki,
  both read directly on 2026-10-12, and it verifies a real Hyprland path.
  Accepting it means trusting hyprwm's builds, which nixarchy already
  intended to do and already trusts through their flake input.
- **`setup-nix` is CI plumbing (§11).** The value change rides in this PR,
  and a human merges it. Substitution only moves where paths come from;
  nothing a check builds changes.
- **The self-hosted runners' own config.** The owner's `nixos_config` repo
  (`flake.nix` and `modules/services/nixarchy-runner.nix`) and
  `nixarchy-hyprflip` carry the same wrong key. They are outside this repo,
  and the PR will name them so the owner can fix them.
- **The cache budget may undercount.** The finding above suggests Cachix
  stores Hyprland paths for us even though `hyprland.cachix.org` serves
  them. If it does, `cache-budget.sh` undercounts what we use of the 5 GB.
  It needs a measurement of its own, so the plan stops at filing it as a
  separate issue (milestone "Keeping the lights on", area `ci`). It does not
  change the budget here.
- **Installed machines** pick the key up on their next rebuild, gated as
  before. Nothing changes until then.

## Verification

- **§1 break proof.** With the fix in place, `checks.cache-keys` passes.
  Then it is run against two breaks, restoring with `git checkout HEAD --`
  after each:
  - the old key put back in `flake.nix` alone fails on copies-disagree,
    naming `flake.nix`;
  - the old key put back in all six files fails on signature-verify for
    `hyprland`.

  Each break gets a `git diff` first, to prove it landed, and both failure
  outputs go in the PR.
- **The real thing, once.** `nix store verify --no-contents --store
  https://hyprland.cachix.org --option trusted-public-keys <new key> <path>`
  passes, and fails with the old key. That output goes in the PR too.
- **Eval:** `nix eval .#nixosConfigurations.vm.config.nix.settings.trusted-public-keys`
  shows the new key.
- `nix fmt -- --ci`, statix and deadnix.
- `install` / `install-iso` are left to CI. They change only which cache a
  path comes from.
