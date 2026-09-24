---
status: draft
issue: 946
intent: intent/2026-09-24-946-nixarchy-menu-default-plugin.md
---

# Spec: nixarchy-menu can be switched on declaratively, and lands in the menu's place

## Decisions on the intent's open questions

The intent was approved without answers, so this spec takes the defaults the
intent proposed. Each one can be changed at this gate.

1. **On-by-default:** left open. It is a separate follow-up issue after razer
   and then p620. This spec only makes the switch possible.
2. **Pre-disable scope:** general. It applies to any default plugin whose
   manifest has `clonedFrom`, not to the menu by name. Nothing else in the set
   uses `clonedFrom` today, so the menu is the only case in practice.
3. **Leftover hand copies:** the existing "your own directory" rule stays.
   The fix is a documented one-time `rm`, plus a companion change in
   nixarchy-menu, where `bin/nixarchy-menu install` refuses on a host where
   nixarchy manages that id.

## Design

### 1. The flake input (`flake.nix`, `docs/internals/flake.md`)

```nix
# Why: docs/internals/flake.md#nixarchy-menu-opt-in-946
# A commit on main (no tags); bump it the way that page says.
nixarchy-menu = {
  url = "github:olafkfreund/nixarchy-menu/<main commit>";
  inputs.nixpkgs.follows = "nixpkgs";
  inputs.omarchy.follows = "omarchy";
};
```

- nixarchy-menu's inputs are exactly `nixpkgs` and `omarchy` (v4.0.4,
  `flake = false`, used by its checks only), so both follow and nothing new
  enters the lock.
- The `docs/internals/flake.md` section is modelled on nixarchy-flatsnap's
  (`:456-478`). It covers:
  - what the input provides (`packages.<sys>.plugin`)
  - that it is **off** unless `defaultPlugins.menu = true`
  - how to bump it
  - the hand-install `rm` (see §4)

### 2. A per-entry default (`modules/home.nix`)

**The trap.** Today `resolvedDefaults` (`:404-407`) uses
`cfg.defaultPlugins.${name} or true`, and `defaultPlugins` is an `attrsOf bool`
whose default attrset (`:650-661`) is replaced **wholesale** as soon as a host
sets any key. So `menu = false` in that default would be silently dropped for
any host that writes `{ podman = false; }`, and the menu would come on.

**The fix.** The fix is a new submodule field on `defaultPluginSet` entries:

```nix
enableByDefault = lib.mkOption { type = lib.types.bool; default = true; };
```

Resolution becomes `cfg.defaultPlugins.${name} or p.enableByDefault`. Every
existing entry keeps `true`, so its behaviour is unchanged. The menu entry sets
`enableByDefault = false`. The `defaultPlugins` description gains one sentence:
"`menu` is the exception: it is off unless set to `true`."

### 3. The entry (`modules/home.nix`, in `defaultPluginSet`)

```nix
# nixarchy-menu, the Raycast-style menu replacement (#946). Opt-in:
# `defaultPlugins.menu = true`. It replaces omarchy.menu, so it keeps that
# plugin's bar slot (placement "") and any other omarchy.menu clone is
# turned off before it is turned on (the hook below).
menu = {
  id = "nixarchy.menu";
  src = inputs.nixarchy-menu.packages.${pkgs.stdenv.hostPlatform.system}.plugin;
  enableByDefault = false;
  placement = "";
  packages = [ pkgs.python3 pkgs.jq pkgs.fd pkgs.wl-clipboard pkgs.xdg-utils
               pkgs.libnotify pkgs.curl pkgs.wtype ];
};
```

- **Packages:** these are what the plugin shells out to:
  - `python3`: helpers and state migration
  - `jq`
  - `fd`: Files
  - `wl-clipboard`: clipboard and copy effects
  - `xdg-utils`: URL opens
  - `libnotify`: notifications
  - `curl`: the web extensions
  - `wtype`: dictation paste
- **voxtype stays optional.** The plugin detects it on PATH.
- **The existing build-time check** (`validatedPlugins`, `:411-481`) validates
  the manifest id against the attribute name, as it does for every plugin.

