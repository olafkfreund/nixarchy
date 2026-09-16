---
status: approved
issue: 725
intent: intent/2026-09-16-725-cache-prebuilt-binaries.md
---

# Spec: the cache carries prebuilt binaries it cannot speed up

## Design

### 1. All three agents are pinned explicitly (`modules/home.nix`)

```nix
services.nixi.agents = [
  "opencode"
  "codex"
  "claude"
];
```

**Owner's decision, 2026-09-16, amending Decision 1 of the intent.** All three
adapters are pinned rather than opencode alone. What this changes and what it
costs is in Risks below; it is a deliberate trade, not an oversight.

The consequence for this issue is that the `agents` line is **no longer the
budget fix** — `claude` stays, so the 650 MiB stays. The budget is brought back
under its ceiling by §2 alone:

```
2234 - 394 (zen-browser) = 1840 MiB, against an unchanged 2048
```

What the line still does is add `opencode` (free, served by `cache.nixos.org`,
and it speaks ACP itself so it pins no adapter — expected cost to this budget:
zero) and make the set explicit instead of conditional on `allowUnfree`.

Plain assignment, not `lib.mkDefault`: `agents` is a `listOf`, and AGENTS.md §7
is explicit that `mkDefault` on a merging type silently drops the whole
contribution the moment a user adds an element.

A `default` is not a definition, so this replaces upstream's conditional default
outright. That matters even though the contents overlap: upstream's default
*varies with `allowUnfree`*, so a machine that turns unfree off silently gets a
different agent set. Stating the three makes the set a property of nixarchy
rather than a side effect of a flag.

The comment beside it belongs in the existing block at `modules/home.nix:563`
("the three defaults nixarchy deliberately does NOT change" — `autoEnable`,
`barWidget.enable`, `menuEntry.enable`). `agents` becomes the one nixarchy
*does* change, and the reason is not obvious from either side:

