{ inputs, pkgs }:
# Builds nixarchy on top of a config that already exists.
#
# Everything else here tests a fresh install: vm-toplevel, session and coexist
# all start from a machine that has nothing. Three bugs shipped anyway, and all
# three were invisible to that:
#
#   * upstream's Zoom.desktop collided with the zoom package's, and buildEnv
#     refuses a profile holding both
#   * both modules took their package from inputs.self, so ~80 runtime
#     dependencies came from nixarchy's nixpkgs rather than the user's
#   * those dependencies were listed in home.packages *and*
#     environment.systemPackages, so any of them the user had overridden
#     collided with the stock one
#
# None of them is an evaluation error. They live in derivations that only exist
# once something is built, which is why a real `nix build` against a real
# config found them and nothing here did.
#
# So this is deliberately *built*, not evaluated, and the config below is not a
# clean machine: it overrides a package nixarchy also uses, brings its own
# Hyprland, and greets with greetd. That is the shape that broke.
let
  system = pkgs.stdenv.hostPlatform.system;

  existing =
    { lib, pkgs, ... }:
    {
      # A package nixarchy also pulls in, built differently. Same version,
      # different derivation -- exactly what `pkgs.tesseract.override { ... }`
      # was on the machine that found this. qrencode because it is small: the
      # point is the collision, not the compile.
      home-manager.users.tester.home.packages = [
        (pkgs.qrencode.overrideAttrs (old: {
          postInstall = (old.postInstall or "") + ''
            mkdir -p $out/share
            echo "not the stock build" > $out/share/nixarchy-marker
          '';
        }))
      ];

      # Its own Hyprland, at nixpkgs' version rather than nixarchy's pin. The
      # module sets programs.hyprland.package outright, so this is the mkForce
      # the doctor tells people to add.
      programs.hyprland = {
        enable = true;
        package = lib.mkForce pkgs.hyprland;
        portalPackage = lib.mkForce pkgs.xdg-desktop-portal-hyprland;
      };

      # Already greeting. nixarchy must not add a second display manager.
      services.greetd = {
        enable = true;
        settings.default_session = {
          command = "${pkgs.hyprland}/bin/Hyprland";
          user = "tester";
        };
      };
    };
  built =
    (inputs.nixpkgs.lib.nixosSystem {
      inherit system;
      modules = [
        inputs.self.nixosModules.nixarchy
        inputs.home-manager.nixosModules.home-manager
        existing
        {
          programs.nixarchy = {
            enable = true;
            # greetd is already greeting; this is the other half of what the
            # doctor prints for a machine like this.
            displayManager = false;
          };

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
    }).config;

  # The Hyprland this configuration asked for, still the one on PATH.
  #
  # The omarchy package carries the compositor its Lua config is written
  # against as a runtime dependency, and every runtime dependency went into
  # environment.systemPackages -- so on a machine that already ran Hyprland,
  # enabling nixarchy replaced the binary behind the user's *existing*
  # sessions, and its share/wayland-sessions/hyprland.desktop won the buildEnv
  # collision as well. Nothing failed; the compositor just quietly changed.
  #
  # This config mkForces nixpkgs' Hyprland, which is what the doctor tells
  # people with their own to do, so the profile must contain that one.
  ours = built.programs.hyprland.package;
  profile = built.system.path;
in
pkgs.runCommand "nixarchy-integration"
  {
    toplevel = built.system.build.toplevel;
    inherit profile;
    wanted = ours.name;

    # Omarchy's manual promises LocalSend "works out of the box on a
    # fresh install" because the firewall is closed "except for
    # LocalSend's port". This module enables that firewall, so it owes
    # the exception -- and shipped the deny half without the allow half.
    localsendTcp = builtins.toString (builtins.elem 53317 built.networking.firewall.allowedTCPPorts);
    localsendUdp = builtins.toString (builtins.elem 53317 built.networking.firewall.allowedUDPPorts);
  }
  ''
    echo "configuration asked for: $wanted"
    on_path=$(basename "$(readlink -f "$profile/bin/Hyprland")" | sed 's|/bin/Hyprland||')
    got=$(readlink -f "$profile/bin/Hyprland" | sed 's|^/nix/store/[a-z0-9]*-||; s|/bin/Hyprland$||')
    echo "on PATH:                 $got"
    if [ "$got" != "$wanted" ]; then
      echo "" >&2
      echo "nixarchy replaced the Hyprland this configuration chose." >&2
      echo "A machine that already runs Hyprland would find its own sessions" >&2
      echo "started by a different compositor after enabling nixarchy." >&2
      exit 1
    fi

    session=$(readlink "$profile/share/wayland-sessions/hyprland.desktop" || true)
    case "$session" in
      *"$wanted"*) ;;
      "") echo "no hyprland.desktop in the profile" >&2; exit 1 ;;
      *) echo "hyprland.desktop points at $session, not $wanted" >&2; exit 1 ;;
    esac

    echo "the configuration's own Hyprland survived, sessions included"

    # 53317 on both protocols: LocalSend discovers over UDP and
    # transfers over TCP, so opening one leaves Share > Receive
    # visible and unusable.
    [ "$localsendTcp" = "1" ] || { echo "firewall does not open TCP 53317 for LocalSend" >&2; exit 1; }
    [ "$localsendUdp" = "1" ] || { echo "firewall does not open UDP 53317 for LocalSend" >&2; exit 1; }
    echo "LocalSend's port is open on both protocols"
    touch $out
  ''
