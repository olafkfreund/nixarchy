---
status: approved
issue: 766
spec: spec/2026-09-18-766-default-plugins.md
---

# Plan: nixarchy-pkg, -podman, -distrobox and -microvm ship with nixarchy and are on by default

## Approved decisions (self-contained)

- **Enabling: one mechanism for every install.** A Home Manager-generated
  `~/.config/omarchy/hooks/post-boot.d/default-plugins` hook, run by upstream's
  `sleep 2 && omarchy-hook post-boot` (autostart.lua). For each resolved
  default id that has no marker in `~/.local/state/nixarchy/enabled-once/<id>`,
  the hook:
  1. waits up to 30 s for `omarchy-shell shell ping`, and exits 0 quietly if
     the shell never answers;
  2. runs `omarchy-shell shell rescanPlugins` once;
  3. if `omarchy-plugin-list --json` already shows the plugin enabled, writes
     the marker only;
  4. otherwise runs `omarchy plugin enable <id> right`, and writes the marker
     **only on success**. A failure is logged with
     `systemd-cat -t nixarchy-default-plugins` and retried at the next login.

  nixarchy never writes `shell.json`, and there is no vendored-default
  `shell.json` layer and no systemd unit.
- **Option.** `programs.nixarchy.defaultPlugins`: attrsOf bool, with `pkg`,
  `podman`, `distrobox` and `microvm` each defaulting to true at `mkDefault`.
  Everything is gated on `osConfig.programs.nixarchy.enable or false`, so
  standalone Home Manager gets nothing.

  | id | installed when |
  |---|---|
  | nixarchy.pkg | nixarchy enabled |
  | nixarchy.podman | `osConfig.virtualisation.podman.enable` |
  | nixarchy.distrobox | `osConfig.programs.nixarchy.services.boxes.enable` |
  | nixarchy.microvm | nixarchy enabled, with a runtime `nixarchy-vm --check` like the Sandbox rows |

  Installation goes through the existing `programs.nixarchy.plugins.<id>.src`,
  which validates, symlinks and reconciles.
- **Helper** `nixarchy-plugin`: `--enabled <id>` is a jq read of `shell.json`.
  Otherwise it toggles an enabled plugin, or sends a notification saying where
  to turn it on. Rows and binds call the helper, never
  `omarchy-shell shell toggle` directly.
- **Menu rows:**
  - new `install.packages` and `apps.podman`;
  - the `trigger.box` parent opens the distrobox panel and its children go;
  - the `trigger.vm` parent opens the microvm panel and its children go.
- **Binds:** Super+Alt+N (pkg), O (podman), D (distrobox), V (microvm),
  appended with an asserted anchor to the seed `config/hypr/bindings.lua`. New
  homes get them; existing homes don't. None of the four conflicts with
  upstream or nixarchy binds.
- **Podman** is a `kind = "plain"` row in `data/services.nix`
  (`virtualisation.podman.enable`), off by default. There is no nixarchy option.
- **Inputs:** commit pin plus `inputs.nixpkgs.follows = "nixpkgs"`, following
  nixi (`flake.nix:129-180`). Each is re-exported beside `nixi`
  (`flake.nix:821`). No cache-allowlist entries. ISO size is measured per input,
  and the pin-bump procedure is documented in `docs/internals/flake.md`.
- **Retiring `nixarchy box` (PR D):**
  - templates are generated as `/etc/nixarchy/box-templates.json`;
  - `pkgs/box.nix`, the `box)` verb, the rows and the menu-verbs box scans go;
  - `checks.box-template` and `checks.box-boot` keep their names and are
    retargeted;
  - the `build.yml` comment edits are a human's (§4, §11);
  - the whole PR is blocked on the plugin gaining templates-from-JSON,
    `promote`, `--check` and `list`.
- **Correction to the approved spec** (found while planning). Spec D2 asserts a
  manifest id equals its attribute name for **every** declared plugin. That
  would break existing configurations: the option installs "under the id from
  its own manifest.json" (`modules/home.nix:533`), so attribute names are free,
  and `tests/plugin.nix:146` declares `bar-toggle`. This plan puts the id
  assertion on the **default set only**, where the attribute name is ours. The
  spec gets the same edit in PR A's first commit.

## PR A — the mechanism (branch `feat/766-default-plugins`)

1. Read the bus (`read_new #nixarchy-agents`, §9). Check
   `gh run list --limit 8 --json status -q '[.[]|select(.status!="completed")]|length'`
   is 0 before any local build, and repeat before every build below (§6).
2. `spec/2026-09-18-766-default-plugins.md`: narrow the D2 assertion as in
   the correction above → verify by `git diff` showing only that paragraph.
3. `modules/home.nix` options (`:418` onward): add `defaultPlugins`
   (`lib.types.attrsOf lib.types.bool`, default
   `{ pkg = true; podman = true; distrobox = true; microvm = true; }`), with a
   description naming each gate and saying that opting out never reaches into
   `shell.json` → verify by `nix eval` of
   `homeConfigurations`-style fixtures in step 9.
4. `modules/home.nix` `let`: `defaultPluginSet`, a map from id to
   `{ src; enabled = gate && cfg.defaultPlugins.<name>; }`. In PR A the `src`
   map is **empty**. The real inputs arrive in B, C, E and D, so PR A ships the
   mechanism with no behaviour change. Tests use a fixture (step 9).
   - `resolvedDefaults = lib.filterAttrs (_: p: p.enabled) defaultPluginSet`.
   - Assert, for each resolved id, `manifest.id == id` (jq in the existing
     `validatedPlugins` runCommand, only for these) → verify by the §1 break in
     the Tests table.
