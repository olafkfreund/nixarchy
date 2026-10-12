---
status: draft
issue: 1250
spec: spec/2026-10-12-1250-cache-budget-upstreams.md
---

# Plan: cache-budget.sh counts what nixarchy.cachix.org actually stores

**Decision.** The budget subtracts only `cache.nixos.org`, the one cache
`cachix push` skips. The 2026-10-12 measurement found nine hyprwm-built
paths, 75.3 MiB, both in hyprland.cachix.org and stored, signed, in ours.
The push is unchanged, and no new check is added, because no offline layer
can see Cachix's behaviour.

## Steps

1. **`.github/scripts/cache-budget.sh:7-8` and `:21`.** The default becomes
   `upstreams=${UPSTREAM_CACHES:-https://cache.nixos.org}`. The header says
   the subtracted paths are those cache.nixos.org serves, which `cachix push`
   skips. It also says hyprland.cachix.org's paths are stored and counted:
   nine paths, 75.3 MiB, measured 2026-10-12 (#1250).
   → Verify: `bash -n`; run `shellcheck` if the repo's lint does.
   Traps: none.
2. **`.github/scripts/cache-allowlist.sh:14-16`.** Change the sentence to
   say the budget subtracts what cache.nixos.org serves. hyprwm's builds are
   counted, because the push stores them.
   → Verify: `bash -n`.
3. **Prove it.**
   - Run `checks.cache-budget` under flock, and it must pass.
   - In the PR, quote `main`'s 1980 MiB and the PR's `system` figure.
4. **Commit and PR.** Use a full-sentence subject with `Closes #1250`.

## Tests

| command | expected |
|---|---|
| `nix build .#checks.x86_64-linux.cache-budget` | passes |
| CI `system` → cache budget | about 2055 MiB of 2560, up from 1980 |

## Rollback

Revert. The figure returns to the undercount.
