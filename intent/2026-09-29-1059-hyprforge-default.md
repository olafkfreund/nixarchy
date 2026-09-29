---
status: approved
issue: 1059
author: olafkfreund
---

# Intent: Ship Hyprforge as a default plugin

## Problem

Changing how the nixarchy desktop looks and behaves (gaps, borders, blur,
animations, input, per-app rules) means editing Lua files under
`~/.config/hypr` by hand and reloading. Nothing lets you see a change before
committing to it, and nothing lets you undo one or keep profiles.

Hyprforge is an Omarchy shell plugin that does exactly this. It has:

- a live scale model of the desktop;
- theme-palette colours that follow `omarchy theme set`;
- a bezier/spring curve editor for animations;
- per-app rules, profiles and history;
- every Hyprland option, from `hyprctl descriptions`.

`olafkfreund/nixarchy-hyprsettngs` is a GitHub fork of
`AbdulazizAlwabel/omarchy-hyprforge` (MIT, plugin id `aziz.hyprforge`,
v1.0.0). It carries no commits of its own yet and has no tag.

**As shipped, it would silently do nothing on nixarchy.**

- Hyprforge writes to `~/.config/hypr/hyprforge.lua`. Its first-run Connect
  button then adds one optional `require` to `~/.config/hypr/hyprland.lua`.
- nixarchy's session never reads that file. It starts Hyprland with
  `--config` pointing at Omarchy's `hyprland.lua` in the store
  (`modules/nixos.nix:103`).
- That store file requires `hypr.monitors`, `hypr.input`, `hypr.bindings`,
  `hypr.looknfeel` and `hypr.autostart` from `~/.config/hypr`, and nothing
  that loads `hyprforge.lua`.

So a user would click Connect and adjust settings. The live preview would
show them, because it goes through `hyprctl`. Then the settings would vanish
at the next login. That is a §2 defect: a setting the tool does not read,
with no error anywhere.

## Proposed outcome

On every nixarchy machine, Hyprforge is installed and enabled from the first
login, as the other default plugins are. It opens from the menu and with
`omarchy-shell hyprforge toggle`. What it saves takes effect after re-login
and after a rebuild, with no manual Connect step that edits a file the
session ignores.

Declining it is one line (`defaultPlugins.<name> = false`) or Setup ▸ Plugins,
as for every default. A user who never opens it sees no change to their
desktop: until Hyprforge has written something, its file does not exist or
is empty, and loading it changes nothing.

## Affected users and systems

- Every nixarchy install, new and existing, at the next login (Mode B). Mode A
  is untouched.
- `flake.nix` gains a new input and a `# Why:` pointer; `flake.lock` changes
  with it.
- `modules/home.nix` gains a `defaultPluginSet` entry and its runtime tools
  (`lua`, `hyprctl`, whatever the plugin shells out to).
- Whatever makes the session load `~/.config/hypr/hyprforge.lua`. That is
  Omarchy's store `hyprland.lua`, as patched in `pkgs/omarchy`, or the seed.
  The spec decides which.
- Tests: `tests/options.nix` (on/off), plugin validation, and a probe that
  the session actually loads the file (§2).
- `tests/plugin.nix` and `noDefaultsHome` gain the new opt-out (the #1052
  lesson).
- Counts and docs: readme-counts ("Fourteen ship by default" becomes
  fifteen), `docs/manual/plugins.md` row and section, `docs/llms.txt`,
  `docs/internals/flake.md`, and the build.yml plugin-row guard.

## Constraints

- **Third-party code, unsandboxed in every user's shell.** Pin a reviewed
  commit and read the diff at every bump, as for herdr and omatheme. The
  LICENSE must keep naming its holder.
- **It writes into `~/.config/hypr`.** It must never make a file Home Manager
  owns unreadable or replace a symlink. Upstream's SafeWriter claims to leave
  a symlinked dotfile a symlink, and the spec verifies that against how the
  seed lays those files out.
- **Loading `hyprforge.lua` has to be optional.** A missing file must not
  break Hyprland's config, like upstream's own optional `require`.
- Nothing is fetched at runtime; no sudo.
- `aziz.hyprforge` is upstream's id. A user who also installs upstream from the
  marketplace has two copies claiming one id.
- Omarchy ≥ 4 and Hyprland ≥ 0.56 (Lua config): nixarchy is on 4.0.4.

## Open questions

1. **Which repository to pin: your fork or upstream?** The fork has no commits
   of its own. Pinning it means bumps come through you; pinning upstream means
   reading Aziz's diffs directly. The fork's name is also spelled
   `hyprsettngs`. Keep that, or rename it before it is pinned into
   `flake.nix`, where the spelling becomes permanent?
2. **Where the fix lives.** Carry the optional `require` for `hyprforge.lua` in
   nixarchy (a `pkgs/omarchy` patch or seed file), or add it to the fork so
   Connect targets a file nixarchy's session reads? The CLAUDE.md §11 rule
   routes Omarchy behaviour upstream. This is nixarchy's `--config` choice,
   so it is ours to carry.
3. **Plugin id.** Keep `aziz.hyprforge`, or give the fork its own id so it
   cannot collide with a marketplace install of upstream?
