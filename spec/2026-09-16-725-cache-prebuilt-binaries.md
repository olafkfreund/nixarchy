---
status: draft
issue: 725
intent: intent/2026-09-16-725-cache-prebuilt-binaries.md
---

# Spec: the cache carries prebuilt binaries it cannot speed up

## Design

### 1. opencode is the agent nixarchy pins (`modules/home.nix`)

```nix
services.nixi.agents = [ "opencode" ];
```

Plain assignment, not `lib.mkDefault`: `agents` is a `listOf`, and AGENTS.md §7
is explicit that `mkDefault` on a merging type silently drops the whole
contribution the moment a user adds an element.

A `default` is not a definition, so one definition replaces upstream's default
outright — the 650 MiB never enters. A user who writes
`services.nixi.agents = [ "claude" ]` concatenates with ours and gets
`[ "opencode" "claude" ]`, which is the right behaviour: their machine, their
unfree binary, their disk.

The comment beside it belongs in the existing block at `modules/home.nix:563`
("the three defaults nixarchy deliberately does NOT change" — `autoEnable`,
`barWidget.enable`, `menuEntry.enable`). `agents` becomes the one nixarchy
*does* change, and the reason is not obvious from either side:

> upstream's default is `lib.optional (pkgs.config.allowUnfree or false)
> "claude" ++ [ "codex" ]`, and `modules/nixos.nix:795` sets `allowUnfree` true,
> so inheriting it pins `claude-agent-acp` → unfree `claude-code`, 650 MiB, into
> `reference-toplevel` and therefore into every installed machine and a public
> cache. opencode speaks ACP itself, so it needs no adapter package at all, and
> it is free, so `cache.nixos.org` serves it.

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

- **A user relying on the pinned claude adapter.** nixi's own option
  documentation covers it: *"An agent not listed is still usable if its adapter
  is on `PATH`"*, and `defaultAgent = "claude"` installs the package. Behaviour
  changes only for someone who had it pinned implicitly and never asked for it —
  which is the 650 MiB this issue is about.
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
   Prediction, falsifiable: **≤ 1190 MiB** against an unchanged 2048 budget.
   An upper bound — removing an entry can drop dependencies the failing run's
   top-ten did not show, so a lower number confirms rather than contradicts.
2. **Watch it fail, in one tree** (§5's rule about closures): revert the
   `agents` line alone, re-run `cache-budget.sh`, confirm ~2234 MiB returns,
   restore. Proves the line is what moved the number, not something incidental.
   Verify the revert landed with `git diff` before reading the result — a
   silent no-op break and a blind check are indistinguishable from exit status.
3. **`checks.options`** — cheap, evaluation only, runs locally: the new
   `agents` default in both Mode A states.
4. **Absence, directly:** `nix eval` the reference closure and assert no
   `claude-code` or `claude-agent-acp` path, so the 650 MiB claim is measured
   rather than inferred from the budget total.
5. **`nix fmt -- --ci`, `statix`, `deadnix`** before pushing.

Not attempted here: `checks.session` and the install checks. They cannot vary
the variable this change touches (AGENTS.md §3) — the budget is a property of
what CI pushes, not of a booted desktop.
