{ inputs, pkgs }:
# The option paths our documentation quotes, against the option set that exists.
#
# #214 is the case: `programs.nixarchy.apps.tailscale.settings.useRoutingFeatures`
# sat in the manual as a worked example a reader was invited to copy, for as
# long as it took someone to try it. Tailscale had moved to the services
# catalogue and the option was gone; nothing noticed, because prose is not
# built.
#
# The repo already refuses to trust prose about numbers -- build.yml derives
# the app and subcommand counts from the data and fails when the README
# disagrees. An option path is the same class of claim, and cheaper: the
# module system already knows every option that exists.
let
  inherit (pkgs) lib;

  eval = inputs.nixpkgs.lib.nixosSystem {
    system = pkgs.stdenv.hostPlatform.system;
    modules = [
      inputs.self.nixosModules.nixarchy
      inputs.home-manager.nixosModules.home-manager
      {
        programs.nixarchy.enable = true;
        home-manager = {
          useGlobalPkgs = true;
          useUserPackages = true;
          sharedModules = [ inputs.self.homeManagerModules.nixarchy ];
          users.tester = {
            programs.nixarchy.enable = true;
            home.stateVersion = "25.05";
          };
        };
        users.users.tester = {
          isNormalUser = true;
          home = "/home/tester";
        };
        boot.loader.grub.device = "/dev/sda";
        fileSystems."/" = {
          device = "/dev/sda1";
          fsType = "ext4";
        };
        system.stateVersion = "25.05";
      }
    ];
  };

  # Both halves, because `programs.nixarchy` is two namespaces wearing one
  # name: the system module declares apps, services and the installer's
  # settings, the Home Manager module declares the theme, neovim and plugins.
  # A reader writing one of those paths does not know or care which module it
  # came from, and a check that knew only the system half would call
  # `programs.nixarchy.defaultTheme` a mistake.
  systemOptions = eval.options.programs.nixarchy;
  homeOptions = (eval.options.home-manager.users.type.getSubOptions [ ]).programs.nixarchy;

  # Leaves and branches kept apart, because what may follow them differs: a
  # leaf can be freeform and take attributes nothing here can enumerate, a
  # branch takes exactly the names below it. See tests/doc-option-paths.py.
  walk =
    prefix: attrs:
    lib.concatLists (
      lib.mapAttrsToList (
        name: value:
        let
          path = "${prefix}.${name}";
        in
        if lib.isOption value then
          [ { option = path; } ]
        # `_type` marks a module-system value that is not a nested option set.
        else if lib.isAttrs value && !(value ? _type) then
          [ { group = path; } ] ++ walk path value
        else
          [ ]
      ) attrs
    );

  nodes = walk "programs.nixarchy" systemOptions ++ walk "programs.nixarchy" homeOptions;

  known = pkgs.writeText "nixarchy-options.json" (
    builtins.toJSON {
      options = lib.catAttrs "option" nodes;
      groups = lib.catAttrs "group" nodes;
    }
  );
in
pkgs.runCommand "doc-options" { nativeBuildInputs = [ pkgs.python3 ]; } ''
  python3 ${./doc-option-paths.py} ${known} ${../README.md} ${../docs}
  touch $out
''
