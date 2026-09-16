---
status: approved
issue: 731
author: olafkfreund
---

# Intent: the cache carries nothing prebuilt, and Claude brings its adapter

Closes #731.

## Problem

### 1. 42% of a public cache is two packages nobody builds

Measured on `main` by CI after #726 — 1622 MiB of a 2048 MiB budget, of which:

```
442.4 MiB  claude-agent-acp      prebuilt binary   <- fetched, not built
208.5 MiB  claude-code           prebuilt binary   <- fetched, not built, UNFREE
393.9 MiB  qemu-for-vm-tests     custom variant    <- a real compile
124.4 MiB  omarchy               assembled here    <- real
101.3 MiB  index-x86_64-linux    generated         <- real
```

`nixarchy.cachix.org` exists so a user does not have to BUILD what is expensive
to build. Hyprland — the reason it was created — is served by
`hyprland.cachix.org` and subtracted by `cache-budget.sh`, so it has not been in
this budget for some time. What is in it instead is 651 MiB of binaries that
Anthropic ships prebuilt: caching them makes this project a slower second mirror
for bytes the user fetches from the vendor either way.

`cache-allowlist.sh` already refuses to push unfree apps, and says why:

> this cache is public, and pushing a proprietary binary to it is
> redistributing it. Its users build it, as nixpkgs' do.

`claude-code` is `unfree = true` in `data/apps.nix`, and reaches the cache
inside `vm-toplevel` rather than through the apps list — so it bypasses that
policy rather than being exempted from it.

Dropping both takes the allowlist to **~971 MiB**, which is **5.3 in-flight
commits inside the 5 GB tier instead of 3.2**. The tier is not the constraint;
the contents are.

### 2. Choosing Claude in nixi does not work, today, on `main`

Independent of the cache, and live right now.

`omarchy-default-agent` maps the menu pick to a package:

```sh
attr_for() { case "$1" in claude) echo claude-code ;; ... }
```

and installs it with `nixarchy-pkg-add`. **`claude-code` is not
`claude-agent-acp`** — separate packages, and nixi needs the *adapter*. So a
user who picks Claude gets the CLI, `~/.config/omarchy/defaults/agent` records
`claude`, and nixi fails looking for an adapter nobody installed.
`programs.nixarchy.defaultAgent = "claude"` has the same hole:
`modules/apps.nix` maps it to `pkgs.claude-code`, with no adapter.

This is masked today only because `services.nixi.agents` pins the adapter
whenever `allowUnfree` is on. Fixing 1 without fixing this turns a corner case
into the common path, so they belong in one change.

## Proposed outcome

- Nothing prebuilt is pushed to `nixarchy.cachix.org`. What is pushed is what a
  user would otherwise compile.
- A default desktop still gets a working nixi card, out of the box, offline,
  with nothing unfree in its closure.
- A user who wants Claude picks it — from the Install menu or in the
  configuration — and it **works**, adapter included.
- `cache-budget.sh` reports roughly **971 MiB** of an unchanged 2048.

## Affected users and systems

- `modules/home.nix` — `services.nixi.agents`.
- `pkgs/omarchy/nix-bin/omarchy-default-agent` and `modules/apps.nix` — the two
  routes that install an agent, both of which must install its adapter.
- `flake.nix` — the nixi pin, if decision 1 below goes that way.
- `tests/options.nix` — both agent states and both `allowUnfree` states.
- Every user: what a default machine ships, and what happens when they choose
  Claude. This is the only change in today's run that a user notices.

## Constraints

- **`allowUnfree` stays on by default**, and this must not change what a user
  can install — only what this project hosts and what a default closure carries.
- **`CACHE_BUDGET_MIB` does not move.** If the work ends up wanting it, that is
  a new decision with its own reasoning (#725 rejected it once already).
- **Mode A**: someone importing `nixosModules.nixarchy` into their own
  configuration must be untouched by anything opt-in, and `tests/options.nix`
  asserts every option in both states — the off state is the one a refactor
  breaks quietly.
- **A menu click must keep working.** `omarchy-default-agent` writes
  `~/.config/omarchy/defaults/agent` at runtime and that has to keep taking
  effect immediately.
- No unfree binary is pushed to a public cache.

## Constraint added by the owner, 2026-09-16

**A user who has already chosen an agent must not lose it.** Not at the upgrade,
not silently, and not with a "re-pick it from the menu" instruction. Whatever
this change does to the default set, a machine that is using Claude today keeps
using Claude with no action from its owner.

That rules out the shape I first proposed, and it rules it out for a reason I
had missed rather than the one I raised. The user at risk is not the one with
`defaultAgent` set -- it is the one who picked Claude **from the Install menu**.
Their `~/.config/omarchy/defaults/agent` says `claude`, which is an EXPLICIT
choice, and nixi-nixarchy#13's new fallback deliberately does not override an
explicit choice: it throws. Dropping the adapter from `agents` would break
exactly those people, and the nixi fix does not catch them by design.

## Decision: pin Claude's adapter when the machine is using Claude

The machine already knows. A menu pick runs `nixarchy-pkg-add claude-code`,
which writes `~/.config/nixarchy/apps.nix` -- declarative, persistent, and read
at build time as `programs.nixarchy.apps.claude-code.enable`. `modules/home.nix`
has the accessor for it already (`appEnabled`, line 72), beside the one for
`defaultAgent` (line 42).

```nix
services.nixi.agents =
  [ "opencode" "codex" ]
  ++ lib.optional (appEnabled "claude-code" || defaultAgent == "claude") "claude";
```

| machine | claude pinned? |
|---|---|
| `checks.vm-toplevel`, `checks.reference-toplevel` | no -- **the 651 MiB leaves the cache** |
| a user who picked Claude from the menu | **yes** -- `claude-code` is in their apps.nix |
| `programs.nixarchy.defaultAgent = "claude"` | yes |
| a user who has never asked for Claude | no |

Nobody is asked to do anything. The adapter arrives exactly where Claude is
wanted, and the closures CI pushes are the ones that never wanted it.

**It also settles open question 2 without any code.** The issue proposed
teaching `attr_for` to install `claude-agent-acp` beside `claude-code`. That is
now unnecessary: enabling `claude-code` is what pins the adapter, through the
existing menu flow, unchanged. One expression replaces two edits and a
migration.

**And it leaves `defaultAgent` alone**, so the option stays `null` by default and
authoritative only when someone sets it -- a menu click still wins, which is the
behaviour its description promises and the constraint above protects.

## Decisions (approved by @olafkfreund, 2026-09-16)

1. **The nixi pin is bumped to `1a7f9cbb` in this change**, so a machine with a
   missing or unreadable defaults file also lands on a startable agent. Both
   halves were reasoned about together and land together.
2. **`codex` stays pinned.** Apache-2.0, cost under 51.8 MiB or zero.

## Answered

1. **Bump the nixi pin to `1a7f9cbb` in this change, or separately?** It is not
   required -- the decision above covers every machine that has chosen an agent,
   and a machine that has chosen none has opencode and codex pinned for nixi to
   find. The pin bump adds the fallback that makes a *missing* defaults file
   safe too. In this change it is one line and one lock entry; separately it is
   a routine bump. I lean including it, since the two were reasoned about
   together.

2. **Does `codex` stay pinned?** Apache-2.0, absent from the failing run's top
   ten, so its cost is under 51.8 MiB or zero. Assumed yes unless you say
   otherwise.
