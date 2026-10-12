---
status: draft
issue: 1250
intent: intent/2026-10-12-1250-cache-budget-upstreams.md
---

# Spec: cache-budget.sh counts what nixarchy.cachix.org actually stores

## Design

- **Narrow the subtraction.** In `.github/scripts/cache-budget.sh:21`, the
  default for `UPSTREAM_CACHES` becomes `https://cache.nixos.org` only, the
  one cache `cachix push` skips. The header line "Cachix does not store
  those" then becomes true, and it names the 2026-10-12 measurement.
- **Fix the allowlist's reasoning.** In
  `.github/scripts/cache-allowlist.sh:14-16`, the sentence now says the budget
  subtracts what cache.nixos.org serves. It notes that hyprwm-built paths are
  counted, because the push stores them (#1250).

## Alternatives rejected

- **Exclude hyprwm's paths from the push:** this would drop the second
  source #1248 kept on purpose, and it needs a path filter in
  `cachix-push.sh` that saves about 75 MiB.
- **A check that the upstream list matches what Cachix skips:** that is a
  property of Cachix's server, so no offline check can see it. The header
  records the measurement instead (§3: say so when no layer can reach it).

## Risks

The budget figure rises by about 75 MiB, to about 2055 of 2560. A later
nixpkgs bump has that much less headroom, which is the honest figure.

## Verification

- **`tests/cache-budget.nix`** sets `UPSTREAM_CACHES` itself, so it is
  unaffected and must still pass.
- **CI's `system` job** prints a higher "in nixarchy.cachix.org" figure than
  `main`'s 1980 MiB, about +75. That is the proof that the change counts the
  nine paths. Compare the two runs in the PR.
- **Before CI:** run the lookup by hand over the Hyprland closure with only
  cache.nixos.org as the upstream. The nine paths must count, 75.3 MiB.