5. `modules/home.nix` config (inside `lib.mkIf cfg.enable`, `:546`):
   - `programs.nixarchy.plugins = lib.mapAttrs (_: p: { src = lib.mkDefault p.src; }) resolvedDefaults;`
     (plain assignment of the attrset; `mkDefault` only on the scalar `src`,
     per `modules/services/default.nix`'s header);
   - `xdg.configFile."omarchy/hooks/post-boot.d/default-plugins"` (executable),
     only when `resolvedDefaults != {}`. It is generated with the id list
     inlined. Commands come from `${cfg.package}/bin` and `${pkgs.jq}/bin` by
     store path, as the `config-repo` hook at `:1409` does, because a hook runs
     with the session PATH.
   - Verify with step 9's cases.
6. `modules/apps.nix`: add `nixarchy-plugin` (`writeShellApplication`,
   `runtimeInputs = [ jq coreutils ]` plus the omarchy package for
   `omarchy-shell` and `omarchy-notification-send`). Every command it calls is
   declared, because an undeclared one is a runtime failure (§7). Install it
   beside the other nixarchy commands (`:2915-2922`). Verify by
   `nixarchy-plugin --enabled` returning 1 on a fixture `shell.json` without
   the id, and 0 with it (a `runCommand` case in `checks.options`, step 9).
7. `modules/AGENTS.md:863-880`: retitle the section and record the reversal.
   Its content: what the owner decided (2026-09-18, #766), why hook plus IPC
   and not a file write (the whole-file writer at `shell.qml`), the marker
   semantics, and that nixi's own self-enable stays nixi's. Add a
   `# Why: modules/AGENTS.md#<anchor>` pointer at the new code (§7). Update the
   `plugins` option description (`home.nix:535-540`), which today says "does
   not enable it". It keeps saying that for plugins you declare, and names the
   defaults as the exception.
   *Deviation, made during implementation:* `nixarchy-plugin` is
   `pkgs/nixarchy-plugin.nix`, called from `apps.nix`, not inline. This is
   the `pkgs/secret.nix` precedent: `tests/options.nix` runs the real command
   against fixture `shell.json` files.
8. `git add` every new file before any evaluation (§5).
9. `tests/options.nix`, with a fixture plugin (a `runCommand` directory holding
   a valid `manifest.json`, id `nixarchy.fixture`) injected through a
   test-only `_module.args` or a `defaultPluginSet` override.
   *Deviation, as settled during implementation:* it goes through an
   **internal** option, `programs.nixarchy.defaultPluginSet` (id, src, gate),
   following the `installerManaged`/`tree` precedent in `nixos.nix`. Later PRs
   fill that same option with the real inputs. A read-only internal
   `pluginChecks` exposes the validation derivations, so the renamed-id case
   is a `testers.testBuildFailure` inside `checks.options` and needs no new
   check name. The cases:
   - `homeWith {}`: no fixture src and no hook file;
   - `homeOn {} {}`: both present;
   - `homeOn` with `defaultPlugins.fixture = false`: both absent;
   - the hook text lists exactly the resolved ids;
   - `nixarchy-plugin --enabled` true and false.

   Verify by building `.#checks.x86_64-linux.options --print-build-logs`
   unpiped (§1), after step 1's queue check.
10. `tests/plugin.nix` (VM): keep the `defaultPlugins` all-false machine for
    the empty-directory case (beside `services.nixi.enable = false`, `:138`).
    Add a second node or a second boot with the fixture default on, and assert:
    - after login, `omarchy-plugin-list --json` shows it `enabled`, with the
      widget in `bar.layout.right`;
    - a pre-seeded user `shell.json` still gets it enabled, by IPC, in a live
      session;
    - `omarchy plugin disable` then re-login leaves it disabled.

    Verify by building `.#checks.x86_64-linux.plugin`, which is already in a
    workflow, so no gate edit is needed.
    *Deviations, made during implementation:*
    - It is a second node, `defaults`: `machine` plus one default, the
      omteleprompt pin this file already fetches. It boots only after
      `machine` shuts down, and the test's `rec` lets it import `machine`.
      Every seeded home already has a user shell.json, so this one scenario is
      also the pre-seeded case.
    - The hook waits up to **120 s** for the shell, not 30 s, and sets
      `OMARCHY_SHELL_IPC_TIMEOUT=30s` unless the user set one. This file
      already found both limits too short in a VM: the shell waits 240 s, and
      upstream's 2 s IPC budget was cut off while plugins reloaded. The hook
      runs in the background at login, so waiting costs nothing visible.
11. `tests/AGENTS.md`: a line on the fixture plugin and why the real four are
    not used here (network and pin churn).
12. `nix fmt -- --ci`, `nix run nixpkgs#statix -- check .` and
    `nix run nixpkgs#deadnix -- --fail .`.
13. Squash to a real subject (§8). Push. Open the PR with the template filled
    in: links to intent, spec and plan, the failing outputs from the Tests
    table, `Refs #766` (not Closes; B to E remain).

## PR B — nixarchy-pkg (branch off the merged A)

1. `flake.nix` inputs: add `nixarchy-pkg` with the URL at a commit on its
   `main`, and `inputs.nixpkgs.follows = "nixpkgs"`. Add the house "why"
   comment. Re-export `packages.<sys>.nixarchy-pkg = inputs.nixarchy-pkg.packages.${system}.default`
   beside `nixi` (`:821`). Verify with `nix flake lock` and a lock diff showing
   one new node and no second nixpkgs.
2. `modules/home.nix` `defaultPluginSet`: add the `nixarchy.pkg` entry. The
   module receives the package the same way it receives nixi's
   (`inputs`/`self` specialArgs), with gate "nixarchy enabled". Verify by the
   `options` cases from A, now also with the real id (present on `homeOn`,
   absent on `homeWith`).
3. `modules/apps.nix` overrideSpec: add `install.packages`:
   - icon `󰏖`, label "Packages";
   - `action = "nixarchy-plugin nixarchy.pkg"`;
   - `when = "nixarchy-plugin --enabled nixarchy.pkg"`;
   - description "Browse, add and apply packages in a panel".

   The existing `install.search` and `install.apply` stay. Verify with the
   generated menu containing the row (`options` case).
4. `pkgs/omarchy/default.nix`, beside the QML splices (`:1845-1919`): assert
   the anchor, the last line of upstream's `config/hypr/bindings.lua` (the MX
   Keys example block), then append the Super+Alt+N bind. The O, D and V lines
   join in their own PRs. Verify: the build fails if the anchor is missing.
   §1: point the anchor at a nonexistent line and watch it fail.
5. `tests/menu-verbs.nix`: a new scan, `\bnixarchy-plugin +[a-z.]+` (field 2).
   It collects every id a row names and checks each against the manifest ids
   of the plugins installed on the `reference` machine plus boxes. Read the ids
   from `eval.config.home-manager.users.<user>.programs.nixarchy.plugins`
   sources, or from the re-exported packages' `manifest.json` in PR B. Floor:
   at least one row. Verify with the §1 break in the Tests table.
6. `docs/internals/flake.md`: the input's "why", its measured size, and the
   pin-bump procedure. Measure with
   `nix path-info -S $(nix eval --raw .#inputs.nixarchy-pkg.outPath)`, or with
   `nix flake archive --json` for the tree.
7. Docs:
   - `docs/manual/other-packages.md` and `getting-started.md` (the Packages
     panel, Super+Alt+N);
   - the README feature table, and `readme-counts.sh` if a count moves (§4:
     teach it any new word);
   - `docs/manual/configuration.md` Plugins (`defaultPlugins`).
8. `git add`, then fmt, statix and deadnix. Run `checks.options`, `plugin` and
   `menu-verbs`, with the queue check before each (§6).
9. Open the PR with a real subject, `Refs #766`, links to all three artifacts,
   the failing outputs, and the ISO number.
10. Then a Discussions post: added, changed, coming.

### PR B — as implemented (deviations)

- **Step 3's options case for the row is covered by step 5 instead.** The
  menu-verbs plugin scan fails if no row opens a plugin (floor 1), and fails
  if a row names an id that is not installed, which is strictly more than
  "the row is present". No separate options case.
- **Two PR A cases moved, both retargeted, not weakened.**
  `defaultPluginsNoHookWhenEmpty` read the default home, which was empty
  only until `nixarchy.pkg` joined the set; it now reads a home with
  `defaultPlugins.pkg = false`. `tests/plugin.nix` sets `pkg = false`
  beside `services.nixi.enable = false`, for the reason recorded there: its
  empty-directory state has to stay reachable.
- **The seed bind is appended with `printf`, not a heredoc.** A heredoc's
  column-0 lines would drop the whole `installPhase` string's common indent
  to 0 and break the exact-whitespace `--replace-fail` strings elsewhere in
  it (`pkgs/AGENTS.md`).
- **The input's reasoning lives in `docs/internals/flake.md`** behind a
  `# Why:` pointer, as that file's convention requires, rather than as a
  long comment in `flake.nix`.
- **The plugin's Apply is not fixed here.** Its adapter still pipes
  `printf 'n\ny\n'` into `nixarchy-apply`, which declines the switch on a
  machine without `nixarchy-preview` (every nixarchy machine has it, since
  it ships in the omarchy package). #765 PR 2's `--yes`/`--no-preview`
  retires it.
- **The package output omits the plugin's LICENSE** (its flake copies an
  explicit file list). An upstream fix, like the wave-2 plugins (#770-#774).

## PR C — podman (approved 2026-09-19)

Branch `feat/766-pr-c-podman`, off `main` after A (#775). It follows PR B's shapes
(#780): the `defaultPluginSet` entry, the helper-driven row, the seeded bind
behind the asserted anchor, and the menu-verbs id scan. If #780 has not merged
when C starts, C rebases onto it, because both append to the same seed-bind
`printf` and the same `defaultPluginSet` block.

Approved decisions it carries: podman is a Services catalogue row of
`kind = "plain"` (the real line `virtualisation.podman.enable = true;`, no
nixarchy option, per `data/services.nix:10-27`). Rootless Docker stays the
default engine (`modules/nixos.nix:1403-1420`). The plugin is on wherever
podman is on, through that row or through Boxes (`boxes.nix:86` sets it at
`mkDefault`). The bind is Super+Alt+O, and nothing upstream or on the owner's
machine binds it.

1. `data/services.nix`: a `podman` row with `kind = "plain"`,
   `option = [ "virtualisation" "podman" ]`, category Development, and a note:
   "Rootless containers next to Docker, which stays the default. The
   `docker` command keeps meaning Docker (`dockerCompat` is left off)."
   → verify: the generated menu has `install.service.podman` with action
   `nixarchy-service-enable podman`, and `nixarchy-service-enable podman`
   writes the plain upstream line (the existing catalogue path, unchanged).
2. `flake.nix`: input `nixarchy-podman` =
   `github:olafkfreund/nixarchy-podman/<commit on master>` (03d9f02 at
   drafting) with `inputs.nixpkgs.follows = "nixpkgs"`, plus the house "why"
   pointer. Re-export `packages.<sys>.nixarchy-podman` beside `nixarchy-pkg`.
   → verify: the lock diff adds one node and no second nixpkgs. The package
   output already carries `LICENSE` (its `flake.nix:15-17` lists it in `files`),
   and a `test -f $out/LICENSE` in step 7's check proves it stays.
3. `modules/home.nix` `defaultPluginSet.podman`:
   `{ id = "nixarchy.podman"; src = inputs.nixarchy-podman.packages.<sys>.default;
   gate = osConfig.virtualisation.podman.enable or false; }`. `or false` holds
   for a null `osConfig` (checked: `null.a.b or false` is `false`), so
   standalone Home Manager stays inert on top of `resolvedDefaults`' own
   nixarchy gate. → verify by step 6's cases.
4. `modules/apps.nix`:
   - `podmanEnabled = cfg.enable && config.virtualisation.podman.enable`,
     beside `boxesEnabled` (`:16`), with the same reason: the row must not
     exist at all when podman is off.
   - `lib.optionalAttrs podmanEnabled { "apps.podman" = { … }; }` with icon
     ``, label "Podman", `action = "nixarchy-plugin nixarchy.podman"`,
     `when = "nixarchy-plugin --enabled nixarchy.podman"`, a description, and
     aliases `podman containers images volumes networks`. **No `docker`
     alias**, unlike the plugin's own snippet (`share/omarchy-menu.jsonc:11`):
     on a machine whose engine is Docker, searching "docker" must not open a
     podman panel.

   → verify: the row is present in the menu on a podman machine and absent on
   the reference one (step 6).
5. `pkgs/omarchy/default.nix`, the seed-bind `printf` from PR B: append
   `'o.bind("SUPER + ALT + O", "Podman", "nixarchy-plugin nixarchy.podman")'`.
   → verify: the anchor assertion from B still guards the block, and the built
   seed ends with the N and O lines.
6. `pkgs/nixarchy-plugin.nix`: when the plugin **directory** is missing from
   `~/.config/omarchy/plugins/<id>`, say "not installed on this machine"
   instead of "turned off … omarchy plugin enable". The O bind is seeded for
   every new home but the plugin exists only where podman is on, so today's
   message would send a user to a command that fails. One `[ -d … ]` test, no
   other change. → verify with a runtime case in `options` next to the
   existing helper cases.
7. `tests/options.nix`: cases across the fixture split. Podman-on machines need
   a NixOS module outside `programs.nixarchy`, which `configNamed` cannot take
   (`:167-189` merges settings into `programs.nixarchy` only). Add one small
   wrapper, `homeOnMod = osModule: hmSettings:` building `osConfig` from
   `configNamed` plus `osModule`, and leave existing callers alone.
   - `podmanPluginGate`:
     - `on`: `homeOnMod { virtualisation.podman.enable = true; } { }` has
       `nixarchy.podman` and the hook lists it;
     - `off`: `defaultHomeOn` has neither.
   - `podmanViaBoxes`:
     - `on`: `homeOn { services.boxes.enable = true; } { }` has it;
     - `off`: boxes on plus `homeOnMod { virtualisation.podman.enable = lib.mkForce false; }`
       lacks it.
   - `podmanRow`: `apps.podman` is in the generated menu exactly when podman is
     on (reuse the `podmanViaBoxes` machines).
   - `pluginNotInstalledMessage`: the helper's not-installed path (step 6).
   - Standalone: `defaultHome` (no `osConfig`) has no `nixarchy.podman`.

   **Cost (#747):** each new machine is a full NixOS eval inside the 11.5 GB
   check. Two new ones only (podman-on, boxes-with-podman-forced-off), each
   bound once and reused, never inlined per case. Record `checks.options`'
   peak RSS before and after in the PR.
8. `tests/menu-verbs.nix`: its eval is reference plus Boxes, so podman is on
   there, and `apps.podman`'s id is checked against the installed manifests by
   B's scan with no change. Raise the plugin-row floor from 1 to 2, so losing
   either row fails.
9. Docs:
   - `docs/manual/development-tools.md`, beside rootless Docker: the Services
     row, the panel, Super+Alt+O, and that `docker` stays Docker;
   - `docs/manual/boxes.md`: one line saying Boxes also brings the Podman panel;
   - `docs/manual/configuration.md` Plugins (`defaultPlugins.podman = false`);
   - `docs/internals/flake.md`: the input's why, measured size and pin-bump
     procedure (the `master` branch, not `main`);
   - `modules/AGENTS.md`'s default-plugins section: the podman gate and why it
     reads `virtualisation.podman.enable` rather than a nixarchy option;
   - the README feature row, and `readme-counts.sh` if a count moves.
10. `git add`, fmt, statix and deadnix. Run `checks.options`, `menu-verbs`,
    `plugin` and `omarchy` through `heavy-build.sh`.
11. Open the PR with a real subject, `Refs #766`, links to the three
    artifacts, the red outputs, the ISO/input size and the RSS numbers.

**Tests and their §1 breaks** (each red captured before green; restore with
`git checkout HEAD -- <path>`):

| check | expected | break that must go red |
|---|---|---|
| `options` `podmanPluginGate` | pass | gate read as `true` |
| `options` `podmanViaBoxes` off-half | pass | gate read from `services.boxes.enable` instead of podman |
| `options` `podmanRow` | pass | drop `lib.optionalAttrs podmanEnabled` |
| `options` `pluginNotInstalledMessage` | pass | remove the `[ -d … ]` branch |
| `menu-verbs` floor 2 | pass | delete the `apps.podman` row |
| `menu-verbs` id scan | pass | rename the row's id to `nixarchy.podmanx` |

**Known limits, named in the PR, not fixed here:**
- The panel's `d` key opens `podman-tui`, which nixarchy does not install
  (`PodmanState.qml:235`). Without it the key fails. See the open question.
- The Docker menu (lazydocker) and the Podman panel sit side by side. Nothing
  merges them; they are different engines.

## PR D — distrobox (approved 2026-09-19)

**What changed since the outline:** the plugin (`nixarchy.distrobox`, MIT,
LICENSE shipped in its package) gained templates on 2026-09-18
(`feat/8-assemble-templates`, main at `f68ac27`), but in a different shape. It
reads a **`distrobox assemble` INI file**, set by the plugin setting
`templatesFile` (manifest default `~/.config/distrobox/boxes.ini`), not
`/etc/nixarchy/box-templates.json`. It still has **no `promote`, no `--check`
and no `list`**.

**Departure for the owner to approve:** retiring `nixarchy box` is **split out**
of PR D into a new issue, filed on approval. It stays blocked on those three
plugin features. PR D ships the panel as the default Boxes UI, and the
`nixarchy box` CLI stays as the terminal interface (`checks.box-template`,
`checks.box-boot` and `build.yml` are untouched). So PR D closes #766 only
together with PR E, and the retirement lives on in its own issue.

**Templates stay single-sourced, and nixarchy never writes `shell.json`.**
`data/box-templates.nix` already holds each template's `ini` as verbatim
assemble syntax. Both templates use only `image`, `pull`, `replace=false` and
`start_now=false`, all of which the plugin's parser accepts (`Model.js:1060,
1180-1206`). So:
- NixOS writes the file (`modules/services/boxes.nix`, when boxes are on):
  `environment.etc."nixarchy/box-templates.ini"`, one `[<name>]` section per
  template, containing its `ini` block.
- The plugin finds it through its **manifest default**, not a user setting:
  nixarchy's wrapper (like #786's `gitlabPipelines`) copies upstream's package
  and rewrites `barWidget.defaults.templatesFile` in `manifest.json` to
  `/etc/nixarchy/box-templates.ini` with `jq`. A user who sets their own path
  in Setup → Plugins still wins, because `shell.json` overrides the manifest.
- **Cost:** a user's own `~/.config/distrobox/boxes.ini` is no longer read by
  default. The plugin reads one file. The fix belongs upstream: let
  `templatesFile` take a list, or read the system file plus the user's. It's
  documented in `boxes.md` and noted in the PR, not filed by us.

### Steps

1. `flake.nix`: input `nixarchy-distrobox` at `f68ac276dc05`, with `follows`,
   and a `# Why:` pointer to a new `docs/internals/flake.md` entry.
   → verify: `nix flake metadata` shows one node and no second nixpkgs.
2. `modules/services/boxes.nix`:
   `environment.etc."nixarchy/box-templates.ini".text` built from
   `data/box-templates.nix` (sorted names, `[name]` then `ini`), inside the
   existing `mkIf boxes.enable`.
   → verify: eval on `boxesOn` shows `[archlinux]` and `[debian]`; absent on
   `boxesOff`.
3. `modules/home.nix`: a `distroboxPanel` wrapper that copies the package and
   runs `jq '.barWidget.defaults.templatesFile = "/etc/nixarchy/box-templates.ini"'`
   on `manifest.json` (the key path is `barWidget.defaults.templatesFile`, read from the manifest).
   Plus `defaultPluginSet.distrobox`:
   - `id = "nixarchy.distrobox"`;
   - gate `osConfig.programs.nixarchy.services.boxes.enable or false`;
   - `packages = [ ]`, since distrobox itself is installed by `boxes.nix`.

   `defaultPlugins.distrobox` already exists.
   → verify: the installed manifest names the `/etc` path.
4. `modules/apps.nix` (`boxesEnabled` block, `:658-700`): `trigger.box` gets
   `action = "nixarchy-plugin nixarchy.distrobox"` and
   `when = "nixarchy-plugin --enabled nixarchy.distrobox"`, and the
   `.enter`, `.rm` and `.create.<name>` children go. The panel does all three
   (the create form lists the templates).
   → verify: the generated menu has no `trigger.box.` child keys.
5. `tests/menu-verbs.nix`: the box scan (`:117-118`) loses those rows, so lower
   its floor deliberately and say so in the PR (§1: a retargeted check is
   named as such). The plugin-row floor rises by one.
6. `pkgs/omarchy/default.nix` (the seed `printf` block): **Super+Alt+D** →
   `nixarchy-plugin nixarchy.distrobox`. Nothing upstream or nixarchy binds it
   (checked in the #766 spec).
7. Docs:
   - `docs/manual/boxes.md`: the panel is the Boxes UI; `nixarchy box` is the
     terminal interface; the templatesFile note;
   - `docs/manual/plugins.md`: Distrobox moves to "on wherever boxes are";
   - the README feature row, and `docs/internals/flake.md`.
8. Lints; heavy builds only through `/mnt/data/vmtest/heavy-build.sh`; PR with
   `Refs #766`, plus `Closes #766` only if PR E has landed.

### Tests (each broken first, §1)

| check | case | break |
|---|---|---|
| `checks.options` | `distroboxIsADefault`: on with boxes; off without boxes, off when opted out, off on standalone Home Manager | gate forced true |
| `checks.options` | `distroboxTemplatesFile`: the installed `manifest.json` names `/etc/nixarchy/box-templates.ini` | drop the `jq` |
| `checks.options` | `boxTemplatesIni`: the etc file has one section per `data/box-templates.nix` entry, and no key outside the plugin's accepted list | add an `exported_apps=x` line to a template in a scratch copy |
| `checks.menu-verbs` | no `trigger.box.` child rows, and the panel row names an installed id | row id `nixarchy.distroboxx` |
| `.#omarchy` | the seed ends with the D line | anchor moved |

`checks.box-template` and `checks.box-boot` are unchanged, because the CLI
stays.

**PR D deviations (made while implementing, 2026-09-19, on `feat/batch-766-800-772`):**
- **Step 5: there was no box-specific floor to lower.** `menu-verbs` has one
  shared `checked >= 12`, and it still holds (the box rows' verbs go, and the
  count stays above 12). The plugin-row floor rises from 5 to 6 (Boxes).
- **`boxTemplatesIni` is two halves:** an eval case, `boxTemplatesIniPresent`
  (the file exists with Boxes on and not with them off), plus the runtime check
  in the options builder. The runtime check compares the section count to the
  catalogue and every key to the lists read out of the pinned `Model.js`.
- **`trigger.box` has no fallback row,** unlike Sandbox (PR E): the step says
  `when = nixarchy-plugin --enabled`, and `nixarchy box` stays in the terminal.
- **`apps.nix` loses `boxTemplates`,** which only the removed create rows used.

## Outlines, in order

- **C — podman.** Stepped above ("PR C — podman").
- **E — microvm.**
  - Input `nixarchy-microvm` at a commit on main (PR #2 merged). The default
    entry, gated on nixarchy enabled.
  - The `trigger.vm` parent gets `action = "nixarchy-plugin nixarchy.microvm"`
    and `when = "nixarchy-vm --check && nixarchy-plugin --enabled nixarchy.microvm"`.
  - Remove the `.new/.open/.stop/.destroy/.list` rows. Their verbs leave
    menu-verbs' vm scan, so lower that floor deliberately and say so in the PR
    (§1: a retargeted check is named as such).
  - The V bind.
  - nixarchy#762 stays separate; the plugin hides the keys that need it.
  - Blocker: none beyond A.
  - **Stepped below** in "#762 and PR E — approved 2026-09-19".
  - Check: its `Model.js:988` path to `nixarchy.pkg`'s script resolves on a
    default install, since that plugin is linked by id.
- **D — distrobox, and retiring `nixarchy box`.** *Superseded by "PR D — distrobox" above: the panel ships, and retirement is split into its own issue. What follows is kept as the retirement issue's starting point.*
  - **Blocked** on the plugin repo shipping templates read from
    `/etc/nixarchy/box-templates.json`, `promote`, a `--check` equivalent and
    `list`.
  - Then:
    - `environment.etc."nixarchy/box-templates.json"` from
      `data/box-templates.nix`;
    - the input and a default gated on boxes;
    - the `trigger.box` parent opens the panel, with its children and the
      template rows removed;
    - remove `pkgs/box.nix`, `packages.nixarchy-box` (`flake.nix:839`), the
      `box)` verb (`apps.nix:2995`), its install (`:2922`), the menu-verbs box
      scans (`:117-118`), the demo scene (`tests/demo/default.nix:519-561`)
      and the `pkgs/verify.sh:1003-1040` wording;
    - retarget `tests/box-template.nix` (the JSON names pinned images) and
      `tests/box-boot.nix` (create a box the way the plugin does, rootless,
      with the offline-enter assertion kept);
    - the D bind;
    - docs: `docs/manual/boxes.md`, the README and `docs/index.md`.
  - **Human only (§4, §11):** the `build.yml` step comments at `:1293` and
    `:1503` describe `nixarchy box create`. The PR carries the proposed wording
    in its body, and the owner commits it. The check names stay, so no gate
    changes.
  - This PR closes #766 (`Closes #766`, alone on its line).

## #762 and PR E — approved 2026-09-19

### What the research found (2026-09-19, read-only)

- **The plugin reads capabilities from `nixarchy-vm help`, nothing else.**
  `Model.js:971-976` (plugin main `481e6c5`):
  `vmDetach: /\brun\b[^\n]*--detach/`, `vmConsole: /\bvm console\b/`,
  `vmSetTemplate: /\bset-template\b/`. JSON listing is detected from the output
  itself, with a text-parsing fallback (`Model.js:192-246`). Today `list` and
  `templates` ignore `--json` (`pkgs/microvm.nix:296`), so the plugin runs on
  text, and hides console, detach and edit, saying why (`Model.js:1208-1210`).
  **The help text is the contract.** Rewording a help line silently turns a
  feature off in the plugin, so a check pins those three patterns.
- **The plugin calls these argvs** (`Model.js:997-1042`): `list --json`,
  `templates --json`, `help`, `console <n>`, `run <n>`, `run --detach <n>`,
  `stop <n>`, `rm <n>`, `create <n> --template <t>`, `set-template <n> <t>`.
- **The Sandbox rows this PR retires are already broken.** Every child row calls
  a verb with no name (`modules/apps.nix:636-671`, e.g. `nixarchy-vm create`).
  The CLI's `${1:?usage…}` exits 1. Measured on the owner's machine:
  `nixarchy-vm create` gives "usage: nixarchy vm create <name>" and exit=1, and
  `run` does the same. `checks.menu-verbs` checks that the verb exists, never
  that the call can succeed. Retiring the rows fixes it for users. The lesson
  ("a verb check is not an arity check") goes into `tests/AGENTS.md` in PR E.
- **`Model.js:988`'s hardcoded `…/plugins/nixarchy.pkg/bin/nixarchy-pkg`**
  resolves once PR B (#780) is merged: nixarchy.pkg is a default, linked by its
  id. The permanent-VM features need it. The detached/disposable ones don't.
- **`dtach` is in nixpkgs** (0.9-unstable-2025-06-20), a single small binary.
  It is the whole "detachable console" mechanism below.

### Decision: #762 is its own PR, landing before E

#762 is five changes to a 324-line CLI, each with its own test. E is an input,
a default and a menu swap. Kept apart, a red check names its half. #762 lands
first, so the panel is complete on day one of E. E is **not blocked** on it,
because the plugin degrades to text and a terminal `run`. The issue asks that
the five ship in one release, so all five are in the one #762 PR.

### #762: steps (branch `feat/762-nixarchy-vm-contract`, off main)

1. `pkgs/microvm.nix`: `runtimeInputs += [ jq dtach systemd ]`. `systemd-run`
   resolves through the strict PATH, and an undeclared command reads as a
   wrong answer (§7). → verify by `checks.microvm-template` building the CLI.
2. `pkgs/microvm.nix`: `list --json` prints `[{name,template,running,dir}]`,
   built with `jq -n` (never string concatenation), `[]` when there are none.
   `running` comes from the same `flock -n` probe as the text output. `dir` is
   absolute. `templates --json` prints `[{name,label,note}]` from `index.tsv`
   through `jq -R`. Text output byte-identical. → verify by step 8's cases (a),
   (b), (c).
3. `pkgs/microvm.nix`: split `run_vm` into `build_vm <name>` (today's
   `nix build … --out-link "$dir/current"` with its fallback, unchanged) and
   `launch_vm <name>` (the lock, the `hostname` write, the
   `exec ./current/bin/microvm-run`). `run <n>` is both, as today. The internal
   `run --prebuilt <n>` is `launch_vm` only, for the unit in step 4. It stays
   out of `help`, so the plugin never sees it. → verify by the existing
   "launch and locking" block (`tests/microvm-template.nix:351-440`) passing
   unchanged.
4. `pkgs/microvm.nix`: `run --detach <n>` runs `build_vm` in the caller, so
   stdout is the build log and a build failure is the exit status. Then:
   `systemd-run --user --unit="nixarchy-vm-$name" --collect --quiet --
   dtach -N "$dir/console.sock" -z nixarchy-vm run --prebuilt "$name"`.
   The unit's process takes the flock, so the lock rule is unchanged and `rm`
   still refuses. It waits up to 30 s for the lock to be held, then exits 0. On
   timeout it exits 1 and names `journalctl --user -u nixarchy-vm-<name>`.
   Refuses up front if already running. → verify by (e), (f).
5. `pkgs/microvm.nix`: `console <n>` refuses unless `$dir/console.sock` is a
   socket ("not detached; `nixarchy vm run <n>` attaches directly"). Otherwise
   `exec dtach -a "$dir/console.sock" -e '^]' -r winch`. Ctrl-] detaches and
   Ctrl-A X still stops the guest. `stop` and `rm` are unchanged:
   `microvm-shutdown` ends the runner, the unit ends with it, and `--collect`
   removes it. → verify by (g).
6. `pkgs/microvm.nix`: `set-template <n> <t>` takes `flock -n` on `$dir/.lock`
   (refuses while running), validates `<t>` with `template_exists` and `<n>`
   with the name rule, and rewrites `$dir/template`. It leaves volumes alone,
   and the help line says the next run rebuilds. → verify by (d).
7. `pkgs/microvm.nix`: the `help` text gains
   `nixarchy vm run [--detach] <name>`, `nixarchy vm console <name>` and
   `nixarchy vm set-template <name> <template>`, worded so the three plugin
   patterns match. → verify by (h).
8. `tests/microvm-template.nix`, "nixarchy vm" section (cheap; PR-gated by
   `build.yml:1278`). The stubs are **exported bash functions**, not PATH files:
   `writeShellApplication` puts runtimeInputs first, so a stub file is never
   reached (the #778 lesson), while a function beats PATH. Cases:
   - (a) `list --json` with none is `[]`;
   - (b) after `create`, exactly the four keys, `running=false`, and
     `running=true` while the existing stub runner holds the lock;
   - (c) `templates --json` names equal `cut -f1 index.tsv`;
   - (d) `set-template` rewrites when stopped, refuses while locked, refuses
     an unknown template or a missing name;
   - (e) `run --detach` calls the `systemd-run` stub with
     `--unit nixarchy-vm-sandbox`, and the stub runs its command in the
     background, so the lock-wait path runs for real. Exit 0;
   - (f) a stub that never runs its command gives exit 1 with the journalctl
     hint;
   - (g) `console` without a socket refuses, and with one it execs the `dtach`
     stub with `-a <dir>/console.sock -e ^]`;
   - (h) the three plugin regexes, copied from `Model.js:973-975` with a
     comment naming the plugin commit, all match `nixarchy-vm help`.
9. `tests/microvm-boot.nix` (nightly, KVM): after today's boot, a real
   `run --detach`, then `list --json` shows `running: true`, the console socket
   exists, then `stop` and wait for the unit to go. Nightly only, so a PR cannot
   see a real detach. That hole is written into `tests/AGENTS.md` (§3), not
   papered over.
    *Deviation, made while implementing #762:* not done. That host has no
    session user (`user = null`, `tests/microvm-boot.nix:73`), so no `systemd
    --user`, and no network for `run`'s `nix build github:...`. A real detach
    there needs a redesign of the test, not a step. The hole is recorded in
    `tests/AGENTS.md` as uncovered, nightly included, with the by-hand check.
    *Deviation, after #784's first review (codex-p620-858273, agent bus):*
    step 4 as written built with the lock free, so `rm` could delete a VM
    mid-build and a second detach could unlink the first's console socket.
    Now `run --detach` takes the lock (`-n`) before the build and holds it
    until the unit exists. `--prebuilt` waits for it (`-w 30`), since
    systemd-run passes on no fd. `systemctl --user is-active
    nixarchy-vm-<name>` (active/activating) counts as busy for run, detach,
    rm and set-template, which covers the handoff. `console.sock` is only
    removed under the lock. New cases: (i) rm during the build refuses,
    (j) a second detach refuses, (k) rm refuses while the unit is activating
    and the lock is free.
10. `docs/manual/sandboxes.md`: the new verbs, the detach key and the JSON shapes
    as a stable contract ("fields are only ever added").

**#762 §1 breaks:**

| case | break | must go red with |
|---|---|---|
| (a) | print the text output under `--json` | jq parse error |
| (b) | drop the `dir` key | key-set mismatch |
| (d) | skip the lock in `set-template` | "rewrote a running VM's template" |
| (e) | `exit 0` before the lock wait | the stub saw no lock taken |
| (f) | treat a timeout as success | exit 0 where 1 was expected |
| (h) | reword the help line to `attach` | "vmConsole pattern no longer matches" |

### PR E: steps (branch `feat/766-pr-e-microvm`, after #762 and #780)

1. `flake.nix`: input `nixarchy-microvm`, pinned to a commit on main (at least
   `481e6c5`), with `inputs.nixpkgs.follows = "nixpkgs"`. Re-export
   `packages.<sys>.nixarchy-microvm`. The reasoning, sizes and pin-bump
   procedure go in `docs/internals/flake.md`, as PR B did. → verify by
   `nix flake metadata`: one new node, no second nixpkgs.
2. `modules/home.nix`: `defaultPluginSet.microvm = { id = "nixarchy.microvm";
   src = inputs.nixarchy-microvm.packages.${system}.default; }`, the gate being
   nixarchy on (the approved spec: gated like the Sandbox rows, whose
   `nixarchy-vm --check` is always 0). Add `microvm` to the `defaultPlugins`
   default. → verify by (i).
3. `modules/apps.nix`: `trigger.vm` keeps its key, label, icon and aliases,
   gains `action = "nixarchy-plugin nixarchy.microvm"`, and its `when` becomes
   `nixarchy-vm --check && nixarchy-plugin --enabled nixarchy.microvm`. Remove
   `.new/.open/.stop/.destroy/.list` (the broken rows above). → verify by (j).
4. `pkgs/omarchy/default.nix`: Super+Alt+V appended to the seeded
   `bindings.lua` with PR B's `printf` after the same asserted anchor. The
   plugin's own Home Manager module is **not** imported, because its bind file
   would duplicate this. → verify by the anchor assertion.
5. `tests/menu-verbs.nix`: **retargeted, and said so in the PR (§1)**. The two
   vm row scans (`:115-116`, floors 2 and 3) have nothing left to scan once the
   rows go, so they are removed. In their place, a contract scan: every
   `"nixarchy-vm", "<verb>"` in the pinned plugin's `Model.js` must be in
   `vm-verbs`, with a floor of 7. That checks the calls that still exist.
   → verify by (k).
6. `tests/options.nix`: `microvmIsADefault` in both states, `sandboxRowsRetired`
   (no `trigger.vm.*` child in the generated menu, and the parent's action is
   the plugin), and
   `microvmNeedsPkg`: with both defaults on, both ids resolve. That is the
   `Model.js:988` path. `tests/plugin.nix` sets `microvm = false` beside
   PR B's `pkg = false` (the tests use stand-ins). → verify by (i).
7. `tests/AGENTS.md`: the verb-versus-arity lesson.
   `modules/AGENTS.md#the-sandboxes-group-226`: the group is now the panel;
   the CLI stays for the terminal. `docs/manual/sandboxes.md`: the menu section.
   README feature row, and `readme-counts.sh --check`.
8. Before pushing, rebase onto main with #780 and #762 in. menu-verbs and the
   plan are edited by both, and #780's plan edit sits in the PR B section.

**PR E §1 breaks:**

| case | break | must go red with |
|---|---|---|
| (i) | remove `defaultPluginSet.microvm` | only `microvmIsADefault` fails |
| (j) | leave `trigger.vm.open` in | `sandboxRowsRetired` (options): "trigger.vm.open still exists". menu-verbs alone would pass, because it checks verbs, not arity |
| (k) | rename a plugin argv verb to `attach` in a copy of `Model.js` | "plugin calls nixarchy-vm 'attach', which it does not accept" |
| bind | point the anchor at a missing line | the omarchy build fails |

`Refs #766` on both PRs. #762's PR says `Closes #762`, alone on its line (§8).

**PR E deviations (made while implementing, 2026-09-19, on `feat/batch-766-800-772`):**
- **Step 5 keeps the two vm row scans.** The owner's fallback row (`trigger.vm-list`,
  shown while the plugin is off) still runs `nixarchy-vm list`, and both rows'
  `when` runs `nixarchy-vm --check`, so the scans still have rows to read. The
  contract scan over `Model.js` is added beside them, not in their place.
- **Step 3 adds the fallback row** that the owner's answer to open question 1 asked
  for: `trigger.vm-list`, with the inverse `when`.
- **The plugin-row floor goes from 4 to 5** (Sandbox), deliberately.

### Open questions for the owner

1. With the plugin turned off, the Sandbox row hides, and the CLI is the only
   way in. Should there be a fallback row that opens a terminal with
   `nixarchy vm list` instead?
2. `set-template` leaves the VM's volumes, which a different template may not
   expect (k3s vs node). Should it refuse when the VM has volumes, or just warn?

## Tests

Every new check is broken first, with the failing output kept for the PR (§1).
Each break loop commits a known-good baseline first and restores with
`git checkout HEAD -- <path>`, not the index (§5). Prove each break landed with
`git diff` before reading a green result.

| check | expected | §1 break (must go red) |
|---|---|---|
| `options`: `homeWith {}` has no default src and no hook | pass | drop the `osConfig…enable` gate |
| `options`: `homeOn {} {}` has src and hook | pass | make the hook `mkIf false` |
| `options`: `defaultPlugins.<x> = false` removes both | pass | ignore the option in `resolvedDefaults` |
| `options`: hook lists exactly the resolved ids | pass | hardcode the id list |
| `options`: `nixarchy-plugin --enabled` 1 without and 0 with the id | pass | make `--enabled` `exit 0` |
| `validatedPlugins`: a default whose manifest id differs from its name | build fails | remove the id assertion; the build then passes, which is the red |
| `plugin` (VM): enabled after first login, widget in `right` | pass | exit the hook before `enable` |
| `plugin` (VM): pre-seeded `shell.json` still enabled via IPC | pass | replace IPC with a direct jq write, which races and loses |
| `plugin` (VM): disable survives re-login | pass | write the marker before the enable, or skip reading it |
| `menu-verbs`: every `nixarchy-plugin <id>` is installed | pass | rename the row's id to `nixarchy.pkgx` |
| `omarchy` build: bind anchor present | pass | point the anchor at a missing line |
| C: podman gate cases | pass | read podman from boxes |
| D: `box-template`, `box-boot` retargeted | pass | an unpinned image; a store-path distrobox |

Commands: `nix build .#checks.x86_64-linux.<name> --print-build-logs`, never
piped (§1), run under bash, with `env -u NIXPKGS_ALLOW_UNFREE` where unfree
matters (§1, §5). Before each: the `gh run list` queue check (§6). Then
`nix fmt -- --ci`, statix and deadnix.

## Rollback

- **Per PR, revert its squash commit.**
  - A: removes the option, hook and helper, with no user state touched.
    Markers left in `~/.local/state/nixarchy/enabled-once` are inert.
  - B, C, E: remove the input and the default. Home Manager's reconcile
    unlinks the plugin (`home.nix:846-895`). A `shell.json` entry for a now
    missing id stays behind, and Setup > Plugins can remove it.
  - D: restores `nixarchy box` and its rows. Boxes created by the plugin are
    plain distrobox containers, which the CLI lists anyway.
- **To opt out without reverting,** set
  `programs.nixarchy.defaultPlugins.<name> = false`.

**PR C decisions (owner, 2026-09-19):** podman-tui is not installed. The panel's `d` key stays dead, and the docs say so; the plugin hiding the key when podman-tui is missing is an upstream change we don't file. The helper's "not installed on this machine" message ships in PR C.

**PR C deviation (recorded after implementation, 2026-09-19):** the plan's `homeOnMod` wrapper became `boxesConfigWith extra enable`. `boxesConfig` already nests Home Manager like a real machine, and reusing `boxesOn`/`boxesOff` keeps the new NixOS evaluations at the two the plan budgeted (#747). The menu spec is read at eval time via `...source.overrideSpec.text`, which is new here. This should have gone in the same commit as the code; it didn't, so it follows as its own commit. The local `checks.plugin` failure is PR A's race, filed as #783, and not caused by PR C.

**PR E and #762 decisions (owner, 2026-09-19):** with the plugin off, a fallback Sandbox row opens `nixarchy vm list` in a terminal. `set-template` refuses when the VM has volumes, unless `--keep-volumes` is passed. The rows retired here also fix #781.
