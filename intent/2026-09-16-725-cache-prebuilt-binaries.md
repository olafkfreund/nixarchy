---
status: approved
issue: 725
author: olafkfreund
---

# Intent: the cache carries prebuilt binaries it cannot speed up

## Problem

`cache-budget.sh` refuses on `main`'s own allowlist: 2234 MiB against a
2048 MiB budget. It surfaced on #719's `system` job, but #719 is not the
cause — its flake input sources are 184 MiB of the total, and subtracting
them leaves `main` at ~2050 MiB, already at the limit.

The budget is derived, not arbitrary.
`spec/2026-09-15-697-cache-allowlist.md:115` measured **~1.05 GB per commit**
and doubled it for headroom, because Cachix holds several in-flight commits at
once and all of them have to fit the 5 GB free tier:

```
spec assumption:  1.05 GB/commit x 2 commits = 2.1 GB + proofs   fits 5 GB
today:            2.23 GB/commit x 2 commits = 4.47 GB + proofs  over 5 GB
```

Overflowing that tier is not hypothetical. It evicted 31 of 34 check proofs on
2026-09-15. That eviction is why `omarchy` spent 2026-09-16 reporting
`proven: 13   to build: 40` and failing on every branch that ran — two lost
their runner mid-build (14 and 17 minutes, `The operation was canceled.`) and
one hit the 45-minute limit exactly. So raising the ceiling to fit 2234 MiB
would close today's red by re-arming the failure that caused it.

What grew it: b2fe7bd (#713, "Pin nixi 0.10") pulled `claude-agent-acp`
(442 MiB) and `claude-code` (208 MiB) into the system closure.

Underneath is a criterion the allowlist never stated. `cache-budget.sh`
already subtracts every path `cache.nixos.org` or `hyprland.cachix.org`
serves, so nothing here duplicates nixpkgs. But "upstream misses it" is not
the same claim as "it must be built from source":

| path | upstream misses it because | a build? |
|---|---|---|
| `qemu-host-cpu-only-for-vm-tests` (394 MiB) | custom variant | yes |
| `omarchy` (124 MiB), `initrd`, `index` | assembled here | yes |
| `claude-agent-acp` (442 MiB), `claude-code` (208 MiB) | **unfree**; Hydra does not build unfree | no — prebuilt |
| `zen-beta-bin-unwrapped` (394 MiB) | `ours`, packaged here | no — `-bin-`, prebuilt |

A prebuilt binary in this cache saves a user nothing: it is the same bytes they
would fetch from the vendor, served more slowly, from a tier that evicts
something else to hold them.

For the two unfree paths there is a second reason, and the repo has already
written it down. `cache-allowlist.sh` refuses to push unfree apps — *"this
cache is public, and pushing a proprietary binary to it is redistributing it.
Its users build it, as nixpkgs' do."* `claude-code` is `unfree = true` in
`data/apps.nix`, yet reaches the cache inside `vm-toplevel` and
`reference-toplevel`, bypassing the apps list and that policy with it. It is
the same split nixpkgs makes: permissive about `allowUnfree`, strict about
what Hydra serves.

## Proposed outcome

- `cache-budget.sh` passes on `main` and on #719, without the budget moving.
- Nothing prebuilt is pushed to `nixarchy.cachix.org`: not the AI CLIs, not
  `zen-browser`. What is pushed is what a user would otherwise compile.
- The allowlist states the criterion, so the next addition is judged by it
  rather than by whether it happens to fit.
- `allowUnfree` remains on by default and the manual says so plainly, so a
  user knows their machine installs proprietary packages. That is a statement
  about their machine, not a licence to redistribute, and the two stay
  separate.

Measured target, from the failing run's own per-path figures:

```
2234 - 442 (claude-agent-acp) - 394 (zen) - 208 (claude-code) = 1190 MiB
```

under the unchanged 2048 budget with #719's 184 MiB included.

## Affected users and systems

- `.github/scripts/cache-allowlist.sh` — the `apps` group has no per-app
  opt-out today, so one is needed.
- `data/apps.nix` — where that opt-out is declared.
- Whatever puts `claude-agent-acp` and `claude-code` into the system closure
  (entered via #713's nixi 0.10 pin); `reference-toplevel` is what an offline
  install copies, so this is also ~650 MiB of every installed machine.
- `docs/manual/` — the unfree statement.
- Users enabling `zen-browser` or the AI CLIs: they fetch from the vendor
  instead of from `nixarchy.cachix.org`. Both are prebuilt, so this is a
  download either way, not a compile.

## Constraints

- **The budget does not move.** Raising `CACHE_BUDGET_MIB` is the fix this
  intent exists to reject; if the work ends up needing it, that is a new
  decision and needs its own reasoning, not a quiet edit.
- **No unfree binary is pushed to the public cache.** Independent of size.
- `allowUnfree` default-on is unchanged. This work must not alter what a user
  can install, only what this project hosts.
- Offline install must keep working: `reference-toplevel` is copied by it, so
  anything removed from that closure must be something an offline machine does
  not need at install time.
- `build.yml` is a CI gate (AGENTS.md §11) — proposed by this branch, merged
  by a human.

## Decisions (approved by @olafkfreund, 2026-09-16)

1. **opencode is the default agent.** nixarchy installs it by default; claude,
   codex and the others stay installable from the Install menu and selectable
   as `defaultAgent`, which `modules/apps.nix:1064` already does.

   This is cheaper than it looks. `nixi`'s home module pins an ACP adapter per
   agent, and opencode **speaks ACP itself** — no adapter package. opencode is
   also free, so `cache.nixos.org` serves it and it costs this budget nothing.

2. **`zen-browser` comes off the cache.** 394 MiB, a `-bin-` package; its users
   fetch the same binary from the vendor.

3. **Do what is needed to make it work now.** The mechanical enforcement of the
   prebuilt criterion is desirable but not a blocker; it is carried as
   follow-up unless it turns out to be cheap in the same change.

## The cause, traced

`modules/nixos.nix:795` sets `allowUnfree = true` by default. `nixi`'s
`agents` option (`nix/hm-module.nix:73`) defaults to

```nix
lib.optional (pkgs.config.allowUnfree or false) "claude" ++ [ "codex" ]
```

so on nixarchy it evaluates to `[ "claude" "codex" ]`, pinning
`claude-agent-acp`, which depends on the unfree `claude-code`. That is the
650 MiB, and `modules/home.nix:561` turns nixi on by default for every user.

Worth stating plainly, because it bears on how `allowUnfree` gets discussed:
the flag is not a neutral permission. Setting it changes what lands in the
closure, in every installed machine, and in a public cache. Documenting that
unfree is allowed tells a user what their machine installs; it does not make
hosting those binaries someone else's decision.

## Open questions

None. The three above are settled.
