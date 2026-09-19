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
  - Check: its `Model.js:988` path to `nixarchy.pkg`'s script resolves on a
    default install, since that plugin is linked by id.
- **D — distrobox, and retiring `nixarchy box`.**
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
