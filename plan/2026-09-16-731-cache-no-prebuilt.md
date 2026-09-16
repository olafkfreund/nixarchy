---
status: draft
issue: 731
spec: spec/2026-09-16-731-cache-no-prebuilt.md
---

# Plan: the cache carries nothing prebuilt

Closes #731.

## The approved decisions, carried over

Self-contained.

`claude-agent-acp` (442 MiB) and the unfree `claude-code` (208 MiB) are **651 MiB
— 42%** of what `nixarchy.cachix.org` holds, and neither is a build: both are
fetched from Anthropic and wrapped. Dropping them from the closures CI pushes
takes the allowlist from **1622 MiB to roughly 971**, and the 5 GB tier from 3.2
in-flight commits to 5.3.

**The owner's constraint: a machine that is using Claude today keeps using it,
with no action from its owner.** The user at risk is the menu-chooser, whose
`~/.config/omarchy/defaults/agent` says `claude` — an explicit choice, which
nixi-nixarchy#13's fallback deliberately does not override.

The machine already records that choice declaratively: a menu pick runs
`nixarchy-pkg-add claude-code`, which writes `~/.config/nixarchy/apps.nix`,
surfacing at build time as `programs.nixarchy.apps.claude-code.enable`. So the
adapter can be pinned exactly where Claude is wanted.

Decisions: the nixi pin is bumped in this change; `codex` stays pinned;
`attr_for` is deliberately **not** touched; `CACHE_BUDGET_MIB` does not move.

## Steps

1. **`modules/home.nix`** — replace the unconditional agent list with:

   ```nix
   services.nixi.agents =
     [
       "opencode"
       "codex"
     ]
     ++ lib.optional (appEnabled "claude-code" || defaultAgent == "claude") "claude";
   ```

   Plain assignment stays (AGENTS.md §7: `mkDefault` on a list is dropped whole
   the moment a user adds an element). Extend the comment block already there
   from #726 — it currently explains why the set is named rather than inherited;
   it now also has to say why claude is conditional, naming the menu-chooser as
   the person the condition exists for.
   → verify: step 1 of Tests.

2. **`flake.nix:148`** — nixi pin `569adeaa…` → `1a7f9cbb…`, and update the
   comment beside it to name what the bump is for. `nix flake lock --update-input
   nixi` for the lock entry.
   → verify: `nix flake metadata` shows the new rev; `checks.options` still
   evaluates.

3. **`tests/options.nix`** — two cases, using **`homeOn`, never `homeWith`**.
   `homeWith` passes `osConfig = null`, so `appEnabled` and `defaultAgent` are
   both inert and every case would return `[ "opencode" "codex" ]` — a check
   that cannot vary with the thing it is written for (AGENTS.md §3).

   ```nix
   nixiPinsClaudeWhenTheMachineUsesIt = {
     on  = elem "claude" (homeOn { apps.claude-code.enable = true; } { }).services.nixi.agents;
     off = elem "claude" (homeOn { } { }).services.nixi.agents;
   };
   nixiPinsClaudeForADeclaredDefaultAgent = {
     on  = elem "claude" (homeOn { defaultAgent = "claude"; } { }).services.nixi.agents;
     off = elem "claude" (homeOn { } { }).services.nixi.agents;
   };
   ```

   **Assert on the option, never on the package.** `checks.options` runs with
   `pkgsFor`, which sets no `allowUnfree`, so forcing `nixiPkg` — and with it
   `pkgs.claude-agent-acp` — would throw and take the whole check with it. The
   `agents` option is a list of strings and forces nothing.
   → verify: `nix build .#checks.x86_64-linux.options`.

4. **Formatting and lint.** `nix fmt -- --ci`, `statix check .`,
   `deadnix --fail .`.
   → verify: clean. Edit `.nix` through Bash, not the Edit tool — the local
   `PostToolUse:Edit` formatter rewrote 204 unrelated lines of this same file on
   2026-09-16 and the churn had to be reverted.

## Tests

1. **`checks.options`** — the load-bearing one.
   ```sh
   nix build .#checks.x86_64-linux.options --print-build-logs
   ```
   Both new cases must pass, and the framework already requires `on && !off`, so
   each asserts the true half and the false half in one row.

2. **Watch it fail** (AGENTS.md §1), in one tree (§5 — never across commits):
   flip the condition to `false`, rebuild `checks.options`, confirm
   **`nixiPinsClaudeWhenTheMachineUsesIt`** goes red, restore.
   ```sh
   git diff --stat        # prove the break landed before believing the red
   ```
   A silent no-op break and a blind check are indistinguishable from an exit
   status. Capture the failing output for the PR.

3. **The budget, measured.** Nothing in flight first (§6 — the runners and this
   shell are all on p620):
   ```sh
   gh run list --limit 8 --json status -q '[.[]|select(.status!="completed")]|length'
   CACHE_BUDGET_MIB=2048 .github/scripts/cache-budget.sh
   ```
   Expect roughly **971 MiB of 2048**, down from 1622. **A number near 1622
   means the adapter is still in a pushed closure and the change did not work** —
   report it rather than explaining it.

4. **The closure, directly** — presence as well as absence, so neither is
   inferred from one total:
   ```sh
   nix path-info -r .#checks.x86_64-linux.reference-toplevel | grep -E 'claude|opencode'
   ```
   Expect `opencode`, expect no `claude-agent-acp` and no `claude-code`. Do not
   send stderr to `/dev/null`: a failed `path-info` and an empty match look
   identical, which cost an hour on 2026-09-16.

5. `nix fmt -- --ci`, `statix`, `deadnix`.

Not attempted: `checks.session`. A booted desktop cannot vary what is pinned into
a closure (§3), and saying so is worth more than a check that looks like it
covers it.

## Rollback

- **A machine loses Claude anyway** → revert step 1. The agent set returns to
  `[ "opencode" "codex" "claude" ]`, the adapter comes back everywhere, and the
  cache returns to 1622 MiB — safe, and the only rollback that is urgent, since
  it is the one the owner's constraint is about.
- **The nixi bump misbehaves** → revert step 2 alone. Step 1 does not depend on
  it; it only covers the machine that has chosen nothing.
- **Whole change** → `git revert` the implementation commit. Nothing is stateful
  and nothing is deleted from the cache, so reverting changes only what future
  pushes contain.
