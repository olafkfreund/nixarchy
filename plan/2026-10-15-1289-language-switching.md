---
status: approved
issue: 1289
spec: spec/2026-10-15-1289-language-switching.md
---

# Plan: Setup ▸ Language works on NixOS

## Approved decisions (from the spec; implement against these)

- **Option B:** one locale per pick, then a rebuild.
- **New option `programs.nixarchy.language`** in `modules/nixos.nix`.
  - Its type is `nullOr (enum registryCodes)`; the default is `null`.
  - `registryCodes` and each code's locale come from
    `builtins.fromJSON (builtins.readFile "${inputs.omarchy}/default/i18n/locales.json")`.
    That is the flake input, a pure read, the same route as the fontconfig
    read at ~:2161. When the file is absent (`v4.0.4`), they are `{ }`.
  - When set, and only inside `mkIf cfg.enable`:
    `i18n.extraLocales = [ "<locale>/UTF-8" ]`, as a plain list assignment.
    `i18n.defaultLocale` is untouched.
- **New `nixarchy-language-select <code|null>`**, a `writeShellApplication`
  in `modules/apps.nix` beside `nixarchy-service-enable`.
  - It validates against a build-time JSON of the registry.
  - It writes, replaces or clears one line in
    `~/.config/nixarchy/services.nix`:
    `programs.nixarchy.language = "<code>";  #@ language`. It reuses the
    service writer's insertion logic and its temp-and-rename write.
  - It prints that a rebuild is needed.
- **Edge carry (step 5),** not in this PR:
  - `omarchy-language`'s `generate_locale()` calls the writer when the
    locale is missing, prints the apply-and-pick-again message and exits
    non-zero **before** any switch. No `sudo`, `pkexec` or `/etc/locale.gen`.
  - `omarchy-locale-generate` becomes a refusal naming the writer.
  - Both leave `checks.session`'s `/usr` exceptions.
- **No coexistence fixture:** `extraLocales` merges, and nothing else is
  set.

## Steps

1. **`modules/nixos.nix`: the option and the locale.**
   - Declare `language` beside the other `programs.nixarchy` options, in a
     `let` that reads the registry once: `registry`, `registryCodes`. Guard
     the read with `builtins.pathExists` so `v4.0.4` gives `{ }`.
   - Under `mkIf cfg.enable`, add
     `i18n.extraLocales = lib.mkIf (cfg.language != null) [ "${registry.${cfg.language}.locale}/UTF-8" ];`.
   - Write a description, and pick a `literalExpression` example only if the
     registry has one at eval.

   **Verify:**
   - `nix eval .#nixosConfigurations.vm.config.programs.nixarchy.language`
     is `null`;
   - `i18n.extraLocales` is unchanged from `main`;
   - on `main` (`v4.0.4`, no registry), setting `language = "da"` fails
     evaluation with an enum error. That is expected on stable; confirm and
     report it.

   **Traps:**
   - `mkIf` on a list is fine. Do not use `mkDefault` on the list (§7).
   - `git add` before evaluating (§5).
   - `nix fmt`, then read `git diff --stat`.

2. **`modules/apps.nix`: `nixarchy-language-select`.**
   - Read `nixarchy-service-enable` (~:1415) and reuse its pieces:
     validation, the insert-before-closing-brace logic, temp-and-rename,
     and `chmod --reference` (#1276).
   - Bake the registry codes in as a file (`pkgs.writeText` of the JSON, or
     an empty `{}` on stable).
   - `null` removes the marked line.
   - An unknown code exits 2 with the list of known codes.
   - Add it to the same package list that `nixarchy-service-enable` sits in.

   **Verify:** step 3's check.

   **Traps:**
   - `writeShellApplication` runs shellcheck at full severity, so build it.
   - An undeclared command is a wrong answer, not a missing one: declare
     `runtimeInputs` (§7).
   - The marker regex must not match a commented `# programs.nixarchy.language`
     line as live.

3. **Checks (`main`).**
   - **`tests/options.nix`.** On `main` the registry is empty, so the
     option can only be `null`. Assert, in both states:
     - **on:** the option exists, defaults to `null`, and
       `i18n.extraLocales` is unchanged;
     - **off:** Mode A has the option and sets nothing.

     The `language = "da"` path cannot be evaluated on `main` (no
     registry). So also assert, by evaluation through a fixture that
     overrides `inputs.omarchy` with a tiny directory holding a
     `default/i18n/locales.json` of two codes, that:
     - `"da"` adds `da_DK.UTF-8/UTF-8`;
     - a user's own extra locale survives.

     If overriding `inputs` in `options.nix` is awkward, put this in a
     small new check, `tests/language-locale.nix`, that calls the module
     with that stub input. Say which.
   - **`tests/language-select.nix` (new `runCommand`, in the style of
     `tests/app-selection.nix`).** It takes the built
     `nixarchy-language-select` by pname via `testLib.vmPackage`, uses a
     stub `services.nix`, and a registry file through an env override if
     the script accepts one (add `NIXARCHY_LANGUAGE_REGISTRY` as a test
     seam only if needed, and say so). It counts failures, and covers:
     - insert into a file without the line;
     - replace an existing line;
     - clear with `null`;
     - an unknown code exits 2 and leaves the file unchanged;
     - the file's mode is kept;
     - a commented line is not treated as live.

   **Red proofs:**
   - options/locale: drop the `mkIf cfg.enable` gate, so Mode A sets a
     locale;
   - language-select: break the replace, so a second line is added, and
     drop the validation, so an unknown code is written.

   **Traps:**
   - Cheap checks one at a time under
     `flock /mnt/data/vmtest/codex-build.lock`.
   - `checks.options` is the expensive tier, only when CI is idle; prove
     the cases by evaluation otherwise (§6).

4. **Docs (`main`): `docs/manual/configuration.md`, a "Language" section.**
   - Setup ▸ Language (when the Omarchy release has it): pick, apply, pick
     again, and why NixOS needs the rebuild.
   - `programs.nixarchy.language` for a flake user.
   - `nixarchy-language-select`.

   No new page, so the three lists are unchanged.

   **Verify:** `checks.docs-lists`, `checks.doc-options` (it checks quoted
   option names exist).

5. **Edge carry (after this merges, on `edge-candidate`, lead).**
   - Patch `omarchy-language`'s `generate_locale()` and
     `omarchy-locale-generate` as above.
   - Drop both from `checks.session`'s `/usr` exceptions.
   - Add `bin-ledger` rows (`class = "patch"`).
   - Add a stubbed `runCommand` case: locale missing, so the writer is
     called, the exit is non-zero, and `50-omarchy-language` is not written;
     locale present, so it switches as upstream.
   - Update `docs/manual/omarchy-channels.md`'s edge note, and close
     #1280's language item.

## Tests

| Command | Expected |
|---|---|
| `nix build .#checks.x86_64-linux.language-select` | green; red for each break |
| options / locale cases (by eval, or the new check) | green; red with the gate removed |
| `nix build .#checks.x86_64-linux.docs-lists`, `doc-options` | green |
| `nix fmt -- --ci`, statix, deadnix | clean |

## Model split

Steps 1–3 edit three or more files, so they go to the `coder` agent. Step 4
and the edge carry (step 5) stay with the lead. A fresh Opus agent reviews
the diff against this plan.

## Rollback

Revert the merge. `programs.nixarchy.language` disappears; a
`services.nix` that sets it then fails evaluation until the line is
removed, and the error names it. Edge keeps its exceptions until the carry
is reverted too.
