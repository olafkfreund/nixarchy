{ inputs, pkgs }:
# #1370: a rebuild resets GTK to the Adwaita default unless omarchy-theme-gnome
# re-applies the engine's GTK target. Evaluated: the answer is a unit's
# ExecStartPost, and the asserts run when the derivation is instantiated.
let
  inherit (pkgs.stdenv.hostPlatform) system;
  post =
    extra:
    (inputs.nixpkgs.lib.nixosSystem {
      inherit system;
      modules = [
        inputs.self.nixosModules.nixarchy
        inputs.home-manager.nixosModules.home-manager
        {
          programs.nixarchy = {
            enable = true;
            user = "someone";
          };
        }
        extra
        {
          users.users.someone = {
            isNormalUser = true;
            home = "/home/someone";
          };
          home-manager.users.someone = {
            imports = [ inputs.self.homeManagerModules.nixarchy ];
            programs.nixarchy.enable = true;
            home.stateVersion = "25.05";
          };
          boot.loader.grub.device = "/dev/sda";
          fileSystems."/" = {
            device = "/dev/sda1";
            fsType = "ext4";
          };
          system.stateVersion = "25.05";
        }
      ];
    }).config.home-manager.users.someone.systemd.user.services.omarchy-theme-gnome.Service.ExecStartPost
      or [ ];
  on = post { };
  gtkOff = post { programs.nixarchyThemeEngine.targets.gtk = false; };
  engineOff = post { programs.nixarchyThemeEngine.enable = false; };
in
assert pkgs.lib.assertMsg
  (builtins.length on == 1 && pkgs.lib.hasInfix "hyprchroma --target=gtk" (builtins.head on))
  "default case: omarchy-theme-gnome has no hyprchroma --target=gtk ExecStartPost: ${builtins.toJSON on}";
assert pkgs.lib.assertMsg (
  gtkOff == [ ]
) "targets.gtk = false: omarchy-theme-gnome still has an ExecStartPost: ${builtins.toJSON gtkOff}";
assert pkgs.lib.assertMsg (
  engineOff == [ ]
) "engine disabled: omarchy-theme-gnome still has an ExecStartPost: ${builtins.toJSON engineOff}";
pkgs.runCommand "nixarchy-theme-gnome-gtk" { } "touch $out"
