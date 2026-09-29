---
status: draft
issue: 1059
intent: intent/2026-09-29-1059-hyprforge-default.md
---

# Spec: Ship Hyprforge as a default plugin

Defaults taken for the intent's open questions, since approval came without
answers. Each can be overruled here.

- **Q1, the pin.** Pin the fork `olafkfreund/nixarchy-hyprsettngs` as it is
  named today, at `2392ad6`, which is identical to upstream's HEAD. A later
  rename changes one `url`, and GitHub redirects the old name meanwhile.
- **Q2, the fix.** It lives in nixarchy. `--config` is nixarchy's choice.
- **Q3, the id.** Keep `aziz.hyprforge`. A second id would diverge from
  upstream for no benefit, since nothing here installs upstream.

## Design

### 1. The input: `flake = false`, packaged by nixarchy (the herdr precedent)

```nix
# Why: docs/internals/flake.md#hyprforge-on-by-default-1059
nixarchy-hyprsettngs = {
  url = "github:olafkfreund/nixarchy-hyprsettngs/2392ad6…";
  flake = false;
};
```

The repository has no `flake.nix`. `modules/home.nix` gains `hyprforgePlugin`,
a `runCommand` in the shape of `herdrSessions`:

- `cp -r` the tree;
- drop `test/` and `preview.png` (not needed at runtime);
- fail unless `LICENSE` still reads `Copyright (c) 2026 Aziz` (MIT requires the
  notice to travel with the code).

### 2. The `defaultPluginSet` entry, on everywhere nixarchy is (ungated)

```nix
hyprforge = {
  id = "aziz.hyprforge";
  src = hyprforgePlugin;
  packages = [ pkgs.lua pkgs.diffutils pkgs.libnotify pkgs.wl-clipboard ];
};
```

Everything else it runs is already on the session's PATH:

- `hyprctl`, from Hyprland;
- `timeout`, `mktemp`, `md5sum`, `readlink`, `head`, `stat` and the rest of
  coreutils;
- `find` and `grep`;
- `omarchy-shell` and `omarchy-launch-config-editor`, from the Omarchy tree.

Declared per §2 and `runtimeInputs`: `lua` runs `baseline.lua`, `cmp` comes
from diffutils, `notify-send` from libnotify, and `wl-copy`/`wl-paste` from
wl-clipboard. All four are `lowPrio`, like every default's tools (#809). No
`placement`: it is a `panel` + `service` plugin, not a bar widget, so the
default `right` section is harmless.

### 3. The fix: the session loads `~/.config/hypr/hyprforge.lua`

In `pkgs/omarchy/default.nix`, Omarchy's `config/hypr/hyprland.lua` gains
Hyprforge's own hook line, after `require("hypr.autostart")`, via
`substituteInPlace --replace-fail` (`pkgs/AGENTS.md`, patching upstream). The
line is:

```lua
require("default.hypr.require_optional").module("hypr.hyprforge") -- Hyprforge (Omarchy plugin)
```

Why this is safe and sufficient:

- **The session reads it.** `modules/nixos.nix:103` points `--config` at that
  store file. `bootstrap.lua` puts `$HOME/.config/?.lua` on `package.path`, so
  `hypr.hyprforge` resolves to `~/.config/hypr/hyprforge.lua`. The `hypr`
  reload prefix re-requires it on every `hyprctl reload`.
- **It is optional.** `require_optional.module` uses `package.searchpath`, so
  a machine that never opened Hyprforge has no file and nothing happens.
  Omarchy's own `omarchy.lua` already uses the helper three times.
- **It is the exact text Hyprforge looks for** (`Engine.hasHook` matches
  `hypr.hyprforge`). A new home's seeded `~/.config/hypr/hyprland.lua`, a
  copy of this file, therefore reads as connected, and the Connect banner
  never appears.
- **Existing homes** keep their older seeded copy (the seed never
  overwrites), so the banner still appears there. Clicking it edits that copy,
  which the session does not read. That is harmless: settings already load
  through the store file. The `docs/manual/plugins.md` section says so.
- **It loads after Omarchy's `looknfeel`/`autostart`**, which is the
  placement Hyprforge itself chooses, so its overrides win. `toggles` still
  comes after, as upstream intends.

Turning the plugin off does not stop the file loading. What Hyprforge saved
stays applied until `~/.config/hypr/hyprforge.lua` is deleted, as with
upstream's Connect line. Documented.

### 4. The menu needs nothing

Hyprforge's service writes `~/.local/share/applications/hyprforge.desktop`.
Omarchy's AppLibrary, which both the stock menu and nixarchy-menu's
Applications provider use, lists desktop entries, so "Hyprforge" appears
under Super+Space. No seeded keybinding. A Super+Alt letter can come later if
you want one.

