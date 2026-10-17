{ inputs, pkgs }:
# The menu's guards, judged by the menu's own model (#1301). The guard batch
# once defined omarchy-pkg-present from pacman, and nixarchy's `disabled`
# was dropped by stable's normalizeItem; the old check ran each condition
# with bash -c and so could see neither. Two worlds differ only in what is
# on PATH. Menu.qml is not exercised: dimming and blocked clicks are QML.
# Why: tests/AGENTS.md#menu-guards-runs-the-menu-s-model-not-the-strings
let
  cfg = inputs.self.nixosConfigurations.reference.config.programs.nixarchy;
  basePath = pkgs.lib.makeBinPath [
    pkgs.coreutils
    pkgs.gnugrep
    pkgs.gawk
    pkgs.bash
  ];
in
pkgs.runCommand "nixarchy-menu-guards" { } ''
  ${pkgs.nodejs}/bin/node ${./menu-guards.js} \
    ${cfg.tree} \
    ${cfg.package}/share/omarchy/default/omarchy/omarchy-menu.jsonc \
    ${basePath} "$TMPDIR/worlds" ${pkgs.bash}/bin/bash
  touch $out
''