> upstream's default is `lib.optional (pkgs.config.allowUnfree or false)
> "claude" ++ [ "codex" ]` — conditional on a flag `modules/nixos.nix:795` sets,
> so the agent set moved with `allowUnfree` and nobody chose it. nixarchy names
> all three instead: opencode (speaks ACP itself, no adapter, free), codex
> (Apache-2.0, `data/apps.nix:361`), and claude, whose adapter pulls the unfree
> `claude-code` — 650 MiB into `reference-toplevel`, and so into every installed
> machine and into a public cache. That cost is accepted deliberately (#725).

The other agents stay reachable by both existing routes, unchanged:
`omarchy-default-agent` installs one from the Install menu through
`nixarchy-pkg-add`, and `programs.nixarchy.defaultAgent` pins one declaratively
(`modules/apps.nix:1064`), which already handles `claude` being unfree.

### 2. A prebuilt package is declared, and not pushed (`data/apps.nix`)

```nix
zen-browser = {
  ...
  # A -bin- package: the derivation fetches Zen's own build and patches it.
  # Caching it makes nixarchy.cachix.org a second, slower mirror for bytes the
  # user would fetch from the vendor regardless, and costs 394 MiB of a 5 GB
  # tier that evicts something real to hold them (#725).
  prebuilt = true;
};
```

`prebuilt` rather than `cache = false`: it states the fact about the package,
so the allowlist's decision follows from it rather than being restated at every
call site. `cache-allowlist.sh`'s `apps` filter gains one clause beside the
existing `unfree` one:

```nix
ours = builtins.filter (
  n: (cat.${n}.ours or false)
     && !(cat.${n}.unfree or false)
     && !(cat.${n}.prebuilt or false)
) (builtins.attrNames cat);
```

### 3. The criterion is written down (`cache-allowlist.sh` header)

The header already says "An entry belongs here only if someone downloads it."
That is necessary and not sufficient — it is what let 1 GB of prebuilt binary
in. It gains the second half:

> …and only if they would otherwise **build** it. `cache-budget.sh` already
> subtracts everything `cache.nixos.org` and `hyprland.cachix.org` serve, so a
> path reaching this budget is one upstream will not serve — but "unfree, so
> Hydra will not build it" and "expensive to build" are different claims. A
> prebuilt binary is a download either way.

### 4. The manual states that unfree is allowed by default (`docs/manual/`)

One short section: nixarchy sets `nixpkgs.config.allowUnfree`, so proprietary
packages install without further configuration; `programs.nixarchy.allowUnfree
= false` turns that off. It also names the consequence the intent traced — the
flag changes what enters the system closure, not merely what is permitted.

## Alternatives rejected

- **Raise `CACHE_BUDGET_MIB`.** The intent rejects it: 2234 MiB/commit × the
  several commits Cachix holds overflows the 5 GB tier, which is the eviction
  that cost 31 of 34 proofs on 2026-09-15 and broke every `omarchy` run on
  2026-09-16. It would close today's red by re-arming its cause.
- **Drop `vm-toplevel` / `reference-toplevel` from the allowlist.** They are
  genuine builds, and an offline install *copies* `reference-toplevel`. Removing
  them would make every install download what the ISO exists to carry.
- **`lib.mkDefault` on `agents`.** AGENTS.md §7, reproduced live, not
  hypothetical.
- **Exclude by name pattern (`-bin-`) in the allowlist.** Magic, and wrong in
  both directions: a prebuilt package need not say so in its name, and a
  `-bin-` suffix does not always mean no build.
- **Remove `claude-code` from `data/apps.nix`.** It is not the problem. The
  apps list already refuses to push unfree; the 650 MiB arrives through nixi's
  `agents`, and the catalogue entry is how a user deliberately installs it.

## Risks

- **Cache headroom, knowingly spent.** The 2048 ceiling is a proxy: Cachix holds
  several in-flight commits inside a 5 GB tier, so what matters is how many fit.

  | pinned agents | per commit | commits before overflow |
  |---|---|---|
  | before this change | 2234 MiB | 2.2 |
  | **this change** | **1840 MiB** | **2.7** |
  | opencode + codex only | 1190 MiB | 4.2 |

  #697's spec assumed the cache holds "the latest commit plus two or three
  predecessors". At 1840 MiB the third predecessor overflows, and 16 commits
  landed on `main` on 2026-09-16 alone. So the eviction that cost 31 of 34 proofs
  on 2026-09-15 remains reachable on a busy day; this change buys margin without
  removing the failure mode. If proofs are evicted again, this row is the first
  place to look, and dropping `claude` from `agents` is the lever.

- **An unfree binary is published to a public cache, deliberately.**
  `claude-code` is `unfree = true` (`data/apps.nix:355`). Pinning its adapter
  puts it in `reference-toplevel`, which `cachix-push.sh` pushes by closure, so
  nixarchy hosts and serves Anthropic's proprietary binary. This **reverses**, for
  the toplevels, the policy `cache-allowlist.sh` states for apps: *"this cache is
  public, and pushing a proprietary binary to it is redistributing it. Its users
  build it, as nixpkgs' do."* Recorded here rather than left to be rediscovered:
  the reversal is the owner's decision of 2026-09-16, taken with the licence
  question raised, and `cachix push` cannot exclude a path from a closure, so
  there is no partial version of it. Revisit if Anthropic's terms are reviewed.

- **A machine with `allowUnfree` off now names `claude` explicitly.** Upstream's
  conditional default dropped `claude` when the flag was false; an explicit list
  does not. `programs.nixarchy.allowUnfree = false` plus a pinned claude adapter
  must not become an evaluation failure for a user who never asked for it —
  `tests/options.nix` covers both states (Mode A), and this case belongs there.
- **`tests/options.nix` asserts nixi's defaults** (`nixiEnablesCard`, and the
  comment warns "tests/options.nix fails if that default moves"). A case for
  `agents` is part of this change, not a follow-up.
- **`reference-toplevel` changes, so the ISO's baked closure changes.**
  `install-iso` and `iso-budget` are nightly-only; the budget moves *down*, so
  the risk is a stale assertion rather than an overflow.
- **Mode A.** `tests/options.nix` asserts every option in both states; the off
  state is the one a refactor breaks quietly.
- **Do not compare closures across commits** (AGENTS.md §5): `flake.outPath` is
  in the closure, so every commit changes every derivation. Any before/after
  must be evaluated in one tree.

## Verification

**The failing output already exists**, which satisfies step 1 of AGENTS.md §1
with a real regression rather than a synthetic break:

```
allowlist: 21 entries, 3027 paths in their closures
in nixarchy.cachix.org: 393 paths, 2234 MiB of a 2048 MiB budget
Error: the allowlist costs 2234 MiB, over its 2048 MiB budget.
```

captured from #719's `system` job, step 22, on 2026-09-16.

1. **The gate itself.** `cache-budget.sh` runs in `build.yml`'s `system` job on
   every pull request, *"so it fails before a large addition merges"*. Its
   passing output on this PR is the proof, and goes in the PR body.
   Prediction, falsifiable: **≤ 1840 MiB** against an unchanged 2048 budget.
   An upper bound — removing `zen-browser` can drop dependencies the failing
   run's top-ten did not show, so a lower number confirms rather than
   contradicts. A number at or above 2048 falsifies the design.
2. **Watch it fail, in one tree** (§5's rule about closures): revert the
   `prebuilt` flag alone, re-run `cache-budget.sh`, confirm ~2234 MiB returns,
   restore. Proves the line is what moved the number, not something incidental.
   Verify the revert landed with `git diff` before reading the result — a
   silent no-op break and a blind check are indistinguishable from exit status.
3. **`checks.options`** — cheap, evaluation only, runs locally: the new
   `agents` default in both Mode A states.
4. **Presence and absence, directly:** `nix eval` the reference closure and
   assert `opencode` is in it and no `zen-beta-bin-unwrapped` path is, so each
   half of the change is measured rather than inferred from one total.
   `claude-code` is expected to remain, by decision.
5. **`nix fmt -- --ci`, `statix`, `deadnix`** before pushing.

Not attempted here: `checks.session` and the install checks. They cannot vary
the variable this change touches (AGENTS.md §3) — the budget is a property of
what CI pushes, not of a booted desktop.
