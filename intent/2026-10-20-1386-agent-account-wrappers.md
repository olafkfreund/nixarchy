---
status: approved
issue: 1386
author: olafkfreund
---

# Intent: on edge, `omarchy agent account use` changes the account that the next `claude`, `codex` or `grok` actually runs as

## Problem

Omarchy's `quattro` branch, which nixarchy's edge channel tracks, adds
subscription accounts for the three agent CLIs. There are 12
`omarchy-agent-account-*` commands. `omarchy agent account use work`
records the choice and says "New Claude sessions now use work".

The choice only takes effect when the CLI is started through
`omarchy-agent-account-exec`. That command sets `CLAUDE_CONFIG_DIR`,
`CODEX_HOME` or `GROK_HOME` to the chosen account's home, then execs the
real binary. Upstream routes every `claude`, `codex` and `grok` through it
with mise wrappers, in `etc/mise/conf.d/omarchy-agent-accounts.toml`:

```toml
[wrappers.claude]
command = "omarchy-agent-account-exec"
args = ["claude"]
```

On edge that file is not installed. Its row in `data/etc-overlay.nix`
(on `edge-candidate`) is `divergent`, and points here. So **on nixarchy
edge the account commands report a switch that never happens**: `claude`
runs the Nix-installed binary with its default home, whichever account was
chosen. Nothing fails, so the only symptom is being logged in as the wrong
account.

Stable (Omarchy 4.0.6, `main`) ships none of these commands, so this is
edge-only until a stable release carries them.

### Measured on 2026-10-20

- **nixpkgs' mise (2026.10.3) reads `[wrappers]`.** In a scratch config,
  `mise reshim` created `command-wrappers/bin/fakeagent`, and an activated
  bash ran it (`fakeagent hi` printed `WRAPPED hi`).
- **In an activated shell the wrapper wins.** `mise hook-env` puts
  `command-wrappers/bin` ahead of `/run/current-system/sw/bin`, so a `claude`
  typed in a terminal would reach the wrapper before the Nix binary.
  nixarchy's bash activates mise (`modules/nixos.nix` ~:740).
- **The exec script then finds the Nix binary.** mise strips its wrapper
  directories before calling it, and it resolves `claude` with `type -P`.
  That is read from the script, not run.

## Proposed outcome

On edge:

- `omarchy agent account use <account>` changes which account the next
  `claude`, `codex` or `grok` runs as, in a terminal and from Omarchy's own
  launchers. Running sessions stay where they are, as upstream intends.
- A user who never adds a second account sees no change: the implicit Main
  account is their existing home.
- Nothing is downloaded by mise in place of a Nix package.

## Affected users and systems

- Edge-channel users who use more than one Claude, Codex or Grok account.
- `edge-candidate`: the `mise/conf.d/omarchy-agent-accounts.toml` row in
  `data/etc-overlay.nix`. If that row becomes `installed`,
  `modules/nixos.nix` installs the file at `/etc/mise/conf.d/`. Possibly the
  edge patches in `pkgs/omarchy/default.nix` too.
- `main` is untouched: its Omarchy has no file or command to route.

## Constraints

- **No mise download ahead of Nix.** If `type -P claude` finds nothing,
  `omarchy-agent-account-exec` runs `mise install` or `mise use -g`, for
  example on a machine with unfree packages off, where nixarchy installs no
  `claude`. `omarchy-tools.toml` is `divergent` precisely to avoid mise
  installing what `data/apps.nix` and #707 keep in Nix. That path is either
  closed or deliberately allowed, with the reason in the row.
- **Coexistence (§14).** User and project mise config can override these
  wrappers, as upstream's comment says. A user's own `[wrappers.claude]`
  must still win.
- **Edge only, through edge's carry.** The change lands on
  `edge-candidate`, not `main`.
- **§1:** the check must fail without the change. "The row's class
  changed" is not the property. The property is "an activated shell's
  `claude` gets the selected account's `CLAUDE_CONFIG_DIR`".

## Open questions

1. **Launchers outside an activated shell.** Hyprland binds and
   `omarchy-launch-*` start agents with the session PATH, which has no mise
   wrapper directory. `pkgs/omarchy/default.nix` ~:1184 already prepends mise
   shims in one launcher. Does the outcome need those launchers to route
   through the exec too, or is a terminal `claude` enough for now? I propose
   both, since a keybinding is how most people start an agent here, but it
   widens the change.
2. **Unfree off.** Should the wrapper simply not apply when nixarchy
   installs no `claude` (so `claude` stays "command not found", as today), or
   should upstream's mise install be allowed for that user? I propose not
   applying it: same reasoning as `omarchy-tools.toml`.
3. **The check's layer.** Is a stubbed `runCommand` (fake `claude` that
   prints `$CLAUDE_CONFIG_DIR`, real mise, the shipped toml) enough? Or does
   this need the edge `session` VM? I propose the stub. The VM adds only the
   launcher PATH question, which question 1 decides.

## Decisions (owner, 2026-10-20)

Approved with the proposals above:

1. Launchers route through the account too, not only a terminal `claude`.
2. No mise install in place of Nix: where nixarchy installs no agent, it
   stays "not installed".
3. A stubbed `runCommand` check, not a VM.
