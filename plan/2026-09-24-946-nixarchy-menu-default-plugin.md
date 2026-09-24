---
status: approved
issue: 946
spec: spec/2026-09-24-946-nixarchy-menu-default-plugin.md
---

# Plan: nixarchy-menu as an opt-in default plugin, in the menu's own slot

## The approved decisions, carried over

This plan is self-contained: everything needed is here, without opening the
intent or spec.

1. **The flake input `nixarchy-menu`** is pinned to nixarchy-menu main
   `8775661650ec7d169ca6f0b17a49922dc8005b49`.
   - `inputs.nixpkgs.follows = "nixpkgs"` and `inputs.omarchy.follows = "omarchy"`,
     which are its only inputs.
   - A `# Why: docs/internals/flake.md#nixarchy-menu-opt-in-946` pointer.
   - A new flake.md section modelled on nixarchy-flatsnap's (`:456-478`). It
     covers what it provides, that it is off unless `defaultPlugins.menu = true`,
     how to bump it, and the hand-install `rm`.
2. **A per-entry default.** `defaultPluginSet` entries gain
   `enableByDefault` (bool, default `true`). Resolution
   (`modules/home.nix:404-407`) changes from `cfg.defaultPlugins.${name} or true`
   to `… or p.enableByDefault`.
   - **Why:** the `defaultPlugins` default attrset (`:650-661`) is replaced
     wholesale when a host sets any key. So a `menu = false` there would be
     dropped by `{ podman = false; }`.
   - The `defaultPlugins` description gains: "`menu` is the exception: it is
     off unless set to `true`."
3. **A per-entry placement.** `defaultPluginSet` entries gain `placement` (str,
   default `"right"`). The enable-once hook passes it to `omarchy-plugin-enable`
   only when non-empty.
   - An empty placement makes a clone take its source's bar slot in place
     (`PluginRegistry.qml:529-533`). `right` moves it (`:544`).
4. **The entry `menu`:**
   - id `nixarchy.menu`
   - src `inputs.nixarchy-menu.packages.<sys>.plugin`
   - `enableByDefault = false`, `placement = ""`
   - packages `python3 jq fd wl-clipboard xdg-utils libnotify curl wtype`
   - voxtype is not included, because it is optional and detected on PATH
5. **Pre-disable, applied generally.** Before enabling an id whose
   `omarchy-plugin-list --json` entry has a non-empty `clonedFrom`, the hook
   disables every **other enabled** plugin with the same `clonedFrom`. Errors
   are logged to `nixarchy-default-plugins` and never fatal.
   - It runs inside the existing once-per-id branch, so a user's later choice
     is never fought.
   - Disabling after the enable is wrong: `restoreCloneSource` (`:555`) would
     bring the stock menu back.
6. **Hand installs.** The rule that leaves a real directory at a plugin id
   alone (`modules/home.nix:1110`) stays.
   - The hook logs one hint line when a declared id's directory is not a
     symlink: `rm -rf ~/.config/omarchy/plugins/<id>`, then log in again.
   - Companion change: nixarchy-menu gets a new issue.
     `bin/nixarchy-menu install` refuses when the target is a symlink into
     `/nix/store`.
7. **Not in scope:**
   - turning the menu on by default (a follow-up issue after razer and p620,
     which also decides whether the large Smart Match model belongs in the
     default closure; it is 84.7 MiB now)
   - any hard-coded `evindor.keystroke`

## Steps

1. **`flake.nix`, `docs/internals/flake.md`:** add the input per decision 1,
   then `nix flake lock --update-input nixarchy-menu`.
   → Verify:
   - `nix flake metadata` shows `nixarchy-menu` at `8775661`.
   - Its `nixpkgs` and `omarchy` resolve to nixarchy's nodes, so there are no
     new `nixpkgs_N` nodes.
   - `git diff flake.lock` touches only the new input.
2. **`modules/home.nix` options:** add `enableByDefault` and `placement` to
   the `defaultPluginSet` submodule. Change the resolution at `:406`, and add
   the sentence to the `defaultPlugins` description.
   → Verify: `nix eval` of the existing hosts' `defaultIds` in checks is
   unchanged (step 5 tests).
3. **`modules/home.nix` entry:** add `menu` per decision 4, next to
   `flatsnap`, with its comment.
   → Verify: `nix build .#checks.x86_64-linux.options` builds the plugin
   through `validatedPlugins`, so the id matches and the manifest is valid.
4. **`modules/home.nix` hook** (`:1873-1918`):
   - Iterate over `id<TAB>placement` lines built from `resolvedDefaults`
     (`lib.concatMapStringsSep`), replacing `defaultIds` in the loop only.
     `defaultIds` stays for the state check.
   - Add the pre-disable (decision 5) and the placement branch (decision 3).
   - Add the hand-install hint (decision 6).
   - `omarchy-plugin-disable` is on the hook PATH via `cfg.package`, the same
     as enable.

   → Verify: `shellcheck` on the rendered hook text (via an options-test
   `runCommand`), with no new findings.
