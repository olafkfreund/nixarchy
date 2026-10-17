{ inputs, pkgs }:
# Menu conditions that must answer for the NixOS machine, not Arch (#1303).
# Why: tests/AGENTS.md#menu-conditions-and-hibernate-resume
let
  inherit (pkgs) lib;
  inherit (pkgs.stdenv.hostPlatform) system;
  inherit (inputs.self.nixosConfigurations) reference;
  noSnapper = reference.extendModules {
    modules = [ { services.snapper.configs = lib.mkForce { }; } ];
  };
  menuOf = c: c.config.environment.etc."nixarchy/omarchy-menu.jsonc".source;
in
pkgs.runCommand "nixarchy-menu-conditions"
  {
    nativeBuildInputs = [
      pkgs.python3
      pkgs.fontconfig
    ];
    menu = menuOf reference;
    menuNoSnapper = menuOf noSnapper;
    bin = "${reference.config.programs.nixarchy.package}/share/omarchy/bin";
    hxBinary = pkgs.helix.meta.mainProgram;
    zenBinary = inputs.self.packages.${system}.zen-browser.meta.mainProgram;
    FONTCONFIG_FILE = pkgs.makeFontsConf {
      fontDirectories = [
        pkgs.font-cursor-misc
        pkgs.dejavu_fonts
      ];
    };
  }
  ''
    bash ${./menu-conditions.sh}
    touch $out
  ''
