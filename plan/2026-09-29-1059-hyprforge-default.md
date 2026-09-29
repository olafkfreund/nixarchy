---
status: approved
issue: 1059
spec: spec/2026-09-29-1059-hyprforge-default.md
---

# Plan: Ship Hyprforge as a default plugin

## Approved decisions

These are carried over from the spec, so the plan can be followed without
opening it.

- **The input.** `nixarchy-hyprsettngs`, `flake = false`, pinned at `2392ad6`
  (the fork, identical to upstream's HEAD), with a
  `# Why: docs/internals/flake.md#…` pointer.
- **Packaging.** `hyprforgePlugin` is a `runCommand` in `modules/home.nix`,
  shaped like `herdrSessions`: copy the tree, drop `test/` and `preview.png`,
  and fail unless `LICENSE` contains `Copyright (c) 2026 Aziz`.
- **The entry.** `defaultPluginSet.hyprforge` has `id = "aziz.hyprforge"`, is
  ungated, and has no `placement`. Its `packages` are `pkgs.lua`,
  `pkgs.diffutils`, `pkgs.libnotify` and `pkgs.wl-clipboard`, all `lowPrio`
  through the existing mechanism.
- **The fix.** `pkgs/omarchy/default.nix` makes Omarchy's
  `config/hypr/hyprland.lua`, the store file `--config` names, gain
  `require("default.hypr.require_optional").module("hypr.hyprforge") -- Hyprforge (Omarchy plugin)`
  after `require("hypr.autostart")`, with `substituteInPlace --replace-fail`.
  - It is optional, a no-op without the file, and it is the exact text
    Hyprforge's `hasHook` matches.
  - New homes never see Connect. Existing homes see a harmless banner, which
    is documented.
  - Turning the plugin off leaves the saved file applied until it is deleted,
    which is documented.
- **No menu row and no keybinding.** Hyprforge's own `.desktop` entry puts it
  under Super+Space.
- **The id stays `aziz.hyprforge`.** Upstream's `node` tests are not run here.

## Steps

1. **`flake.nix`: the input.**
   - Add the input with its `# Why:` pointer, then run
     `nix flake lock --update-input nixarchy-hyprsettngs`.
   - Verify: the lock diff adds one node and moves nothing else.
2. **`modules/home.nix`: `hyprforgePlugin` and the `hyprforge` entry.**
   - The `runCommand` goes next to `herdrSessions`; the entry goes in
     `defaultPluginSet` with a 2–3 line comment.
   - Update the `defaultPlugins` description to name Hyprforge.
   - Run `nix fmt`, then check `git diff --stat` (the formatter hook, §5).
   - Verify: `nix build` the entry's `src`. There is no `test/`,
     `manifest.json` has `id = aziz.hyprforge`, and `LICENSE` names Aziz.
3. **`pkgs/omarchy/default.nix`: the hook.**
   - Add the `substituteInPlace --replace-fail` on
     `$out/share/omarchy/config/hypr/hyprland.lua`. It sits beside the seed's
     `bindings.lua` edit, with a one-line comment and a `# Why:` pointer to
     `pkgs/AGENTS.md`.
   - Use `printf`, not a heredoc (§5).
   - Verify: build `.#omarchy`. The file has the line exactly once, directly
     after `require("hypr.autostart")`.
   - Break proof: point `--replace-fail` at a non-existent line, and the
     build fails. Then restore.
4. **`tests/options.nix`.**
   - `hyprforgeIsADefault`:
     - on: `defaultHomeOn` installs `aziz.hyprforge`, and the hook lists it;
     - off: `homeOn { } { programs.nixarchy.defaultPlugins.hyprforge = false; }`
       does neither.
   - `hyprforgePackaged`, a runtime assertion: `$src/LICENSE` names Aziz,
     `$src/test` is absent, and `$src/manifest.json` has the id.
   - `noDefaultsHome` gains `hyprforge = false`.
   - `toolNames` gains `"lua"`.
5. **`tests/plugin.nix`.** The empty-directory node gains `hyprforge = false`,
   with a one-line comment.
6. **`tests/session.nix`: the §2 probe.** Placed after the desktop is up, it
   uses the existing `on_desktop()`:
   - Write `/home/omarchy/.config/hypr/hyprforge.lua` as the user, with one
     distinctive integer option. Use `general:border_size = 7`, in the
     `hl.config({ … })` form Hyprforge's `Engine.js` emits; read the exact
     form from `Engine.js` first.
   - `hyprctl reload`, then assert `hyprctl getoption general:border_size -j`
     reports 7.
   - Remove the file and reload.
   - The assertion message names #1059 and says "saved but never loaded".
   - Break proof: remove the store hook (step 3), and the probe must fail.
     That runs in CI, not locally: a VM check is only run locally with nothing
     in flight, and it costs ~10–20 min. If the local slot is free, run it
     locally instead.
7. **Counts and docs.**
   - `docs/index.md:90`: fifteen, twelve always on. Then
     `readme-counts.sh --check`.
   - `docs/manual/plugins.md`: a table row with `<!-- aziz.hyprforge -->`, and
     a "Hyprforge" section covering:
     - what it solves and what it does;
     - how to open it;
     - the Connect note for existing homes;
     - that turning it off keeps saved settings until the file is deleted;
     - upstream credit and the licence.
   - `docs/llms.txt:115`: add "Hyprforge" to the on-by-default list.
   - `docs/internals/flake.md`: a new section titled "Hyprforge, on by default
     (#1059)", with its anchor, covering:
     - why `flake = false`;
     - the licence check;
     - the hook patch;
     - the measured size (`nix path-info -S` on the plugin plus lua);
     - bump steps, which read the diff since the pinned commit (third-party
       code).
   - `README.md`: a plugin section in the register of its neighbours.
   - `tests/demo/screencast/shots.nix`: a shot entry for `aziz.hyprforge`.
     `shot-coverage.sh` lists every id and no workflow runs it (§4, a
     hand-maintained list fails open).
   - Verify: `grep -rn "aziz.hyprforge"` covers every list the research named.
8. **Local checks, in cost order, each only with `gh run list` empty.**
   - `nix fmt -- --ci`, statix, deadnix, `readme-counts.sh --check`.
   - `checks.options`. Break proof: delete the `hyprforge` entry, and
     `hyprforgeIsADefault` fails. Restore with `git checkout HEAD --` after a
     baseline commit (§5).
9. **PR.** Use the template, and write "Closes #1059". Link the three files,
   and include the break outputs from steps 3, 6 and 8. Say that `session`
   carries the §2 probe and that its failing run is CI's first. Merge when
   green and `mergeable`.

## Tests

| Command | Expected |
| --- | --- |
| `nix build .#omarchy` | the store `hyprland.lua` has the hook once, after `hypr.autostart` |
| the same, `--replace-fail` broken | build fails |
| `checks.options` | green, including `hyprforgeIsADefault` and `hyprforgePackaged` |
| `checks.options` with the entry removed | `hyprforgeIsADefault` fails |
| `checks.session` | green, border_size probe reads 7 |
| `checks.session` with the hook removed | the probe fails |
| `readme-counts.sh --check` | exit 0 with fifteen and twelve |
| `nix fmt -- --ci`, statix, deadnix | clean |

## Rollback

Revert the squash commit.

- Hyprforge stops being installed, and the store hook goes with it.
- `~/.config/hypr/hyprforge.lua`, if a user saved anything, stays on disk but
  is no longer loaded.
- The enabled-once marker stays, so a later re-add does not re-enable it for
  someone who turned it off.

## Deviations, recorded while implementing

- **Step 2:** `pkgs.lua5_4`, not `pkgs.lua`. nixpkgs' `lua` is 5.2. Arch's
  `lua`, which upstream calls "already a Hyprland dependency" and
  `baseline.lua` was written against, is 5.4. Both ran `baseline.lua` to
  identical output on a thin input, which is too thin to rely on 5.2.
- **Step 4:** `hyprforgeIsADefault`'s off state reads the already-bound
  `noDefaultsHome`, `defaultHome` and `fixtureNixarchyOff`, as
  `herdrIsADefault` does, not a new `homeOn { … hyprforge = false; }`. Every
  `homeOn` is a full NixOS evaluation (#747). `noDefaultsHome` gains
  `hyprforge = false`, so the opt-out is still what is tested.
- **Step 4:** `hyprforgePackaged` checks the manifest id with `grep -E`,
  because the check has no `jq` on its PATH.
- **Step 6:** the probe parses `hyprctl getoption -j` in Python with a short
  retry, not `… | grep -q`. That is the #1058 trap this repo just documented.
  It imports `json` and `time` locally, since the script's own `import json`
  comes 1,300 lines later.
- **Step 7, no shot entry.** `tests/demo/screencast/shot-coverage.sh` is
  already red on `main`: `io.github.nobledoodle.omarchroma` and
  `nixarchy.menu` are missing, and no workflow runs it. A real Hyprforge shot
  needs a recorded, gated scene, and a name added only to satisfy the grep
  would be a false claim (§4). Filed as an issue for all three instead.
- **Step 3:** the `# Why:` pointer at the hook lands on a new
  `pkgs/AGENTS.md` section, "Hyprforge's hook lives in the store
  hyprland.lua".
