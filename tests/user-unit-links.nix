{ inputs, pkgs }:
let
  inherit (pkgs) lib;
  normalHome = "/srv/nixarchy unit's home";
  systemHome = "/srv/nixarchy-system-probe";
  cfg =
    (inputs.nixpkgs.lib.nixosSystem {
      system = pkgs.stdenv.hostPlatform.system;
      modules = [
        inputs.self.nixosModules.nixarchy
        {
          programs.nixarchy.enable = true;
          users.users.unitprobe = {
            isNormalUser = true;
            home = normalHome;
          };
          users.users.systemprobe = {
            isSystemUser = true;
            uid = 899;
            group = "users";
            home = systemHome;
          };
          boot.loader.grub.device = "/dev/sda";
          fileSystems."/" = {
            device = "/dev/sda1";
            fsType = "ext4";
          };
          system.stateVersion = "25.05";
        }
      ];
    }).config;
  activation = cfg.system.activationScripts.nixarchyRemoveOldUserUnitLinks;
in
assert lib.assertMsg (lib.hasInfix (lib.escapeShellArg normalHome) activation)
  "normal user's nonstandard home is not shell-escaped in unit cleanup activation";
assert lib.assertMsg (
  !(lib.hasInfix systemHome activation)
) "system user's home reached unit cleanup activation";
pkgs.runCommand "user-unit-links"
  {
    nativeBuildInputs = [
      pkgs.bash
      pkgs.coreutils
      pkgs.gnugrep
      pkgs.gnused
    ];
  }
  ''
    bash ${./user-unit-links.sh} ${../pkgs/omarchy/enable-user-units.sh} \
      ${../pkgs/omarchy/cleanup-user-unit-links.sh} ${../pkgs/verify.sh} \
      ${pkgs.bash}/bin/bash ${pkgs.coreutils}/bin/rm ${pkgs.coreutils}/bin/stat \
      ${lib.makeBinPath [
        pkgs.bash
        pkgs.coreutils
        pkgs.gnugrep
        pkgs.gnused
      ]}
    touch "$out"
  ''
