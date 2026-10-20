---
status: approved
issue: 1386
intent: intent/2026-10-20-1386-agent-account-wrappers.md
---

# Spec: on edge, `omarchy agent account use` changes the account that the next `claude`, `codex` or `grok` actually runs as

Decided in the intent:
- launchers route through the selected account too;
- no mise install in place of Nix;
- a stubbed check, not a VM.

All of it is on `edge-candidate` (quattro 0a7beb7). `main`'s Omarchy has
none of these commands.

## What research changed

- **The launchers already work.** Quattro's `bin/omarchy-agent`, the
  command behind the agent keybinding and menu, resolves the account
  itself. It runs `omarchy-agent-account-home "$agent"` and prefixes the
  command with `env CLAUDE_CONFIG_DIR=… OMARCHY_AGENT_CLAUDE_HOME=…`. It
  "carries the new pin in the command, since terminals launched through uwsm
  don't inherit our env". That path never touches the mise wrappers. So
  decision 1 needs no code, only a case in the check that proves it.
- **The mise fallback is never right here for these three.** Edge's
  `nix-bin/omarchy-default-agent` maps claude → `claude-code`, codex →
  `codex` and grok → `grok-cli`, all from nixpkgs.
  `omarchy-agent-account-exec` only reaches `mise install` / `mise use -g`
  when `type -P` finds no binary. For these three that means nixarchy chose
  not to install one, for example with unfree packages off.
- **All 12 `omarchy-agent-account-*` commands ship verbatim.** None has a
  row in edge's `data/bin-ledger.nix`.

## Design

### 1. The wrappers file is installed

In `edge-candidate`'s `data/etc-overlay.nix`, the
`mise/conf.d/omarchy-agent-accounts.toml` row goes from `divergent` to
`installed`. `modules/nixos.nix` already installs every `installed` row
through `environment.etc`, as it does for `mise/conf.d/omarchy.toml`
(#649), so `/etc/mise/conf.d/omarchy-agent-accounts.toml` is the shipped
file. The new reason:

> mise `[wrappers]` routing claude, codex and grok through
> `omarchy-agent-account-exec`, so `omarchy agent account use` reaches a
> CLI started in a terminal. nixpkgs' mise reads `[wrappers]` (2026.10.3,
> measured). The launchers resolve the account themselves. The exec's mise
> install fallback is patched to refuse (#1386).

In an activated shell, mise puts `command-wrappers/bin` ahead of
`/run/current-system/sw/bin` (measured), so a typed `claude` reaches the
wrapper. The exec strips the wrapper dirs, `type -P` finds the Nix binary,
and it runs with the selected account's home.

### 2. The exec's mise fallback refuses

In `pkgs/omarchy/default.nix` (edge), one `substituteInPlace --replace-fail`
on `bin/omarchy-agent-account-exec` replaces the body of
`if ! agent_binary=$(type -P "$provider"); then … fi` (from
`export MISE_MINIMUM_RELEASE_AGE=0` to `agent_binary=$(mise which
"$provider")`) with:

```bash
echo "$provider is not installed. nixarchy installs it through Nix: omarchy default agent $provider" >&2
exit 127
```

It is placed next to the existing `omarchy-agent` patch (~:1215), with a
one-line comment pointing at `omarchy-default-agent`'s reasoning.
`data/bin-ledger.nix` gains a `patch` row for it, which
`check-bin-ledger.py` requires. Exit 127 is what a missing command already
returns, so what a user sees matches today's "command not found".

### 3. Launchers: unchanged

Nothing to change: `omarchy-agent` already does this (see above). The check
proves it.

## Coexistence (§14)

- **A user's own `[wrappers.claude]`** in `~/.config/mise/` or a project
  `mise.toml` overrides the system file. That is mise's config precedence,
  and upstream's comment relies on it. Proved by a check case.
- **An explicit `CLAUDE_CONFIG_DIR` / `CODEX_HOME` / `GROK_HOME`** wins over
  the selection. The exec only sets them when they are empty.
- **A user without mise activation** (no `mise activate` in their shell)
  gets no wrapper, so a typed `claude` runs as before. The launchers still
  follow the selection. That is upstream's behaviour too.
- **Mode A:** the file is installed only where the overlay's `installed`
  rows are, and that is edge's `modules/nixos.nix` path. A machine not on
  edge is untouched.

## Alternatives rejected

- **A Nix wrapper around the `claude-code` / `codex` / `grok-cli`
  packages** that calls the exec. It works without mise activation, but it
  shadows the package for everyone, Mode A included. It also diverges from
  how upstream routes, and duplicates what the launchers already do.
- **Leaving the fallback as upstream wrote it:** a mise download of an
  unfree CLI that nixarchy deliberately did not install (intent decision 2).
- **Patching `omarchy-agent` as well:** not needed, it already pins the
  account.

## Risks

- **Every typed `claude` now goes through a wrapper, a shell script and a
  `omarchy-agent-account-home` lookup.** If `omarchy-agent-account-home`
  fails, the exec runs under `set -euo pipefail` and dies before the agent
  starts. Upstream ships it this way. The check covers a user with no
  accounts at all (implicit Main), the case every existing user is in.
- **mise must have reshimmed** for `command-wrappers/bin/claude` to exist.
  `mise hook-env` / `mise reshim` create it. Whether an activated shell on a
  fresh login creates it without a manual `mise reshim` is checked in the
  `runCommand` with `hook-env` only, then confirmed on p620.
- **Promotion is outward-facing.** Edge users get this when an
  `omarchy-edge` dispatch with `from_candidate` passes. That dispatch is
  run only with your go-ahead.

## Verification (§1)

`checks.agent-account-routing`, edge only: a `runCommand` with the shipped
Omarchy tree, nixpkgs' mise, the installed toml as
`MISE_SYSTEM_CONFIG_DIR`, and a stub `claude` that prints
`$CLAUDE_CONFIG_DIR`. State is under a temporary `HOME`/`XDG_*`; per §4 the
check moves `XDG_*` too, not just `HOME`. Cases:

1. Add an account `work` with the shipped `omarchy-agent-account-add`, then
   `omarchy-agent-account-use claude work`. In a `hook-env`-activated bash,
   `claude` prints work's home.
   **Red:** without the toml, it prints the empty default.
2. No accounts (implicit Main): `claude` runs, and prints what
   `omarchy-agent-account-home claude` returns.
3. A user `[wrappers.claude]` pointing at `echo USER` wins.
4. No `claude` on PATH: the exit is 127 with the nixarchy message, and
   nothing appears under mise's installs.
   **Red:** the unpatched exec reaches `mise install` (it fails offline in
   the sandbox, with a different message).
5. `omarchy-agent --inline` with `omarchy-default-agent` stubbed to
   `claude` prints work's home. This is the launcher path, with no wrapper
   involved.

Notification and usage side effects of `use` are stubbed
(`omarchy-notification-send`, `omarchy-agent-usage-update`).

Then, after a `from_candidate` dispatch you approve, on p620 on edge: in a
fresh terminal, `omarchy agent account use claude <second account>`, then
`claude` shows that account's login.
