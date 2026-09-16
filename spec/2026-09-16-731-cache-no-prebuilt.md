---
status: approved
issue: 731
intent: intent/2026-09-16-731-cache-no-prebuilt.md
---

# Spec: the cache carries nothing prebuilt

Closes #731.

Carrying the approved decisions: the adapter is pinned **where Claude is
used**, the nixi pin is bumped in this change, and `codex` stays pinned.

## Design

### 1. The agent set follows the machine's own choice (`modules/home.nix`)

```nix
services.nixi.agents =
  [
    "opencode"
    "codex"
  ]
  ++ lib.optional (appEnabled "claude-code" || defaultAgent == "claude") "claude";
```

Both accessors already exist in that file and are already used this way:
`defaultAgent` (line 42) and `appEnabled` (line 72), each reading `osConfig`
with an `or` default so a standalone Home Manager user evaluates.

**Why the machine can answer this at build time.** A menu pick runs
`omarchy-default-agent`, which calls `nixarchy-pkg-add claude-code`, which
writes `~/.config/nixarchy/apps.nix` -- a declarative file the user's flake
imports, surfacing as `programs.nixarchy.apps.claude-code.enable`. So "is this
machine using Claude" is a configuration question, not a runtime one, and no
migration or activation script is needed to answer it.

**Why both halves of the condition.** `appEnabled` catches the menu-chooser,
whose `~/.config/omarchy/defaults/agent` says `claude` and whose nixi would
otherwise throw -- nixi-nixarchy#13's fallback deliberately does not override an
explicit choice. `defaultAgent == "claude"` catches the declarative user, whose
`modules/apps.nix` mapping installs `claude-code` without going through the apps
catalogue at all.

**Unfree stays consistent.** `claude-code` is `unfree = true` in
`data/apps.nix`, so a machine cannot enable it without `allowUnfree`; and
`claude-agent-acp` throws under `allowUnfree = false` (measured 2026-09-16). The
condition therefore cannot pin an adapter on a machine that refuses unfree,
because the thing it keys on cannot be enabled there either.

### 2. `attr_for` is NOT changed

The issue proposed teaching `omarchy-default-agent` to install
`claude-agent-acp` beside `claude-code`. Section 1 removes the need: enabling
`claude-code` is what pins the adapter, through the existing menu flow,
unchanged. Stated here because "we decided not to" is worth a line -- the next
reader will otherwise wonder why the obvious edit is missing.

### 3. The nixi pin moves to `1a7f9cbb` (`flake.nix:148`)

nixi-nixarchy#13. Its fallback picks the first agent whose adapter resolves
rather than the literal name `claude`, so a machine with **no** recorded choice
-- a missing or unreadable defaults file -- also lands on something startable
instead of erroring on an adapter this change no longer pins by default.

Section 1 already covers every machine that HAS chosen. This covers the one that
has not, and it is why the two were reasoned about together.

## Alternatives rejected

- **Default `programs.nixarchy.defaultAgent = "opencode"`** (the issue's own
  proposal). The option is `null` deliberately: its description says it is
  *authoritative on the next activation*, so giving it a default would make the
  configuration authoritative for everyone and a menu click would stop surviving
  a rebuild. That is the workflow the owner's constraint protects.
- **An activation-time migration** that detects `defaults/agent == claude` and
  installs the adapter. Reads runtime state to decide a closure, which Nix
  cannot do before the closure exists, and leaves a machine broken between the
  rebuild and the next activation.
- **Drop `claude` unconditionally and tell people to re-pick it.** The
  constraint the owner added rules it out: a machine using Claude keeps using
  Claude with no action from its owner.
- **Raise `CACHE_BUDGET_MIB`.** Rejected once in #725 and rejected again here:
  the tier is not the constraint, the contents are.

## Risks

- **The condition is the whole change.** If `appEnabled "claude-code"` is ever
  false on a machine that is in fact using Claude, that user's nixi breaks and
  nothing tells them until they press SUPER+H. The verification below asserts
  the true case as well as the false one, because only asserting "the default
  machine has no claude" would pass with the condition hard-coded to `false`.
- **Mode A.** `tests/options.nix` asserts every option in both states, and the
  off state is the one a refactor breaks quietly.
- **`reference-toplevel` changes**, so the ISO's baked closure changes. The
  budget moves down, so the risk is a stale assertion rather than an overflow;
  `install-iso` and `iso-budget` are nightly-only.
- **The nixi bump carries everything else on that branch**, not only #13. It is
  one commit ahead (`6d32459` was documentation; `1a7f9cbb` is the fix), so the
  surface is small, but it is a flake input moving and deserves saying.
- **A machine that enables `claude-code` now pays 651 MiB** it may not have
  paid before if it had `allowUnfree` on but never chose Claude. That is the
  trade working as intended -- the cost follows the choice -- but it is a
  closure growing for somebody, not only shrinking.

## Verification

1. **`checks.options`**, the load-bearing one. Four cases, and the pair matters:
   - a default machine: `agents == [ "opencode" "codex" ]`, no `claude`;
   - a machine with `programs.nixarchy.apps.claude-code.enable = true`:
     `agents` contains `claude` -- **this is the owner's constraint as a
     check**, and without it the condition could be hard-coded to `false` and
     still pass;
   - a machine with `defaultAgent = "claude"`: same;
   - `allowUnfree = false` still evaluates.
2. **The budget, measured.** `cache-budget.sh` on the PR: expect roughly
   **971 MiB** of an unchanged 2048, down from 1622. A number near 1622 means
   the adapter is still in a pushed closure and the change did not work.
3. **Absence and presence in the closure**, rather than inferred from one total:
   `claude-agent-acp` and `claude-code` absent from `checks.reference-toplevel`
   and `checks.vm-toplevel`; `opencode` present.
4. **Watch it fail** (AGENTS.md §1): flip the condition to `false` in one tree,
   confirm the apps-enabled case goes red, restore. Prove the break landed with
   `git diff` before believing the red -- a silent no-op break and a blind check
   read the same from an exit status.
5. `nix fmt -- --ci`, `statix`, `deadnix`.

Not attempted: a booted desktop actually launching nixi with each agent. That is
`checks.session` territory and it cannot vary the variable this change touches
(AGENTS.md §3) -- what is pinned is a property of the closure, not of a running
card.
