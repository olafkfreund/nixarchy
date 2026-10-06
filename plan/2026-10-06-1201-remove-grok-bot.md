---
status: draft
issue: 1201
spec: spec/2026-10-06-1201-remove-grok-bot.md
---

# Plan: remove grok-bot from nixarchy

## Approved decisions (from the spec)

- The `grok-bot` package, its overlay attribute and its flake package output
  go.
- The `data/apps.nix` entry stays as an `unavailable` app, so the upstream
  `install.ai.grok-bot` row renders disabled with a reason. It keeps `menuId`,
  `label`, `category` and `arch` (the menu-mapping check reads `arch`), and
  drops `attr`, `ours` and `unfree`.
- `programs.nixarchy.apps` also declares an `enable`-only option for every
  `unavailable` app. Enabling one installs nothing and adds a warning naming
  the app, the reason and the line to delete. This covers grok-bot, sublime and
  brave-origin.
- `build.yml` drops `NIXPKGS_ALLOW_UNFREE` from "Build every app the flake
  ships itself" (grok-bot was the only unfree package output) and keeps
  `NIXPKGS_ALLOW_BROKEN: "0"`.
- `grok-cli` and the `grok` agent are untouched.

## Steps

1. **Package removal.** `git rm pkgs/apps/grok-bot.nix`. In `flake.nix`,
   delete line 806 (`grok-bot = final.callPackage ./pkgs/apps/grok-bot.nix { };`)
   and `grok-bot` from the `inherit (pkgsFor.${system}.nixarchy-apps)` list
   at line 1266.
   → verify by `nix eval .#packages.x86_64-linux --apply builtins.attrNames`
   not listing `grok-bot`.
   Traps: none.

2. **`data/apps.nix:457-465`.** Replace the entry's `attr`, `ours` and
   `unfree` with
   `unavailable = "Removed from nixarchy: an unfree Electron build pinned to a Cursor CDN commit with no update path.";`.
   Update the comments at `:339` and `:612` that list the AI rows by name.
   → verify by `python3 .github/scripts/check-menu-mapping.py` with the same
   arguments `build.yml:1044` passes. It must say every row is mapped.
   Traps: `check-menu-mapping.py` parses with regexes, so keep the entry's
   layout (`arch = "grok-bot";` on its own line).

3. **`modules/apps.nix`: options and warning for unavailable apps.**
   - At `:1021-1028`, the `apps = lib.mapAttrs (...) available;` option set
     becomes that, `//`
     `lib.mapAttrs (name: app: lib.mkOption { type = lib.types.submodule { options.enable = lib.mkEnableOption "${app.label} (not available on NixOS)"; }; default = { }; description = "${app.label}: not available on NixOS. ${app.unavailable}"; }) unavailable`.
     Do not reuse `appModule`: for `sublime` it would add a package option
     defaulting to a broken package.
   - At `:1186`, `warnings = lib.optional (needsUnfree ...) ''...'';` becomes
     that list `++ lib.mapAttrsToList (name: app: "nixarchy: ${app.label} is enabled in ~/.config/nixarchy/apps.nix but is not available on NixOS: ${app.unavailable} It installs nothing; remove`${name}.enable`.") (lib.filterAttrs (name: _: cfg.apps.${name}.enable) unavailable)`.
   → verify by step 4's check.
   Traps: escape the backticks inside the Nix string as needed; the warning
   must stay inside the`mkIf cfg.enable` block it is already in. Comments
   follow the house style: why, not what.

4. **`tests/unavailable-apps.nix` (new) and a `checks` entry in `flake.nix`.**
   Evaluation only:
   `(self.nixosConfigurations.vm.extendModules { modules = [ { programs.nixarchy.apps.grok-bot.enable = true; } ]; }).config.warnings`
   must contain a warning mentioning `Grok Bot` and `grok-bot.enable`. The
   same `vm` without the setting must contain no such warning. Shape it like
   `tests/stable-eval.nix`: compute in Nix, assert in a `runCommand` with a
   message saying what was missing. Wire it in `flake.nix` checks with a
   one-line `# Why:` comment pointing at the test.
   → verify by `nix build .#checks.x86_64-linux.unavailable-apps -L`.
   Traps: `generated-checks.sh` builds every check not on its opt-out list in
   PR CI. This one is eval-only and cheap, so it belongs there; do not add it
   to `claimed`.

5. **CI and tooling.**
   - `.github/workflows/build.yml:1254-1259`: drop the grok-bot sentence of
     the comment and `NIXPKGS_ALLOW_UNFREE: "1"`. Keep the broken flag and its
     reasoning. If that step's `nix eval --impure --expr` list still yields an
     unfree package, stop and record it here instead of dropping the flag.
   - `.github/workflows/update.yml:64-65`: reword so the comment no longer
     names `.#grok-bot`; keep its point (do not list a package the job
     cannot change).
   - `pkgs/review.sh:115` and `:287-295`: remove the grok-bot comment and age
     check.
   → verify by `actionlint` (as `build.yml:181` runs it) and
   `bash -n pkgs/review.sh`.
   Traps: write commit messages with `-F`, not `-m` with backticks.

6. **Docs.** `docs/manual/ai.md:20`: drop "Grok Bot" from the row list.
   `docs/internals/flake.md:1206`: reword the sentence that names grok-bot
   as the only package with an unknowable pin. Say there is none now, or drop
   the clause if the paragraph stands without it.
   → verify by reading the paragraphs in context.
   Traps: `docs/` is published; keep relative links intact.

## Tests

- `nix eval .#packages.x86_64-linux --apply builtins.attrNames` → no
  `grok-bot`.
- `nix flake check --no-build` with no `NIXPKGS_ALLOW_UNFREE` → evaluates. If
  an unrelated failure stops it, record it in the PR.
- `nix build .#checks.x86_64-linux.unavailable-apps -L` → passes.
- `nix build .#checks.x86_64-linux.options -L` and
  `.#checks.x86_64-linux.doc-options -L` → pass. If either snapshots option
  names, update its expectation in step 3's commit and say so here.
- `python3 .github/scripts/check-menu-mapping.py ...` → all rows mapped.
- `git grep -n -i grok-bot -- . ':!intent' ':!spec' ':!plan'` → only the
  `data/apps.nix` entry and the new test.

## Rollback

Revert the PR. Grok Bot returns as a package and menu row. The
unavailable-app warnings disappear, and enabling `sublime` or `brave-origin`
fails evaluation again, as it does today.
