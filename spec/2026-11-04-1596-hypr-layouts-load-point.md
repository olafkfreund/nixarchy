---
status: approved
issue: 1596
intent: intent/2026-11-04-1596-hypr-layouts-load-point.md
---

# Spec: A supported load point for layout settings after looknfeel

## What was checked

- **Stable** (`omarchy-4.5.0-rc3`, `config/hypr/hyprland.lua:19-27`) and
  **edge** (quattro `cc99764`, the same file, lines 22-29) both carry the
  line `require("hypr.looknfeel")` verbatim. So one `--replace-fail` holds on
  both pins.
- Hyprforge's substitution (`pkgs/omarchy/default.nix:2065-2067`) anchors on
  `require("hypr.autostart")`. A substitution on the `looknfeel` line touches
  neither its anchor nor the exact text its Connect button looks for.
- `require_optional.module` (`default/hypr/require_optional.lua`) returns
  nothing when the module isn't on `package.path`, and lets errors inside an
  existing module surface. That covers Mode A and loud failure.
- `docs/manual/configuration.md:637` and `:667` list the files the two
  sessions share.

## Design

1. **`pkgs/omarchy/default.nix`:** one more `substituteInPlace` on
   `$out/share/omarchy/config/hypr/hyprland.lua`, placed beside Hyprforge's:

       --replace-fail 'require("hypr.looknfeel")' \
         $'require("hypr.looknfeel")\nrequire("default.hypr.require_optional").module("hypr.layouts") -- nixarchy: layout settings (#1596)'

   It carries a 2-line comment ending
   `# Why: pkgs/AGENTS.md#layouts-load-point`. It sits after `looknfeel` and
   before `autostart`, so the declarative config files stay together before
   `autostart` spawns anything.
   - **Load order:** `looknfeel` < `layouts` < Hyprforge's saves < SUPER+L's
     saved toggles.
   - **Measured:** only `looknfeel` < `layouts`, by the probe below.
   - **Expected, not measured:** the other two follow from require order,
     because a later `hl.config` overrides an earlier one. Hyprforge's own
     probe and `looknfeel.lua`'s defaults rely on the same behaviour (codex).
   - **The seeded copy gets the line too.** A fresh home's seeded
     `~/.config/hypr/hyprland.lua` comes from this patched store file
     (`modules/home.nix:1195`), exactly as Hyprforge's line already does
     (agy).

2. **`tests/session.nix`:** a probe after the Hyprforge one, in the same
   shape. It runs in two stages, so 9 can't come from a looknfeel edit that
   never took effect (codex):
   1. Append `hl.config({ general = { border_size = 5 } })` to the user's
      `~/.config/hypr/looknfeel.lua`, keeping a `cp -p` copy so the restore
      keeps `omarchy:` ownership (agy). Reload, and poll for **5**.
   2. Write `~/.config/hypr/layouts.lua` containing
      `hl.config({ general = { border_size = 9 } })`, `chown omarchy:` it, and
      reload. Poll for **9**.

   What the second poll reads:
   - 9 proves `layouts` loaded **after** `looknfeel`.
   - 5 means it loaded before `looknfeel`, or not at all.

   A reload re-reads both files, because `bootstrap.lua:4-29` evicts every
   `hypr.*` module from `package.loaded`.

   It restores `looknfeel.lua`, removes `layouts.lua` and reloads. Its §1
   break: move the require above `require("hypr.looknfeel")`, then delete it.
   Both must go red.

3. **`pkgs/AGENTS.md`:** a short `layouts-load-point` section beside
   Hyprforge's: what the hook is, the precedence, why it isn't in
   `autostart.lua`, and the coexistence note below.

4. **`docs/manual/configuration.md`:** leave the two brace lists alone,
   because those five files are seeded and shared. After the first list, add
   a separate sentence covering:
   - `~/.config/hypr/layouts.lua` is optional and never seeded;
   - the Omarchy session loads it automatically after `looknfeel`;
   - the user's own session loads it only if their own `hyprland.lua`
     requires it;
   - the precedence (codex, agy).

## Alternatives rejected

- **Anchor after `require("hypr.autostart")`.** It also satisfies "after
  `looknfeel`, before toggles", but it shares Hyprforge's anchor. Two
  substitutions on one line then depend on order, and on Hyprforge's exact
  text surviving.
- **Ask upstream for the hook.** Upstream's Arch session reads
  `~/.config/hypr/hyprland.lua`, which a user can edit, so the need only
  exists because the nixarchy session runs the store copy. That makes it
  nixarchy's to carry, as with Hyprforge (#1059).
- **A `programs.nixarchy` option that writes `layouts.lua`.** It isn't needed
  and isn't requested. Downstream already writes the file. An option can come
  later if someone asks.
- **Carrying asks 2 and 3** (SUPER+L master and monocle, the bar icons). These
  were declined at intent approval: they're Omarchy's code, and outside this
  change.

## Risks

- **Coexistence (§14).** Both sessions share `~/.config/hypr`. A user whose
  own Hyprland setup already has a `layouts.lua` module would now have it
  loaded by the **Omarchy** session too. Their own session is untouched, since
  it never reads the store `hyprland.lua`. This is the same exposure as
  Hyprforge's line, and it's documented in the manual list rather than guarded.
  There's no option merge involved, so there's no `tests/coexistence` fixture
  (§14 is about merged NixOS options). The manual says it plainly.
- **Upstream rewords the `looknfeel` line.** `--replace-fail` fails the build
  and edge's `prepare` on that bump, which is the intended signal.
- **`checks.install-phase-budget`.** The edit adds about 150 bytes to the
  phase. The plan reads the current margin before and after.
- **`checks.session` cost.** The probe is a few seconds inside an existing VM
  check, and adds no new VM.

## Coexistence

See Risks. Test-observable only in the Omarchy session, and asserted there.

## Verification

- `checks.session`: green with the hook. Red with the require placed above
  `looknfeel` (reads 5), and red with it removed (reads 5). Both red outputs
  go in the PR.
- `checks.patched-files`, `checks.omarchy` (package), and
  `checks.install-phase-budget`: green.
- All local tiers before the push, and the VM tier only while CI is idle.
