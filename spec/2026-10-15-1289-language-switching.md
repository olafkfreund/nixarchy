---
status: draft
issue: 1289
intent: intent/2026-10-15-1289-language-switching.md
---

# Spec: Setup ▸ Language works on NixOS

**Chosen: option B, one locale per pick and a rebuild.** This is the
intent's recommendation; the approval did not name an option. To prefer A
(every locale up front, about 220 MB on every machine) or the middle
ground, say so at this gate and the spec changes.

## Design

### 1. The option (`main`, all channels)

`modules/nixos.nix`, inside `mkIf cfg.enable`:

```nix
language = lib.mkOption {
  type = lib.types.nullOr (lib.types.enum registryCodes);
  default = null;
  description = "Omarchy's interface language (Setup ▸ Language). Adds that language's locale to the system so the switch can complete; null keeps today's set.";
};
```

- **`registryCodes`** is read from the Omarchy tree's
  `default/i18n/locales.json` at evaluation time, through `inputs.omarchy`.
  It is a flake input, so this is a pure read, not import-from-derivation
  (the same route `modules/nixos.nix` ~:2161 uses for the fontconfig
  file). The registry also gives each code's locale.
- **On `v4.0.4`** there is no `locales.json`. The option still exists, its
  type is `nullOr (enum [])`, and only `null` is accepted. That is honest:
  stable has no language feature to choose for.
- **When set:**
  `i18n.extraLocales = [ "${registry.${code}.locale}/UTF-8" ];`. That is a
  plain assignment (a list, §7), so it merges with a user's own extra
  locales. `i18n.defaultLocale` is untouched: the session's `LANG` is
  upstream's per-user setting (`~/.config/uwsm/env.d/50-omarchy-language`),
  not the system's.
- **Mode A:** the option exists on a disabled config, and nothing is set.

### 2. The selection writer (`main`)

A new `nixarchy-language-select <code>`, a `writeShellApplication` in
`modules/apps.nix` beside `nixarchy-service-enable`:

- It validates `<code>` against the registry, which the module bakes in as a
  JSON file at build time, or `null` to clear.
- It writes one line into `~/.config/nixarchy/services.nix`, marked `#@
  language`, the same marker convention `nixarchy-service-enable` uses:
  `programs.nixarchy.language = "da";  #@ language`. It replaces the line
  if present, and inserts it before the module's closing brace if not, using
  the existing service writer's insertion logic and its temp-and-rename
  write.
- `services.nix` is the user's own NixOS module, for decisions about the
  machine, and `nixarchy-apply` already copies it into the flake. This adds
  no new file and no new import.
- It exits 0 and prints that a rebuild is needed (`nixarchy-apply`).

### 3. `omarchy-language` on NixOS (edge carry, until a stable tag brings it)

Patched in `pkgs/omarchy/default.nix`. `--replace-fail` is used, so on
`main` it waits until the command exists.

- **`generate_locale()`:** when the locale is already present (upstream's
  own `locale_generated` check), return as today. Otherwise run
  `nixarchy-language-select <code>` and print:

  > *"Danish needs its locale built into the system. It is recorded in
  > your configuration; apply it (`nixarchy-apply`, or Install ▸ Apply
  > changes) and choose Danish again."*

  Then exit **non-zero before** `apply_session_locale` and the interface
  switch, as upstream does when generation fails ("the interface switched
  with LANG behind it" must not happen). It never runs `sudo` or `pkexec`,
  and never touches `/etc/locale.gen`.
- **`omarchy-locale-generate`** is no longer reachable. Its body is replaced
  with a refusal that names `nixarchy-language-select`, so a stray caller
  gets a reason, not a `locale-gen: not found`.
- **The `checks.session` `/usr` exceptions** drop both commands: the
  patched bodies hold no `/usr` path. #1280's language item closes.

### Coexistence (§14)

`i18n.extraLocales` is a list that merges, so a user's own entries are kept
alongside ours. `i18n.defaultLocale` and `i18n.extraLocaleSettings` are not
set. Nothing can collide, so there is no fixture, for the reason #1278,
#1283 and #1285 give.

### Docs

- The manual gains a short "Language" section in `configuration.md`:
  Setup ▸ Language, the one rebuild per new language and why, and the
  option for a flake user.
- `docs/manual/omarchy-channels.md`'s edge note drops the language item once
  the edge carry lands (that page is in PR 2, #1278).

## Alternatives rejected

- **A: every locale up front.** About 220 MB on every machine for a setting
  most users change once. The owner may still choose it at this gate.
- **The middle ground (A behind an option).** It is A for whoever turns it
  on, and B is still needed for everyone else.
- **`i18n.imperativeLocale` with `localectl`.** It changes which built
  locale is the system default at runtime; it does not make a locale
  available. Not the gap.
- **A new selection file** (`~/.config/nixarchy/language.nix`). It needs a
  new copy step in `nixarchy-apply` and a new import, for one line that
  `services.nix` already has room for.
- **Running `nixarchy-apply` from inside `omarchy-language`.** That turns
  a menu click into a full rebuild with no confirmation, which is the
  failure #765's "it asks before it switches" exists to prevent. Telling
  the user to apply keeps that rule.

## Risks

- **The registry moves upstream.** A code or locale renamed in
  `locales.json` changes the enum, and a machine set to a removed code
  fails evaluation with an enum error that names the allowed values. That
  is a loud, correct failure; the release notes name it.
- **Two steps instead of one.** The user picks, applies, and picks again.
  The message says exactly that, and the selection is kept, so the second
  pick is instant.
- **`services.nix` edited by hand.** The writer only touches its marked
  line. A user's own `programs.nixarchy.language` elsewhere in their config
  makes two definitions conflict at evaluation, which says where both are.

## Verification

| Check | Proves | Fails when |
|---|---|---|
| `checks.options` | `language = null` adds nothing; `language = "da"` adds `da_DK.UTF-8/UTF-8` to `i18n.extraLocales`; a user's own extra locale survives; Mode A has neither | the gate or the merge is wrong |
| a `runCommand` check for `nixarchy-language-select` (stubbed `services.nix`, as `tests/app-selection.nix` drives the app writers) | it inserts, replaces and clears the marked line, refuses an unknown code, and keeps the file's mode | each behaviour is broken in turn |
| edge carry: the patched `omarchy-language`, run against a stub `locale -a` with the locale missing | it calls the writer, exits non-zero, and leaves `50-omarchy-language` unwritten; with the locale present it switches as upstream | the patch is reverted |
| `checks.session` (edge) | the `/usr` scan passes with both commands off the exception list | a `/usr` path remains |
