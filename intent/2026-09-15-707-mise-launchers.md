---
status: approved
issue: 707
author: olafkfreund
---

# Intent: first login stops installing mise launchers that shadow Nix agents

## Problem

On first login, upstream's `install/user/mise.sh` writes mise launchers into
`~/.local/bin` for 13 tools: codex, claude, crush, gemini, gh, copilot,
opencode, playwright, pi, omp, grok, ghui and hunk. `~/.local/bin` comes before
`/etc/profiles/per-user/$USER/bin` on PATH, so each launcher shadows the Nix
package of the same name.

As a result:

- The Nix package never runs. On p620 `codex` was mise's 0.150.1, while the
  flake shipped 0.154.0, and a flake update never changes what runs.
- The upstream binaries lack nixpkgs' wrapping. Codex warns on every start that
  bubblewrap is missing.
- Removing a launcher does not last. Each launcher runs `mise use -g` again,
  and `omarchy-refresh-applications` re-runs `mise.sh`.

The chain is `omarchy-provision-user` → `install/user/all.sh` →
`install/user/mise.sh`, plus `omarchy-refresh-applications` → `mise.sh`.

## Proposed outcome

- **Fresh install:** after first login, no mise launcher in `~/.local/bin`
  shadows a tool that nixarchy or nixpkgs provides. `codex`, `claude` and the
  rest resolve to the Nix packages and update with the flake.
- **`omarchy-refresh-applications`:** running it does not bring the launchers
  back.
- **Tools nixpkgs lacks:** open question 1 decides whether they keep a mise
  route.
- **Regression check:** a check fails if a shadowing launcher reappears.

## Affected users and systems

- Every nixarchy desktop, at first login and on each run of
  `omarchy-refresh-applications`.
- `pkgs/omarchy/default.nix`, the vendored-tree patches.
- `checks.session`, or a cheaper check if one can see it.
- Existing machines already have the launchers.

## Constraints

- Patch the vendored tree the way the other `install/user/*` scripts are
  patched. Upstream's Arch behaviour is correct on Arch, so this is not an
  upstream fix.
- The `omarchy-default-agent` mise shim path must keep working for agents
  installed through mise on purpose.
- The check must be seen red first (AGENTS.md §1).
- Mode A: nothing changes for a host that imports the module without enabling
  it.

## Open questions

Resolved at approval (the owner accepted the recommendations):

1. **Tools nixpkgs lacks:** keep the mise route only for tools nixpkgs does not
   package (omp, ghui, hunk, muse). Drop it for everything nixarchy or nixpkgs
   provides.
2. **Existing machines:** activation removes existing launchers that shadow a
   Nix-provided tool, because otherwise the fix never reaches a machine that is
   already installed.
