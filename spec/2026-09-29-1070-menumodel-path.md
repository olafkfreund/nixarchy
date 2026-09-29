---
status: draft
issue: 1070
intent: intent/2026-09-29-1070-menumodel-path.md
---

# Spec: The menu plugins load MenuModel.js from the Omarchy they were built against

Decisions approved in the intent:

- **nixi** gains its own `omarchy` input (option (a)).
- **#1069's `pathsToLink`** stays.

## Design

### 1. nixarchy-menu (`olafkfreund/nixarchy-menu`, `flake.nix`, the `plugin` output)

Beside the existing `substituteInPlace "$out/matching/Session.qml"`, add:

```nix
substituteInPlace "$out/providers/OmarchyMenu.qml" \
  --replace-fail 'file:///run/current-system/sw/share/omarchy' 'file://${omarchy}'
test -f "${omarchy}/shell/plugins/menu/MenuModel.js"
```

- `${omarchy}` is the repository's pinned Omarchy input
  (`github:basecamp/omarchy/v4.0.4`). nixarchy makes it follow its own
  (`inputs.omarchy.follows = "omarchy"`), so the plugin loads exactly the
  `MenuModel.js` from the Omarchy nixarchy ships.
- The `test -f` fails the build if Omarchy ever moves the file.
- `--replace-fail` fails it if the import is ever reworded.
- **Its `checks`** already rewrite the same import in `checkSrc`. Beside them
  goes one assertion over the built `plugin` output: `OmarchyMenu.qml`
  contains no `/run/current-system`, and the `file://` path it imports exists.
  That prevents a regression back to the runtime path.
- `core/Hotkeys.js`'s `String(omarchyPath || "/run/current-system/…")`
  already prefers `$OMARCHY_PATH` and is left as it is.
- **Process:** a branch and PR in that repository, following its own
  intent/spec/plan layout, which this spec and plan cover by reference.
  Released as a patch version (1.0.1), because nixarchy pins released
  commits.

### 2. nixi (`olafkfreund/nixi-nixarchy`)

- `flake.nix` gains
  `inputs.omarchy = { url = "github:basecamp/omarchy/v4.0.4"; flake = false; };`
  and passes it to `nix/package.nix` as `omarchySrc`.
- `nix/package.nix` takes `omarchySrc ? null`. When it is set, it adds to the
  existing `MenuSearch.qml` substitution:
  `--replace-fail 'file:///run/current-system/sw/share/omarchy' 'file://${omarchySrc}'`,
  with the same `test -f`. When it is null (`callPackage` without the flake),
  the import is unchanged, so nothing breaks for a non-flake build.
- `installCheckPhase`, which already exists, asserts that the built
  `MenuSearch.qml` contains no `/run/current-system` whenever `omarchySrc` is
  set.
- **Process:** a PR in that repository, then a release commit as usual.

### 3. nixarchy (this repository)

- **The nixarchy-menu pin** moves to its release commit. Its `inputs.omarchy`
  follows ours already.
- **The nixi pin** moves to its release commit, and nixarchy adds
  `inputs.nixi.inputs.omarchy.follows = "omarchy";` beside the existing
  `nixpkgs` follow.
- **`docs/internals/flake.md`**: the menu and nixi sections name the build-time
  import, and the follows line.
- **#1069's `pathsToLink` stays**, with its comment updated to say it is now
  belt and braces.

## Alternatives rejected

- **A runtime path from `$OMARCHY_PATH`.** A QML import is static, so the URL
  cannot be built at runtime.
- **Vendoring a copy of `MenuModel.js` into each plugin repository.** It would
  drift from the Omarchy the shell runs. The build-time path is the pinned
  Omarchy itself.
- **nixarchy patching nixi's import when packaging it (option (b)).** It is
  nixarchy-only, and was rejected at intent.

## Risks

- **The build-time Omarchy is upstream's source, not nixarchy's patched tree.**
  `MenuModel.js` is pure functions over menu data, and nixarchy does not patch
  it (it is not among `pkgs/omarchy`'s substitutions; checked in the plan). So
  the code is identical.
- **A new `omarchy` input in nixi** adds one lock node. For nixarchy it
  follows, so it adds nothing to nixarchy's lock.

## Verification

- **nixarchy-menu:** `nix build .#plugin` and `nix flake check`.
  - The new assertion is green.
  - **Break:** drop the `substituteInPlace`, and the assertion fails, naming
    `/run/current-system`.
- **nixi:** `nix build .#nixi`, with the `installCheckPhase` assertion green.
  **Break:** drop the substitution, and it fails.
- **nixarchy:** the pins are bumped, then:
  - with #1069's `pathsToLink` line **removed** as a deliberate break,
    `checks.session`'s #1069 probe **still passes**. That proves the plugins
    no longer need the link.
  - With the line restored, everything is green on CI.
  - `demo-scene-menus` is green.
