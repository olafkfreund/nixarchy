# The `nixarchy-desktop` template: the stock nixarchy desktop for the guest's
# `dev` user, with ai-mirror inside, so an MCP agent on the host can drive
# nixarchy's own keybindings, bar and omarchy-* commands in a disposable VM.
# #1513.
#
# The one template that imports another module this repo ships (see "The bar"
# in data/microvm-templates.nix): its purpose is the nixarchy desktop itself.
#
# It does not import installer/host.nix. That file is the installed machine --
# systemd-boot, nh pointed at /etc/nixos, installerManaged, GC floors -- and
# fighting it from a microvm needs mkForce for the bootloader and more. Only
# the programs.nixarchy and home-manager lines carry over.
#
# Rendering is in software: the guest has a virtio GPU for a DRM device but no
# host GL behind it (#1506), so WLR_RENDERER_ALLOW_SOFTWARE and
# LIBGL_ALWAYS_SOFTWARE are what let the compositor start at all.
{ inputs, ... }:
{
  imports = [
    inputs.self.nixosModules.nixarchy
    inputs.home-manager.nixosModules.home-manager
    ./ai-mirror-guest.nix
  ];

  programs.nixarchy = {
    enable = true;
    user = "dev";
  };

  home-manager = {
    useGlobalPkgs = true;
    useUserPackages = true;
    sharedModules = [ inputs.self.homeManagerModules.nixarchy ];
    users.dev = {
      programs.nixarchy.enable = true;
      home.stateVersion = "25.05";
    };
  };

  services.displayManager.autoLogin = {
    enable = true;
    user = "dev";
  };

  environment.sessionVariables = {
    WLR_RENDERER_ALLOW_SOFTWARE = "1";
    LIBGL_ALWAYS_SOFTWARE = "1";
  };

  services.gnome.at-spi2-core.enable = true;

  microvm = {
    qemu.extraArgs = [
      "-device"
      "virtio-gpu-pci"
    ];
    mem = 8192;
    vcpu = 4;
  };
}