5. **`tests/options.nix`:**
   - Extend `fixtureDefaults` with a third entry, `clone`: a fixture whose
     manifest has `"clonedFrom":"omarchy.menu"`, with
     `enableByDefault = false` and `placement = ""`.
   - Add these cases:
     - (a) With `defaultPlugins` unset, `hookLists "nixarchy.clone"` is false.
     - (b) With `defaultPlugins = { podman = false; }`, it is still false.
     - (c) With `defaultPlugins.clone = true`, the hook lists it with an empty
       placement, and `nixarchy.fixture` still has `right`.
     - (d) The hook text contains the `clonedFrom` pre-disable, and it appears
       before the `omarchy-plugin-enable` call (index comparison with
       `lib.strings`).
     - (e) The real entry `menu` resolves off on a default nixarchy home.

   → Verify: `nix build .#checks.x86_64-linux.options` passes. Each new case
   fails when its guarded behaviour is reverted (checked once each, then
   restored).
6. **Full check:** run `nix flake check` on the branch. Any heavy local work
   goes under `taskset -c 0`, because p620 is shared.
   → Verify: exit 0, and the closure of `inputs.nixarchy-menu.packages.<sys>.plugin`
   is recorded here with `nix path-info -Sh`.
7. **Razer.** Claim it on the bus first; no generation is kept.
   - Build razer's toplevel on p620 from a `/tmp` clone of nixos_config with:
     - `--override-input nixarchy git+file:///mnt/data/Source-home/nixarchy-946`
     - one extra line for the user's HM, `programs.nixarchy.defaultPlugins.menu = true;`
   - `nix copy` it to razer, then `switch-to-configuration test`.
   - Because razer's plugin dir is a hand copy, check the hook logs the
     `rm` hint. Then `rm -rf` the hand copy and run
     `~/.config/omarchy/hooks/post-boot.d/default-plugins` in the session
     environment.

   → Verify:
   - `omarchy-plugin-list --json` shows `nixarchy.menu` enabled from a
     `/nix/store` link, with `omarchy.menu` and `evindor.keystroke` disabled.
   - The bar's menu button is in the same slot as before (a screenshot
     compared with the pre-test one).
   - `Super+Space` opens nixarchy-menu.
   - Then restore razer's original generation with `switch-to-configuration
     test` from `/run/current-system` as captured before, restore the hand
     copy from `~/dev/nm-restore`, re-enable it, restart the shell, post
     "done", and record the results here.
8. **Companion issue:** open the nixarchy-menu issue for the installer refusal
   (decision 6), linked from the PR.
9. **Codex review** of the branch, then the PR. The PR links intent, spec and
   plan, and merges when CI is green and the user agrees.

## Tests

- `nix build .#checks.x86_64-linux.options`: the new cases (a) to (e) pass,
  and each fails when its behaviour is reverted.
- `nix flake check`: exit 0.
- The razer checks from step 7.

## Rollback

Revert the merge. The input, entry and hook change go with it.
- **Hosts that never opted in** see no change in either direction.
- **An opted-in host** falls back to the stock menu, because the plugin link
  is removed by the stale-symlink cleanup and the clone's disable restores
  `omarchy.menu`.
- **The enable-once marker for `nixarchy.menu` stays behind.** That is
  harmless, and it means a later re-merge will not re-enable it for a user
  who had since turned it off.

## Deviations during implementation

- **Step 4:** each id's placement travels in a bash associative array
  (`declare -A placement=([id]=placement …)`) built with `lib.escapeShellArg`,
  instead of `id<TAB>placement` lines. The behaviour is the same, and the
  quoting is simpler. The hand-install hint runs for every id still to do,
  before the already-enabled check, so a hand copy that is already enabled
  still logs it once.
- **Step 5:** step 4's shellcheck runs in `checks.options` itself, on the hook
  as rendered with the real `menu` entry on (`defaultHookScript`, `-S warning`).
  The same shell section asserts that the real plugin passes the validator
  (`menuValidated`).
- **Step 6:** a whole `nix flake check` fails on `packages.grok-bot` being
  unfree (`Refusing to evaluate package 'grok-bot-0.24.0'`). That is
  pre-existing: evaluating its `drvPath` on main `a5460e2` fails identically,
  and nixarchy's CI never runs a whole `flake check`, only named checks. So
  step 6 is instead:
  - the PR workflow's lint, run locally: `nix fmt -- --ci` (0 changed),
    statix and deadnix all exit 0
  - `checks.options`, which passes
  - CI builds the rest

  The pinned plugin's closure, measured at `8775661`, is **84.7 MiB**.
