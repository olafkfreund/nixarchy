# The profile a user actually gets, built rather than inspected.
#
# #809: both panel defaults contributed a bare `pkgs.python3` to
# `home.packages`. A user who keeps their own interpreter there --
# `python3.withPackages (ps: ...)`, the documented way to have a Python with
# libraries -- then had two in one profile, and `buildEnv` refuses:
#
#   pkgs.buildEnv error: two given paths contain a conflicting subpath:
#     `/nix/store/...-python3-3.14.7/bin/idle3' and
#     `/nix/store/...-python3-3.14.7-env/bin/idle3'
#
# The derivation that fails is `home-manager-path`, so the whole system closure
# fails with it and the machine cannot leave its old generation. It was found by
# a person rebuilding, not by a check: tests/options.nix reads evaluated
# configuration, and this failure only exists once something builds the profile
# (AGENTS.md §2 -- the highest layer that can see it).
#
# `checks.options` carries the rule (`defaultRuntimeToolsLowPriority`). This
# carries the symptom, and it is deliberately not the same assertion: a profile
# that builds is not yet a profile where the user's interpreter won, so both are
# asserted here.
{
  inputs,
  pkgs,
}:
let
  system = pkgs.stdenv.hostPlatform.system;

  # The machine the home sits on: nixarchy on, so the defaults are on, which is
  # the state every install is in since #770/#772.
  osConfig =
    (inputs.nixpkgs.lib.nixosSystem {
      inherit system;
      modules = [
        inputs.self.nixosModules.nixarchy
        { programs.nixarchy.enable = true; }
        {
          networking.hostName = "testbox";
          boot.loader.grub.device = "/dev/sda";
          fileSystems."/" = {
            device = "/dev/sda1";
            fsType = "ext4";
          };
          system.stateVersion = "25.05";
        }
      ];
    }).config;

  # The user's own interpreter, with a library in it, so "whose python won" has
  # an answer that cannot be read off a store path alone.
  userPython = pkgs.python3.withPackages (ps: [ ps.pytest ]);

  home =
    (inputs.home-manager.lib.homeManagerConfiguration {
      inherit pkgs;
      extraSpecialArgs = { inherit osConfig; };
      modules = [
        inputs.self.homeManagerModules.nixarchy
        {
          home = {
            username = "someone";
            homeDirectory = "/home/someone";
            stateVersion = "25.05";
            packages = [ userPython ];
          };
          programs.nixarchy.enable = true;
        }
      ];
    }).config;

  # The same buildEnv Home Manager builds for `home.packages`, with the same
  # collision behaviour. Building `home.activationPackage` would drag in the
  # whole activation script for no extra answer.
  profile = pkgs.buildEnv {
    name = "nixarchy-home-profile-809";
    paths = home.home.packages;
    ignoreCollisions = false;
  };
in
pkgs.runCommand "nixarchy-home-profile"
  {
    inherit profile;
    nativeBuildInputs = [ pkgs.coreutils ];
    userPython = "${userPython}";
  }
  ''
    set -euo pipefail

    # 1. It builds at all. If the defaults' python3 is at default priority this
    #    derivation never gets here -- buildEnv refuses over bin/idle3.
    test -x "$profile/bin/python3" || {
      echo "the profile has no bin/python3 at all" >&2
      exit 1
    }

    # 2. The user's interpreter won. Without this, "it built" would also pass
    #    with nixarchy's copy winning, which is the bug wearing a green light.
    target=$(readlink -f "$profile/bin/python3")
    case "$target" in
      "$userPython"/*) ;;
      *)
        echo "the profile's python3 is not the user's:" >&2
        echo "  resolved: $target" >&2
        echo "  user's:   $userPython" >&2
        exit 1
        ;;
    esac

    # 3. And it is still the interpreter they built, libraries and all.
    "$profile/bin/python3" -c 'import pytest' || {
      echo "the profile's python3 cannot import the library the user put in it" >&2
      exit 1
    }

    echo "the user's python3 wins the profile, and keeps its libraries" > "$out"
  ''
