---
status: draft
issue: 725
spec: spec/2026-09-16-725-cache-prebuilt-binaries.md
---

# Plan: the cache carries prebuilt binaries it cannot speed up

## The approved decisions, carried over

Self-contained: everything needed to implement this is here.

`cache-budget.sh` failed on #719's `system` job at **2234 MiB against a
2048 MiB budget**. The budget is derived (#697's spec measured ~1.05 GB/commit
and doubled it), so raising it re-arms the eviction that cost 31 of 34 check
proofs on 2026-09-15 and broke every `omarchy` run on 2026-09-16. **The budget
does not move.**

Four changes, and **`build.yml` is not one of them** — no CI gate is touched,
because `CACHE_BUDGET_MIB` stays at 2048.

1. **`services.nixi.agents = [ "opencode" "codex" "claude" ]`** — owner's
   decision. All three pinned. This is *not* the budget fix; claude stays, so
   its 650 MiB stays. It adds opencode (free, upstream-cached, speaks ACP
   itself so it pins no adapter) and makes the set explicit rather than
   conditional on `allowUnfree`, which is how the 650 MiB arrived unchosen.
2. **`prebuilt = true` on the `zen` catalogue entry**, filtered out of the
   allowlist's `apps` group. **This is the budget fix:** `2234 − 394 = 1840`.
3. **The criterion in `cache-allowlist.sh`'s header** — an entry belongs only if
   someone downloads it *and would otherwise build it*.
4. **The manual states `allowUnfree` is on by default**, and that the flag
   changes what enters the closure rather than merely what is permitted.

Two costs, accepted deliberately and recorded in the spec's Risks: headroom
falls to **2.7 in-flight commits** inside the 5 GB tier (dropping `claude` from
`agents` is the lever if proofs are evicted again), and an unfree binary is
published to a public cache, reversing for the toplevels the policy
`cache-allowlist.sh` states for apps.

## Steps

1. **`data/apps.nix`** — add `prebuilt = true;` to the `zen` entry
   (line 306, key `zen`, `attr = "zen-browser"`, already `ours = true`), with
   the reason beside it: a `-bin-` package, so caching it makes this cache a
   slower second mirror for bytes the user fetches from the vendor anyway.
   → verify: `grep -A12 '^  zen = {' data/apps.nix` shows the flag and reason.

2. **`.github/scripts/cache-allowlist.sh:51`** — add the clause to the `apps`
   filter, beside the existing `unfree` one:
   ```nix
   n: (cat.${n}.ours or false)
      && !(cat.${n}.unfree or false)
      && !(cat.${n}.prebuilt or false)
   ```
   → verify: `.github/scripts/cache-allowlist.sh apps` no longer prints
   `.#zen-browser`, and still prints every other `ours` app. Compare the full
   list before and after — the diff must be exactly one line.

3. **`.github/scripts/cache-allowlist.sh` header** — the criterion's second
   half, per spec §3. Three lines, not a paragraph.
   → verify: read it back; it must say why "upstream will not serve it" is not
   the same claim as "expensive to build".

4. **`modules/home.nix`** — `services.nixi.agents = [ "opencode" "codex"
   "claude" ];` beside `services.nixi.enable` (line 561), plain assignment
   (AGENTS.md §7: `mkDefault` on a list is dropped the moment a user adds an
   element). Extend the comment block at line 563 — which currently names the
   three nixi defaults nixarchy does *not* change (`autoEnable`,
   `barWidget.enable`, `menuEntry.enable`) — with `agents` as the one it does,
   and why: upstream's default is conditional on `allowUnfree`, which
   `modules/nixos.nix:795` sets.
   → verify: `nix eval` the home config's `services.nixi.agents` and get the
   three, in both `allowUnfree` states.

5. **`tests/options.nix`** — a case asserting the pinned set, in both Mode A
   states. The existing nixi cases are at 702+ (`nixiEnablesCard`), with
   `nixiOff` at 285 and a `services.nixi` block at 787; follow their shape.
   The case that matters is the risk the explicit list creates: upstream's
   default dropped `claude` when `allowUnfree` was false and an explicit list
   does not, so `programs.nixarchy.allowUnfree = false` must still evaluate.
   → verify: `nix build .#checks.x86_64-linux.options --print-build-logs`.

