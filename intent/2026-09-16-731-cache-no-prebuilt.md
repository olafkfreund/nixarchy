---
status: draft
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

## Open questions

1. **How does a default desktop get a working agent — the nixi fallback, or an
   authoritative `defaultAgent`?** This is the real decision, and #731's
   original proposal now looks wrong to me.

   The issue proposed defaulting `programs.nixarchy.defaultAgent` to
   `"opencode"`. Reading the option, that has a cost I had not seen: it is
   `null` today *deliberately*, and its description says the option **is
   authoritative on the next activation**. Giving it a default makes the
   configuration authoritative for everyone — so a user who picks Claude from
   the Install menu would silently lose it at the next rebuild. That is a
   regression in exactly the workflow the constraint above protects.

   The alternative only became available tonight: nixi-nixarchy#13 merged, and
   nixi now falls back to the first agent whose adapter actually resolves
   instead of the literal name `claude`. So bumping the nixi pin to `1a7f9cbb`
   and dropping `claude` from `agents` may be sufficient on its own — a default
   desktop gets opencode because that is what is pinned, a menu click still
   wins, and `defaultAgent` stays `null` and authoritative only when set.

   - **A.** Bump the pin, drop claude from `agents`, leave `defaultAgent` alone.
     Smallest surface, keeps the menu semantics, depends on the new nixi.
   - **B.** Default `defaultAgent = "opencode"`. Works without the pin bump,
     costs the menu-click-survives-rebuild behaviour for everyone.
   - **C.** Both, as belt and braces — at the same cost as B.

   I lean **A**. It is also the only one whose failure mode is "an older nixi
   pin behaves as it does today" rather than "a user's menu choice vanished".

2. **Where does the adapter get installed from — the menu, the option, or
   both?** `attr_for` returning two packages is the smaller change;
   `modules/apps.nix`'s `defaultAgent` mapping needs the same treatment either
   way, or the declarative route stays broken while the menu is fixed.

3. **Does `codex` stay pinned?** It is Apache-2.0 and did not appear in the
   failing run's top ten, so its cost is under 51.8 MiB or zero. Keeping it is
   nearly free; dropping it would make opencode the only pinned agent and the
   set less useful. I assume it stays unless you say otherwise.