### 4. The enable-once hook (`modules/home.nix:1873-1918`)

**New field.** A new submodule field is added:

```nix
placement = lib.mkOption {
  type = lib.types.str;
  default = "right";
};
```

The hook iterates `(id, placement)` pairs instead of `defaultIds` alone.

**The enable loop** (today `:1910`) becomes:

```bash
# A clone of a first-party plugin (clonedFrom) must be the only one: any other
# enabled clone of the same source is turned off FIRST, because turning it
# off after would restore the source beside ours (PluginRegistry restoreCloneSource).
src=$(jq -r --arg id "$id" 'first(.[] | select(.id == $id) | .clonedFrom) // ""' <<<"$list")
if [ -n "$src" ]; then
  for other in $(jq -r --arg id "$id" --arg src "$src" \
      '.[] | select(.clonedFrom == $src and .id != $id and .enabled) | .id' <<<"$list"); do
    omarchy-plugin-disable "$other" 2>&1 | systemd-cat -t nixarchy-default-plugins || true
  done
fi
if [ -n "$placement" ]; then out=$(omarchy-plugin-enable "$id" "$placement" 2>&1)
else out=$(omarchy-plugin-enable "$id" 2>&1); fi
```

- **Only same-source clones are touched.** The pre-disable affects only
  plugins with the same `clonedFrom` that are currently enabled.
- **It runs once per id,** inside the existing enable-once branch. A user who
  later re-enables their old clone isn't fought again.
- **Empty placement keeps the slot.** Checked in `PluginRegistry.qml:527-545`:
  a clone with no placement **takes the source's slot in place**
  (`:529-533`) and is never moved. With `right`, the `moveBarEntry` at `:544`
  moves it.

### 5. Hand installs (the intent's open question 3)

**The existing rule stays.** The activation step (`modules/home.nix:1110`)
leaves a real directory at the plugin's id alone.

**The hook reports it.** The hook gains one line: when the declared id's
directory is not a symlink, it logs "nixarchy.menu is a hand install;
`rm -rf ~/.config/omarchy/plugins/nixarchy.menu` and log in again to use the
declared one" to `nixarchy-default-plugins`. The same text goes in the flake.md
section.

**Companion change** (a nixarchy-menu issue, not this repo):
`bin/nixarchy-menu install` refuses when
`~/.config/omarchy/plugins/nixarchy.menu` is a symlink into `/nix/store`,
because nixarchy manages it there.

## Alternatives rejected

- **`menu = false` in the `defaultPlugins` default attrset:** the wholesale
  replacement trap in §2. A host setting any other key would turn the menu on.
- **A `gate` for opt-in:** `gate` means "doesn't apply to this host" and has
  no user-facing override. Opt-in needs a default the user can flip, so it
  belongs in `defaultPlugins`.
- **Disabling the competing clone after enabling:** that brings the stock menu
  back through `restoreCloneSource` (`PluginRegistry.qml:555`).
- **Hard-coding `evindor.keystroke`:** it misses hand installs under other ids
  and future clones. Matching on `clonedFrom` is exact and costs one `jq`.
- **Replacing a hand-copied directory at activation:** the "your own
  directory" rule protects real checkouts for every plugin. Weakening it for
  one id is a special case with a data-loss edge.

## Risks

- **Hook regressions for existing defaults.** Mitigation: the default
  `placement = "right"` reproduces today's call exactly. `tests/options.nix`
  asserts the hook still passes `right` for an existing entry.
- **Unexpected pre-disable.** Only same-`clonedFrom`, currently-enabled
  plugins are touched, and only on the first enable of the clone.
  - On razer that is `evindor.keystroke` (installed, already disabled, so
    untouched).
  - On a host that never opts in, nothing changes, because the menu isn't in
    `resolvedDefaults`.
- **Shell reload during enable.** A disable followed by an enable means two
  plugin reloads. Quickshell 0.3.1's reload segfault (#958) is fixed, and the
  hook already waits with `OMARCHY_SHELL_IPC_TIMEOUT=30s`.
