---
status: draft
issue: 1053
intent: intent/2026-09-29-1053-menu-snowflake.md
---

# Spec: nixarchy-menu's bar button wears the NixOS snowflake

## Design

**Where.** `modules/home.nix`, in the `menu` entry of the default-plugin set
(#946). It is the only place nixarchy takes in nixarchy-menu. Its `src`
changes from the flake's plugin output to a patched copy of it:

```nix
src = pkgs.applyPatches {
  name = "nixarchy-menu";
  src = inputs.nixarchy-menu.packages.${pkgs.stdenv.hostPlatform.system}.plugin;
  # The bar button wears the snowflake, like omarchy.menu's
  # (pkgs/omarchy/menu-bar-widget.qml).
  postPatch = ''
    substituteInPlace BarWidget.qml --replace-fail \
      'fontFamily: "omarchy"' \
      '${snowflakeButton}'
  '';
};
```

**What.** `snowflakeButton` is the matched line, followed by what
`pkgs/omarchy/menu-bar-widget.qml` adds to the stock button:

- `labelVisible: false`. The glyph stays, so the button keeps its width, hit
  area and `hasVisualContent`. Only the label is hidden.
- an `Image` child of the button: `anchors.centerIn: parent`,
  `source: "file://${pkgs.nixos-icons}/share/icons/hicolor/256x256/apps/nix-snowflake.png"`,
  side `Math.round(button.fontSize * 1.3)` for `sourceSize`, `width` and
  `height`, `smooth` and `mipmap` on, and
  `opacity: button.dimmed ? 0.45 : 1`.

A QML object's properties and children can come in any order, so inserting
them after `fontFamily` inside `WidgetButton { id: button … }` is valid.
`fontFamily: "omarchy"` occurs exactly once in the file (in the menu button;
the bar-item buttons do not set a font), which makes the anchor unambiguous.
Nothing else in the file changes: the `omarchy.menu` toggle, right-click
opening a terminal, the `barList` Repeater and `moduleName`.

**Why `--replace-fail` and not a `.patch`.** `pkgs/AGENTS.md#patching-upstream`
makes `--replace-fail` the rule. The two carried `.patch` files are
multi-hunk exceptions. This change is a single anchored insertion. It fails
the build just as loudly as `--fuzz=0` when nixarchy-menu rewords the line,
and it needs no new file. This departs from nixos_config#2074's plan
(steps 2–3 there name a `.patch` with `--fuzz=0`). Its plan records the
change in the commit that bumps the lock.

**Why here and not in nixarchy-menu.** nixarchy-menu also runs on Arch
Omarchy. The snowflake is nixarchy's identity, applied where nixarchy
already applies it to the stock button. That was decided in
nixos_config#2074's spec, where the alternatives are listed: the plugin
drawing it itself, an `icon` setting, replacing the whole file, and a
host-local override.

**#1052.** There is no code overlap. #1052 changes `enableByDefault` on the
same entry, and this change touches `src`. Whichever merges second rebases.
The conflict, if any, is textual and confined to adjacent lines.

## Alternatives rejected

- A `.patch` applied with `--fuzz=0`: equally loud, but it adds a file and
  breaks the house rule for a single insertion (see above).
- Replacing all of nixarchy-menu's `BarWidget.qml`, as the stock button is
  replaced: it would silently fork the `barList` Repeater and the panel
  lookup, and nixarchy-menu fixes to them would stop arriving.

## Risks

- **A nixarchy-menu bump rewords the anchor.** The build fails at
  `--replace-fail`, which is the intended alarm. The substitution then has
  to be re-anchored.
- **The QML is broken but builds.** This is covered by linting the patched
  file in `tests/qml.nix`.
- **The icon is invisible.** An SVG would render nothing, because quickshell
  has no SVG image plugin. The PNG is used, the same file the stock button
  uses.
- **Existing machines keep the old glyph until the shell restarts** (the
  stale plugin reload). The next login fixes it. It is not a code risk.

## Verification

- `tests/qml.nix` also lints `${menuSrc}/BarWidget.qml`. It is passed in
  from `flake.nix` as `menuPlugin`, the patched `src` above, alongside
  `omarchy`. Expected: `== menu-plugin/BarWidget.qml` then `ok`.
- `tests/options.nix`, in the #946 block: the patched source that
  `menuOnHome` installs (`programs.nixarchy.plugins."nixarchy.menu".src`)
  has a `BarWidget.qml` that contains `nix-snowflake.png` and
  `labelVisible: false`. The existing `menuValidated` check proves the
  patched copy still validates as `nixarchy.menu`. To confirm the assertion
  can fail, it is run once with the substitution commented out.
- `nix flake check` is green. `nix fmt -- --ci` is clean.
- Downstream (nixos_config#2074): p620 and razer show the snowflake with the
  palette as their menu.
