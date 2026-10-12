---
status: approved
issue: 1250
author: olafkfreund
---

# Intent: cache-budget.sh counts what nixarchy.cachix.org actually stores

## Problem

`cache-budget.sh` subtracts, from the allowlist's cost, every path that
`cache.nixos.org` or `hyprland.cachix.org` serves. Its stated reason is
"Cachix does not store those".

For `hyprland.cachix.org` that is false. Measured on 2026-10-12 against the
shipped Hyprland's closure, which is 172 paths:

| served by | paths | NAR size |
|---|---|---|
| cache.nixos.org only | 163 | 556.4 MiB |
| hyprland.cachix.org **and** nixarchy.cachix.org | 9 | 75.3 MiB |

`cachix push -r` skips only `cache.nixos.org`'s paths. Each of those nine
hyprwm-built paths has its own NAR and its own `nixarchy.cachix.org-1:`
signature in our cache. The budget subtracts them all the same, so it
undercounts by about 75 MiB for each Hyprland version it holds.

## Proposed outcome

The budget's figure matches what the push stores. `cache-allowlist.sh`'s
header no longer reasons from the wrong premise.

## Affected users and systems

- The `system` job's "cache budget" step, on `main` and on PRs.
- No machine or user is affected.

## Constraints

- **The budget step is a CI gate.** Today it reads 1980 MiB of 2560. Adding
  about 75 MiB stays under the budget, so nothing goes red.
- **The push itself is unchanged.** Keeping hyprwm's paths in our cache as
  a second source is deliberate (#1248).

## Open questions

None. Approved in advance by the owner ("approve all and fix all").
