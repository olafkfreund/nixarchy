---
status: approved
issue: 1201
intent: intent/2026-10-06-1201-remove-grok-bot.md
---

# Spec: remove grok-bot from nixarchy

## Design

### 1. The package goes

- Delete `pkgs/apps/grok-bot.nix`.
- `flake.nix:806`: drop `grok-bot = final.callPackage ./pkgs/apps/grok-bot.nix { };`
  from the `nixarchy-apps` overlay set.
- `flake.nix:1266`: drop `grok-bot` from the `inherit (...nixarchy-apps)`
  list of package outputs.

### 2. The menu row stays, marked unavailable

`data/apps.nix:457-465` keeps the `grok-bot` entry, so the upstream
`install.ai.grok-bot` row still maps to something and the menu-mapping check
stays green. The entry drops `attr`, `ours` and `unfree`, and gains:

```nix
unavailable = "Removed from nixarchy: an unfree Electron build pinned to a Cursor CDN commit with no update path.";
```

This is the existing mechanism (`modules/apps.nix:53-54, 160, 826`). The row
renders disabled with that text, and the apps.nix template lists it under
"not available". The comments at `data/apps.nix:339` and `:612` that list the
AI rows by name are updated.

### 3. Enabling an unavailable app warns instead of failing

Today `programs.nixarchy.apps` declares options only for `available` apps
(`modules/apps.nix:1021-1028`). So a user with `grok-bot.enable = true` in
`~/.config/nixarchy/apps.nix`, or the same for `sublime` or `brave-origin`,
gets `The option ... does not exist` and the rebuild stops.

Options are declared for `unavailable` apps too, each with only an `enable`
option. When one is enabled, a warning names the app, the reason, and the line
to delete:

```text
nixarchy: Grok Bot is enabled in ~/.config/nixarchy/apps.nix but is not
available on NixOS: <reason>. It installs nothing; remove `grok-bot.enable`.
```

Nothing is installed for it. Every other use of `cfg.apps` reads `available`
names, so nothing else sees the new options (checked: `cfg.apps.retroarch` at
`:1169`, `:3946`; `needsUnfree` at `:123` iterates `available`).

### 4. CI and tooling

- `.github/workflows/build.yml:1254-1259`: in "Build every app the flake
  ships itself", drop `NIXPKGS_ALLOW_UNFREE: "1"` and the grok-bot sentence of
  its comment. Keep `NIXPKGS_ALLOW_BROKEN: "0"`. On 2026-10-06, `grok-bot` is
  the only unfree output in `packages.x86_64-linux`.
- `.github/workflows/update.yml:64-65`: the comment that names
  `.#grok-bot` as history. Reword it so it no longer names a package that
  is gone.
- `pkgs/review.sh:115, 287-295`: remove the grok-bot age check and its
  comment.

### 5. Docs

- `docs/manual/ai.md:20`: drop "Grok Bot" from the list of `Install > AI`
  rows.
- `docs/internals/flake.md:1206`: the sentence that cites grok-bot as the one
  package with an unknowable pin. Reword or drop it.

### Untouched

`grok-cli` and the `grok` agent: `modules/apps.nix:1237`,
`modules/nixos.nix:631`, `pkgs/omarchy/default.nix:1133`,
`pkgs/omarchy/nix-bin/omarchy-default-agent`. It is free-licensed, not broken,
and a separate program.

## Alternatives rejected

- **Drop the `data/apps.nix` entry entirely.** The upstream row would then
  have no mapping, so it vanishes without explanation and the menu-mapping
  check has to learn an exception.
- **A one-off `mkRemovedOptionModule` for `grok-bot`.** That turns the option
  into an assertion error, which still stops the rebuild, and it covers only
  this one app. Section 3 is about the same size and also fixes sublime and
  brave-origin users.
- **Keep `NIXPKGS_ALLOW_UNFREE` in build.yml just in case.** It was there for
  grok-bot. A future unfree app adds it back with its own reason.

## Risks

- **The menu-mapping check reads `attr`** for every entry. An `unavailable`
  entry without `attr` must already be valid: `sublime` has `attr`
  (`data/apps.nix:108-116`), so the plan confirms against
  `check-menu-mapping.py` and keeps `attr` if the check needs it.
- **Options for unavailable apps change the docs/option surface.** Any check
  that snapshots `programs.nixarchy.apps` names (`checks.options`,
  `doc-options`) will see three new option sets. The plan runs those checks
  and updates their expectations if they snapshot names.
- **Users who had grok-bot installed** lose the app at their next rebuild
  after updating. The warning explains why. Their data in `~/.config/Grok Bot`
  is left alone.

## Verification

- `nix eval .#packages.x86_64-linux --apply builtins.attrNames` → no
  `grok-bot`.
- `nix flake check --no-build` evaluates with no unfree environment variable.
  If something unrelated stops it, that is recorded rather than worked around.
- A configuration with `programs.nixarchy.apps.grok-bot.enable = true`
  evaluates and its `config.warnings` contains the removal warning, checked
  by a small eval-only test next to the existing app tests.
- The menu-mapping check, `checks.options` and the app-related checks pass.
- `git grep -i grok-bot` returns only `data/apps.nix` (the unavailable
  entry) and the intent, spec and plan files.