6. **`docs/manual/other-packages.md`** — a short section: nixarchy sets
   `nixpkgs.config.allowUnfree`, so proprietary packages install without
   further configuration, and `programs.nixarchy.allowUnfree = false` turns it
   off. Name the consequence: the flag changes what enters the system closure.
   No new page, so no sidebar row and no `readme-counts.sh` vocabulary change.
   → verify: the page renders; no count moves.

7. **Formatting and lint, last.** `nix fmt -- --ci`, `statix check .`,
   `deadnix --fail .`.
   → verify: all clean. **Watch for the local formatter hook** — it reformats
   `.nix` files after an edit and can leave the tree disagreeing with
   `nix fmt --ci`; re-run `git diff` after formatting and commit whatever it
   changed rather than pushing a tree CI will reject.

## Tests

Run in this order; the first two are the proof.

```sh
# 1. The gate itself, on the real allowlist. Expect <= 1840 MiB of 2048.
CACHE_BUDGET_MIB=2048 .github/scripts/cache-budget.sh
```
Expected: `in nixarchy.cachix.org: <n> paths, <=1840 MiB of a 2048 MiB budget`,
exit 0. **A number at or above 2048 falsifies the design** — report it, do not
raise the budget to meet it.

Cost warning: this substitutes or builds every allowlist entry, including both
toplevels and five MicroVM runners. Check nothing is in flight first
(AGENTS.md §6 — all four runners are on p620 and so is this shell):
```sh
gh run list --limit 8 --json status -q '[.[]|select(.status!="completed")]|length'
```
If that is non-zero, skip the local run and let CI be the proof: the step lives
in `build.yml`'s `system` job on every pull request, which is where it failed.

```sh
# 2. AGENTS.md §1 -- prove the check fails, in ONE tree (§5: every commit
#    changes every derivation, so never compare across commits).
git checkout HEAD -- data/apps.nix        # NOT `git checkout --`, which
                                          # restores the index, i.e. the break
git diff --stat                           # prove the revert actually landed
CACHE_BUDGET_MIB=2048 .github/scripts/cache-budget.sh   # expect ~2234, exit 1
```
Then restore the flag and re-run to watch it pass. Capture both outputs for the
PR. A break that silently fails to apply and a check that cannot see it are
indistinguishable from the exit status alone — hence the `git diff`.

```sh
# 3. Cheap, and runs locally.
nix build .#checks.x86_64-linux.options --print-build-logs

# 4. The closure claims, measured rather than inferred from one total.
#    opencode present, zen absent, claude-code present by decision.
nix path-info -r .#checks.x86_64-linux.reference-toplevel \
  | grep -cE 'opencode|zen-beta-bin-unwrapped|claude-code'
```

```sh
# 5. The allowlist diff is exactly one line.
.github/scripts/cache-allowlist.sh > /tmp/after.txt   # vs the same on HEAD
```

Not run here: `checks.session`, the install checks. They cannot vary the
variable this change touches (AGENTS.md §3) — the budget is a property of what
CI pushes, not of a booted desktop.

## Rollback

Each change is independent and separately revertible:

- **Budget regression** → revert the `prebuilt` flag (step 1) and the filter
  clause (step 2). `zen-browser` returns to the cache and the budget returns to
  2234, i.e. failing — so this rollback is only ever paired with a different
  fix, never on its own.
- **Agent set wrong** → revert step 4. The option falls back to upstream's
  `lib.optional (pkgs.config.allowUnfree or false) "claude" ++ [ "codex" ]`,
  which is today's behaviour, so this is safe alone.
- **Whole change** → `git revert` the implementation commit. Nothing here is
  stateful; no cache entry is deleted by this PR, so reverting restores the
  previous push set on the next push from `main`.
- **If proofs are evicted again** despite this, the lever named in the spec is
  dropping `claude` from `agents`: 1840 → 1190 MiB, 2.7 → 4.2 commits of
  headroom. That is a decision to bring back to the owner, not to take
  unilaterally.