- **Closure size.** It is **84.7 MiB** (measured, `nix path-info -S`). The
  plugin references the Smart Match engine (`keystroke-matching-0.1.0`) and
  **both** models (`keystroke-model-small`, `keystroke-model-large`), plus
  glibc. That is acceptable for opt-in, and it only lands on hosts that set
  `menu = true`. Before any on-by-default flip, the follow-up should decide
  whether the large model belongs in the default closure. That is a
  nixarchy-menu packaging question, noted in the follow-up issue.

## Verification

- **Eval and build:**
  - `nix flake check` (including `checks.options`)
  - `nix build .#nixosConfigurations.<test host>` evaluates with
    `defaultPlugins.menu` unset (off) and with it `true`
- **`tests/options.nix`, new cases:**
  1. With `defaultPlugins` unset, the menu isn't in the hook's id list.
  2. With `defaultPlugins = { podman = false; }`, the menu is still off (the
     §2 trap).
  3. With `defaultPlugins.menu = true`, it is in the list, with an empty
     placement. An existing entry still passes `right`.
  4. The hook text contains the same-`clonedFrom` pre-disable before the
     enable.
- **Razer (claimed on the bus):**
  - Opt in and rebuild.
  - Remove the hand copy. The hook log shows the `rm` hint before removal.
  - Log in again and check:
    - `omarchy-plugin-list --json` shows `nixarchy.menu` enabled and
      `omarchy.menu` disabled
    - `evindor.keystroke` is still disabled
    - the bar's menu button is in the same slot as before
    - `Super+Space` opens nixarchy-menu
  - Set `menu = false` and check that the stock menu comes back.
- **Closure:** `nix path-info -S` of the pinned plugin is re-measured and
  recorded in the plan. It was 84.7 MiB at the spec.

## Amendment 1: the off switch restores the source (user decision, 2026-09-24)

**Found on razer** (plan step 7, case 3): when a declared clone is no longer
declared, HM's stale-symlink cleanup removes its link. The shell then no
longer knows the plugin, but the source (`omarchy.menu`) stays in
`disabledPlugins`, and the clone's bar entry stays behind as an orphan. The
result is **no menu button, and Super+Space opens nothing**. Removing files
never runs `restoreCloneSource`, which only a disable does, so the intent's
"clean off switch" outcome was not met. The user chose to have the hook
restore the source.

**Design:**

1. **The marker records the source.** When the hook enables a default (or
   finds it already on), the enabled-once marker holds its `clonedFrom`
   (`printf '%s\n' "$src" >"$state/$id"`). For a plugin that isn't a clone
   the marker is empty, exactly as today. Old markers are empty, so they
   never trigger what follows.
2. **Restore pass, at the start of the hook.** For each marker whose id is
   **not** declared any more, whose content (the source) is non-empty, and
   whose plugin directory `$plugins/$id` is gone, the clone was dropped.
   Once the shell answers, the hook, for each dropped clone:
   - runs `omarchy-plugin-enable "$source" --before "$id"`, so the source
     lands right beside the clone's orphaned bar entry, in its place
   - runs `omarchy-plugin-disable "$id"`. With no manifest, that only
     removes the orphaned entry.
   - removes the marker once the enable worked, so it never runs again and a
     later re-declare enables afresh

   A marker whose directory still exists (a hand install at that id) is left
   alone.
3. **Early exit.** The hook's "nothing to do, exit" now needs both the
   to-do list and the dropped-clone list to be empty.

**Limit, documented:** the hook exists only while at least one default
plugin resolves (`lib.mkIf (resolvedDefaults != { })`). A host that turns off
the menu **and every other default** gets no restore. That's rare (`pkg` and
`rebuild` are on wherever nixarchy is), and the flake.md section gives the
one command, `omarchy plugin enable omarchy.menu`.

**Verification added:**
- **checks.options:**
  - The hook text writes `$src` into the marker.
  - The restore pass (`--before`) comes before the to-do loop.
  - The early exit tests both lists.
- **razer:** re-run case 3. After `menu` is dropped, the menu button is back
  in the same slot, Super+Space opens the stock menu, and the marker is gone.
