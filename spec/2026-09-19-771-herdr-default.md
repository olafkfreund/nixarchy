---
status: approved
issue: 771
intent: intent/2026-09-19-771-herdr-default.md
---

# Spec: the herdr sessions widget ships with nixarchy and is on by default

## Design

This lands after #770, which adds the `packages` field to `defaultPluginSet`,
and after #766 PR B (#780), which adds the seed-bind block.

**D1. A non-flake input, wrapped by nixarchy.** The repo has no `flake.nix`, so
it is pinned as `nixarchy-herdr = { url = "github:olafkfreund/nixarchy-herdr/<rev>"; flake = false; };`
(no nixpkgs, so no `follows`). nixarchy builds it in a small `runCommand`,
re-exported as `packages.<sys>.nixarchy-herdr` so CI builds it:

- copy the tree without `intent/`, `spec/`, `plan/`, `tests/` and `preview.png`.
  The plugin validator refuses symlinks, so this is a plain `cp -r` with
  `--no-preserve=mode` plus `chmod +x bin/*`;
- keep `LICENSE`, which names **both** copyright holders (Jankees van Woezik
  and olafkfreund). The build fails if either name is missing from the output;
- run **`patchShebangs bin/`**. Both scripts start `#!/bin/bash`
  (`bin/herdr-sessions:1`). Today they run only because nixarchy turns envfs on
  by default (`modules/nixos.nix:1261`), and a user who turns envfs off would
  get a widget that silently runs nothing. Rewriting the shebang to the store
  path removes that dependency. The scripts are run directly by path
  (`HerdrModel.qml:147,228,544,788`; `Menu.qml:167`), so the shebang is the
  only interpreter lookup there is.

**D2. The entry.**
```
defaultPluginSet.herdr = {
  id = "nixarchy.herdr";
  src = self.packages.<sys>.nixarchy-herdr;
  packages = [ pkgs.herdr pkgs.jq pkgs.iproute2 ];
};
```
Plus `herdr = true` in the `defaultPlugins` default. The manifest is
`menu` + `bar-widget` with `defaultSection: "right"`, and the hook's `right`
agrees with it. `hyprctl`, `foot`/`xdg-terminal-exec` and `ssh` come from the
session nixarchy already builds, and are not added again.

**D3. nixpkgs' herdr (0.9.0 at the pin) is compatible, checked against the
binary.** The widget calls:
- `herdr session list --json`, `session stop` and `session delete`;
- `herdr --session <n>` and `--remote <host>`;
- `herdr api snapshot`;
- `herdr agent focus` and `agent prompt`;
- `herdr server`, matched as a process.

Every one of these is in `herdr --help`, `herdr session --help` (list, attach,
stop, delete), `herdr session list --help` (`--json`), `herdr api --help`
(snapshot) and `herdr agent --help` (focus, prompt) from
`/nix/store/…-herdr-0.9.0`.

The owner runs 0.9.1 from `github:ogulcancelik/herdr`. By the intent's decision
that input keeps priority on his machine: his `/etc/nixos` puts it in the
system profile, and the choice between the two is PATH order, which the plan
verifies on his host before merging. `herdr update` (the self-updater) cannot
write to the store. That is harmless and is noted in the docs.

**D4. Rows and binds.** In `modules/apps.nix` `overrideSpec`:
- `apps.herdr`, through `nixarchy-plugin nixarchy.herdr`;
- `learn.herdr-keybindings`, running
  `~/.config/omarchy/plugins/nixarchy.herdr/bin/herdr-menu-keys` (patched, so it
  runs without envfs).

Seed binds, appended to PR B's block for new installs only:
`SUPER + ALT + H` for the widget. The README's Super+Shift+H is not used, per
the intent. Super+Alt+H is free upstream and in nixarchy. On the owner's machine
`bindings.lua:317` binds Super+Shift+H and is not touched.

**D5. Upstream prerequisites (in the plugin repo, not filed by us).**
- **Delete asks first**, on key and on click (`Card.qml:97-99,629-639`), with the
  default on Cancel, as Kill already has.
- **Delete reports failure.** `bin/herdr-sessions:821` runs
  `herdr session delete "$name" >/dev/null 2>&1 || true` and prints success
  whatever happened. It should pass on the exit status and stderr.

The pin moves to a commit that has both. Until then this does not merge: the
intent makes these a condition of shipping as a default.

**D6. The owner's machine.** `~/.config/omarchy/plugins/nixarchy.herdr` is a
hand-copied checkout, and there is a leftover `.jankeesvw.herdr.bak.*` beside
it. The reconcile step refuses to replace an unmanaged directory, so the PR says
to remove it first. The plugin stays enabled in `shell.json`, and the hook
writes its marker because it is already on.

## Alternatives rejected

- **Upstream's herdr flake instead of nixpkgs:** that is a second nixpkgs in the
  lock and on the ISO for one binary. nixpkgs' 0.9.0 covers every call the
  widget makes (D3). The owner can keep his own input.
- **Adding a flake to the plugin repo first:** a better end state, but a
  `flake = false` input plus about ten lines of `runCommand` gets there now. If
  a flake lands, the pin switches with no change to behaviour.
- **Relying on envfs for the shebang:** it works today, but only because of a
  default a user can turn off. `patchShebangs` costs one line.
- **Carrying the Delete fix as a patch here:** it's the owner's repo. Fixing it
  upstream helps everyone who clones it.

## Risks

- **Polling while closed:** it polls every 20 s (`HerdrModel.qml:831`) for the
  badge. With herdr installed it is cheap, and it is a cost, not a hazard.
- **A herdr bump in nixpkgs could rename a subcommand**, and the widget would
  fail with "herdr is not installed" or an empty list rather than an error. The
  `menu-verbs` case below catches a rename at `nix flake update` time.
- **Kill sends SIGKILL** after SIGTERM, but it asks first with the default on
  Cancel, so that is unchanged and acceptable.
- **ISO:** herdr is a Rust binary of a few MiB; measured against `iso-budget`
  in the PR.

## Verification

Every check is proven red first (§1), with the break confirmed by `git diff`.
Existing checks only (§4):

- **`checks.options`:**
  - `herdrIsADefault`: present by default, absent with
    `defaultPlugins.herdr = false`, standalone and nixarchy-off. Break: delete
    the entry.
  - `herdrPackaged`: in the resolved `src`, `bin/herdr-sessions`'s shebang is a
    `/nix/store` path, and `LICENSE` contains both names. Break: drop
    `patchShebangs`, or drop `LICENSE` from the copy.
- **`checks.menu-verbs`:**
  - The plugin-row floor goes up by one.
  - A new claim: every herdr subcommand the widget sends (D3's list, read from
    `bin/herdr-sessions`) appears in the pinned herdr's `--help` output. Break:
    add a made-up `herdr session frobnicate` call to a fixture copy.
- **`checks.plugin` (VM):** `herdr` resolves from the session PATH, and the
  widget's `herdr-sessions list` returns `{"ok":true,…}` with no sessions.
  Break: drop `pkgs.herdr` from `packages`, and the result says
  "herdr is not installed".
- **By hand on the owner's machine:** Super+Alt+H opens the widget. Delete asks
  first. A failed delete says so.
