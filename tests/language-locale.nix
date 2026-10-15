{ inputs, pkgs }:
# programs.nixarchy.language (#1289): which locale a code adds, and that it
# adds it only on a machine that enabled nixarchy (Mode A is untouched).
#
# Evaluated, with the module re-imported over a stub `omarchy` input that
# carries a two-code registry: on the pinned v4.0.4 there is no registry, so
# the real input can only ever answer "null". The stub is a directory in the
# repository, not a derivation, so reading it is not import-from-derivation.
# Only the registry is read from it: the fontconfig default that would read the
# rest of the tree is overridden below and never forced.
let
  stubbed = import ../modules/nixos.nix (inputs // { omarchy = ./fixtures/language-omarchy; });

  machine =
    settings:
    (inputs.nixpkgs.lib.nixosSystem {
      system = pkgs.stdenv.hostPlatform.system;
      modules = [
        stubbed
        inputs.home-manager.nixosModules.home-manager
        {
          fonts.fontconfig.localConf = "";
          users.users.someone = {
            isNormalUser = true;
            home = "/home/someone";
          };
          home-manager.users.someone.home.stateVersion = "25.05";
          boot.loader.grub.device = "/dev/sda";
          fileSystems."/" = {
            device = "/dev/sda1";
            fsType = "ext4";
          };
          system.stateVersion = "25.05";
        }
        settings
      ];
    }).config.i18n.extraLocales;

  unset = machine { programs.nixarchy.enable = true; };
  danish = machine {
    programs.nixarchy = {
      enable = true;
      language = "da";
    };
  };
  beside = machine {
    programs.nixarchy = {
      enable = true;
      language = "da";
    };
    i18n.extraLocales = [ "fr_FR.UTF-8/UTF-8" ];
  };
  modeA = machine {
    programs.nixarchy = {
      enable = false;
      language = "da";
    };
  };
in
pkgs.runCommand "nixarchy-language-locale" { } ''
  fails=0
  bad() { echo "  FAILED  $1"; fails=$((fails + 1)); }
  test '${builtins.toJSON unset}' = '[]' || bad 'language = null added a locale: ${builtins.toJSON unset}'
  test '${builtins.toJSON danish}' = '["da_DK.UTF-8/UTF-8"]' || bad 'da did not give exactly da_DK.UTF-8/UTF-8: ${builtins.toJSON danish}'
  test '${builtins.toJSON (builtins.sort builtins.lessThan beside)}' = '["da_DK.UTF-8/UTF-8","fr_FR.UTF-8/UTF-8"]' || bad 'a user extraLocales entry did not survive: ${builtins.toJSON (builtins.sort builtins.lessThan beside)}'
  test '${builtins.toJSON modeA}' = '[]' || bad 'Mode A (enable = false) gained a locale: ${builtins.toJSON modeA}'
  test "$fails" -eq 0
  echo "language-locale: every case passed"
  touch $out
''