### 5. Tests

- **`tests/options.nix`:**
  - `hyprforgeIsADefault`: on, `defaultHomeOn` installs `aziz.hyprforge` and
    the hook lists it; off, a home with `hyprforge = false` does neither.
  - `hyprforgePackaged`: the LICENSE holder is present, and `test/` is gone.
  - `noDefaultsHome` gains `hyprforge = false`.
  - `toolNames` gains `lua` (the lowPrio assertion; its list is spelled out
    by design).
- **`tests/plugin.nix`:** the empty-directory node gains `hyprforge = false`.
- **The §2 probe: the session actually loads the file.** In
  `checks.session`, the VM writes `~/.config/hypr/hyprforge.lua` with one
  distinctive value (`hl.config({ general = { gaps_in = 17 } })`) and runs
  `hyprctl reload`. The probe asserts `hyprctl getoption general:gaps_in`
  reads 17, and that it does not without the store hook. This is the only
  layer that can see "saved but never loaded", so it is where the probe goes
  (§2). The spec does not run Hyprforge's UI in the VM. The probe covers the
  contract between Hyprforge and the session, not the panel.
- **Build time:** `--replace-fail` breaks the omarchy build if upstream moves
  `require("hypr.autostart")`.

### 6. Counts and docs

- `readme-counts.sh` is derived: "Fourteen ship by default: eleven are always
  on" becomes fifteen and twelve (`docs/index.md:90`).
- `docs/manual/plugins.md`: a table row `<!-- aziz.hyprforge -->` (the
  build.yml guard requires it) and a section covering what it solves, what it
  does, the Connect caveat, turning it off, and upstream credit.
- `docs/llms.txt:115` names it (readme-counts' llms check).
- `docs/internals/flake.md`: an input section covering why `flake = false`,
  the licence check, the hook patch, the measured size, and how to bump.
- `README.md`: a plugin section in the register of its neighbours.
- `tests/demo/screencast/shots.nix`: `shot-coverage.sh` wants a shot per id.
  No workflow runs it (§4), but a hand-maintained list fails open, so an
  entry goes in.

## Alternatives rejected

- **Patch the fork's Connect to edit `looknfeel.lua`.** It would still be a
  per-home edit that existing homes never receive, and it would fork upstream
  behaviour for a nixarchy-specific cause.
- **Seed `hyprforge.lua` or the hook into `~/.config/hypr/hyprland.lua`.** The
  session does not read that file, which is the bug.
- **Gate the store hook on the plugin being enabled.** The store `hyprland.lua`
  is per-system and the plugin is per-user. The optional require is already a
  no-op without the file, so a gate adds a mechanism and removes nothing.
- **A flake in the fork.** It adds a lock node and upstream maintenance, and
  buys nothing over `flake = false` plus `runCommand`, which herdr has proven.
- **Run upstream's `node test/run.js` in our checks.** It hard-codes
  `/usr/share/omarchy` paths and would need patching. It is upstream's CI's
  business, the same judgement as nixarchy-devenv's extra templates.

## Risks

- **Third-party code, unsandboxed, in every user's shell.** Reviewed at
  `2392ad6`. Recent commits bound every input before it reaches the shell and
  never write through a symlink. Every bump re-reads the diff; this goes into
  the flake.md bump steps.
- **The generated Lua runs `io.popen` inside Hyprland** (mkdir, mktemp, cat,
  mv) at every config load, with Hyprland's PATH. It works on NixOS, because
  coreutils are on the system PATH, but it is code executed at login from a
  user-writable file. That is no worse than `looknfeel.lua`, which already is.
- **A bad save could break Hyprland's config.** Upstream dry-runs through
  `hyprctl eval` and rolls back if `configerrors` names hyprforge after a
  reload. Not re-tested here beyond the session probe.
- **The existing-home Connect banner** is misleading but harmless (§3).
- **`aziz.hyprforge` collides with a marketplace install of upstream.** The
  hand-install rule (a real directory wins) applies, as for every default.
- **Size:** a few hundred KiB of QML/JS plus `lua` (about 1 MiB). It is
  measured in the plan, and the ISO headroom is not at issue.

## Verification

- `nix fmt -- --ci`, statix, deadnix, `readme-counts.sh --check`.
- `checks.options`. Break proof: remove `hyprforge` from the set, and
  `hyprforgeIsADefault` goes red.
- The omarchy package build. Break proof: point `--replace-fail` at a line
  that does not exist, and the build fails.
- `checks.session` (CI, or locally only with nothing in flight). Break proof:
  drop the store hook, and the gaps probe reads the default rather than 17.
- `checks.plugin` in CI.
