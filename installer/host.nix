# The Omarchy host, as installed. Imported by the generated flake the installer
# writes, and by vm/configuration.nix, which layers qemu-only overrides on top.
#
# The boundary: anything true of a real machine belongs here; anything true only
# of a throwaway guest stays in vm/. Extracting this rather than writing it fresh
# is what stops the smoke test and the installed machine drifting apart --
# checks.vm-toplevel keeps building the same module the installer ships.
#
# Deliberately absent: networkmanager, pipewire and SDDM. modules/nixos.nix
# already sets all three at mkDefault, and a second definition here would be
# dead config that reads like a decision.
{
  hostname,
  username,
}:
{
  inputs,
  lib,
  pkgs,
  ...
}:
{
  programs.nixarchy = {
    enable = true;

    # Puts the user in the `input` group -- upstream's installer does
    # `usermod -aG input`, and without it dictation and controllers cannot read
    # their devices. The module cannot guess who logs in, so it is told.
    user = username;

    # Where nixarchy-apply copies the app selection before rebuilding. Stated
    # even though modules/apps.nix defaults to the same path: on an installed
    # machine this is the installer's decision, not a default it could later
    # lose without anyone noticing.
    flake = "/etc/nixos";
  };

  # `nh os switch` is the loop the user lives in, and it only works with no
  # arguments if nh knows which flake it is switching -- otherwise it fails, or
  # picks up $NH_FLAKE from somewhere else entirely.
  #
  # The GC timer is the part Arch has no equivalent of and NixOS badly needs.
  # Without it a machine that updates weekly accumulates every old generation
  # and the owner finds out when the disk fills. Fourteen days and five
  # generations keeps rollback useful without unbounded growth.
  programs.nh = {
    enable = true;
    flake = "/etc/nixos";
    clean.enable = true;
    clean.extraArgs = "--keep-since 14d --keep 5";
  };

  home-manager = {
    useGlobalPkgs = true;
    useUserPackages = true;
    sharedModules = [ inputs.self.homeManagerModules.nixarchy ];
    users.${username} = {
      programs.nixarchy.enable = true;
      home.stateVersion = "25.05";
    };
  };

  users.users.${username} = {
    isNormalUser = true;
    extraGroups = [
      "wheel"
      "video"
      "input"
      "docker"
      "i2c"
    ];
    # No password here. The installer writes hashedPassword into the generated
    # configuration.nix; the VM sets a plaintext one as its own definition.
  };

  networking.hostName = hostname;

  boot.loader = {
    systemd-boot.enable = true;
    efi.canTouchEfiVariables = true;
  };

  # mkDefault: the generated configuration.nix carries the answers the installer
  # collected, and must win over these without needing mkForce.
  time.timeZone = lib.mkDefault "UTC";
  i18n.defaultLocale = lib.mkDefault "en_US.UTF-8";
  console.keyMap = lib.mkDefault "us";

  # Redundant with the module's own default since #57, and deliberately so: this
  # file becomes the user's own configuration.nix, and a licence policy they
  # cannot see is one they cannot change.
  nixpkgs.config.allowUnfree = true;

  # The flake on disk is a git repository, and nixarchy-apply needs git on PATH
  # to stage the selection it copies in.
  environment.systemPackages = [ pkgs.git ];

  system.stateVersion = "25.05";
}