- **Step 4, after the Codex review (P2, accepted):** the pre-disable also
  covers a target that is **already enabled**, such as a hand install sitting
  beside an enabled `evindor.keystroke`. Before, that case was marked done
  and both stayed on, and `resolveEnabledId` picked the alphabetically first
  one.
  - The hook now lists the enabled rivals first. It only marks-and-skips when
    ours is on **and** there are no rivals.
  - Otherwise it disables the rivals, then (re-)enables ours, with no
    placement if ours was already on. The re-enable takes the source back
    off after `restoreCloneSource` (`PluginRegistry.qml:548-549`).
  - Step 7 tests this exact case on razer.

## Razer results (2026-09-24, step 7; toplevel k0rxjvx4 from nixos_config 758b4af with nixarchy at c4fea64)

- **Case 1, the Codex scenario** (a hand-copied `nixarchy.menu` and
  `evindor.keystroke` both enabled): **pass.**
  - HM logged "nixarchy.menu is your own directory, not replacing it", and
    the hook logged the `rm` hint.
  - The hook disabled `evindor.keystroke` and re-enabled ours.
    `omarchy-menu toggle root` (the stock Super+Space path) opens
    nixarchy-menu, and the bar is pixel-identical apart from the clock.
  - A disabled `omarchy.menu` entry is left in the bar layout where the rival
    sat. It isn't drawn, and `restoreCloneSource` removes every source entry
    before restoring, so it is harmless.
- **Case 2, the declared plugin** (hand copy removed): **pass.** The link
  points at `/nix/store/gh2g5346...-nixarchy-menu`, the pinned build.
  Super+Space opens it, the bar is unchanged, and there are 0 failed units.
  - Test-procedure note: activating the same toplevel twice doesn't re-run
    HM, so the home-manager unit had to be restarted.
- **Case 3, the off switch** (menu no longer declared): **FAIL, a design gap.**
  - HM's stale cleanup removes the link, so the plugin is gone. But
    `omarchy.menu` stays in `disabledPlugins`.
  - Result: **no menu button, and Super+Space opens nothing.**
  - Removing files never runs the shell's `restoreCloneSource`, which only a
    disable does. The spec's "clean off switch" outcome is not met. This is
    stopped for a user decision before any fix.
- **Restored:** 2954 (06kpcydy), the hand copy back and enabled in its slot,
  `evindor.keystroke` and `omarchy.menu` disabled, the stray entry removed,
  no marker, 0 failed units.

## Amendment 1: the off switch restores the source (spec amendment 1, approved 5c52092)

### Decisions, carried over
- **Marker content.** The enabled-once marker holds the plugin's
  `clonedFrom`. It is written at enable time, and also when the plugin is
  found already on. For a plugin that isn't a clone, it stays empty.
- **Restore pass, at the start of the hook.** A **dropped clone** is a marker
  whose id isn't in the declared ids, whose content (the source) is
  non-empty, and whose `$plugins/$id` is gone. Once the shell answers, for
  each dropped clone the hook:
  - runs `omarchy-plugin-enable "$source" --before "$id"`, which puts the
    source beside the orphaned bar entry
  - runs `omarchy-plugin-disable "$id"`, which removes the orphan, since there
    is no manifest
  - removes the marker once the enable worked

  A marker whose directory still exists is left alone.
- **Early exit** only when the to-do list and the dropped-clone list are
  both empty.
- **Limit** (documented in flake.md): with every default off, there is no
  hook, so no restore. The manual command is `omarchy plugin enable
  omarchy.menu`.

### Steps
10. **`modules/home.nix` hook.**
    - Write `$src` into the marker on both marking paths.
    - Before the `todo` early exit, build `gone` (id and source pairs) from
      the markers, keeping those not in `defaultIds` whose directory is gone.
    - Change the early exit to `[ ${#todo[@]} -gt 0 ] || [ ${#gone[@]} -gt 0 ] || exit 0`.
    - After the shell ping, run the restore loop for `gone`.

    → Verify: `checks.options` shellcheck is still clean.
11. **`tests/options.nix`,** a new case `defaultPluginsRestoreSource`:
    - on: the hook text writes `"$src"` into the marker, and
      `--before "$id"` appears before the to-do enable loop
    - off: `--before` appears after the to-do loop

    → Verify: it passes, and it fails when the restore block is moved after
    the loop (checked once, then restored).
12. **`docs/internals/flake.md`:** in the nixarchy-menu section, a sentence
    on the off switch restoring the stock menu, and the limit.
    → Verify: rendered by reading it.
13. **Razer re-check** (claimed on the bus; no generation kept):
    - Build the toplevel with `menu = true`, activate in test mode, remove
      the hand copy, restart the HM unit, and run the hook. That writes the
      marker with `omarchy.menu`.
    - Then activate razer's own 2954 system (menu not declared) and run the
      hook again.

    → Verify:
    - The menu button is back in the same slot (the bar matches the pre-test
      screenshot).
    - `omarchy-menu toggle root` opens the **stock** menu.
    - The `nixarchy.menu` marker is gone.

    Then restore the hand copy, re-enable it, remove the stray entries, and
    post "done". Record the results here.
14. **Then carry on with the rest of step 9:** a Codex re-review of the new
    commits, then the PR.
