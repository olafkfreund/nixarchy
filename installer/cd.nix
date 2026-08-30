{
  inputs,
  lib,
  pkgs,
  modulesPath,
  ...
}:
# The live image: boot it, answer the questions, get a machine.
#
# Phase 1's path -- boot the stock NixOS minimal ISO and
# `nix run github:olafkfreund/nixarchy#install` -- works, and asks a person to
# have a configured network and to wait through a flake evaluation and a
# Hyprland fetch before the first question. This is the answer to that, and it
# is what Omarchy ships.
#
# Still online at this stage. Baking the closure onto the image (#15) and
# making evaluation work with no network (#16) come after, and are separate
# because they fail in different places and are worth telling apart.
#
# An ISO can only install from a PUBLISHED commit.
#
# The flake this writes to /etc/nixos pins `github:olafkfreund/nixarchy/<rev>`,
# and <rev> is whatever commit the image was built from. Build an ISO from an
# unpushed commit and the install dies partway through with a 404 on
# github.com/.../archive/<rev>.tar.gz -- after the disk has been partitioned,
# which is the worst possible moment for it.
#
# Nothing here can fix that while the image is online: nix prefers to fetch a
# locked github: input rather than resolve it from a store path that already
# has the right narHash, so carrying the source on the image does not help.
# Offline it does resolve from the store -- demonstrated in tests/install.nix
# -- which is why #16 is what actually removes this constraint, and why #19
# builds release images from tags.
#
# nixosModules.nixarchy is deliberately NOT imported. The live image does not
# need a desktop; importing the module would make it one, at several gigabytes,
# to run a text installer for ninety seconds.
{
  imports = [ "${modulesPath}/installer/cd-dvd/installation-cd-minimal.nix" ];

  environment.systemPackages = [
    inputs.self.packages.${pkgs.stdenv.hostPlatform.system}.install
    pkgs.git
  ];

  # installation-cd-minimal brings wpa_supplicant; the installed machine uses
  # NetworkManager, and so does anyone reaching for nmtui when the wireless
  # does not come up on its own. The two conflict, so one has to go, and it
  # should be the one the finished system does not use.
  networking.wireless.enable = lib.mkForce false;
  networking.networkmanager.enable = true;

  # Straight into the installer, with no boot menu -- upstream shows none and
  # a menu nobody reads is a menu that only ever delays the install.
  #
  # Plymouth is NOT enabled here yet. programs.nixarchy.bootSplash renders
  # Omarchy's theme from their vendored artwork, and shipping another project's
  # logo on our boot screen is the wrong default even where the licence allows
  # it. #46 draws ours; this gains `splash` then.
  boot = {
    loader.timeout = lib.mkForce 0;

    # `quiet` alone is not enough. It lowers the console log level but leaves
    # anything at KERN_ERR and above going straight to tty1, which is where the
    # installer draws -- an OOM kill or a disk warning paints itself across the
    # progress bar and the screen never recovers. loglevel=3 keeps the console
    # for the installer; everything still reaches the journal and dmesg.
    kernelParams = [
      "quiet"
      "loglevel=3"
      "udev.log_level=3"
      "rd.systemd.show_status=false"
      # Kernel messages to the serial line as well. tty0 is listed LAST and so
      # stays the primary console -- the installer keeps the screen, and a
      # headless run or a support request still has somewhere to read from.
      "console=ttyS0,115200"
      "console=tty0"
    ];
    consoleLogLevel = 0;
  };

  # Give the console the whole screen.
  #
  # Without a DRM driver bound early the kernel keeps the VGA text console, and
  # that console is 80x25 no matter how large the display is -- measured inside
  # this ISO: stty says 25 80 while /sys/class/graphics/fb0 says 1600x900. The
  # installer then correctly centres itself in 80 columns and correctly looks
  # like it is hunched in the top-left corner of the screen.
  #
  # Real hardware usually binds i915/amdgpu/nouveau on its own; a VM needs to
  # be told. These are cheap to carry and do nothing on a machine that has
  # already sorted itself out.
  boot.initrd.kernelModules = [
    "virtio_gpu"
    "bochs"
  ];

  # The installer owns tty1.
  #
  # A systemd unit rather than a shell hook, and the choice matters: Ctrl-C
  # leaves a usable root shell instead of relaunching the TUI, and opening a
  # second shell on tty1 does not start a second installer.
  #
  # `conflicts` is the load-bearing line. Without it the autologin getty that
  # installation-device.nix puts on tty1 keeps the terminal and the installer
  # draws underneath a login prompt -- which is exactly what happened three
  # times over in installer/vm.nix before the cause was understood.
  systemd.services.nixarchy-installer = {
    description = "nixarchy installer";
    after = [
      "getty@tty1.service"
      "network-online.target"
    ];
    wants = [ "network-online.target" ];
    wantedBy = [ "multi-user.target" ];
    conflicts = [ "getty@tty1.service" ];
    # A systemd service inherits no TERM, and without one tput cannot report
    # the console size -- the installer then draws a 92-column wordmark into an
    # assumed 80, clipped, with every other line at column zero. ui.sh asks
    # stty instead, and this is here so anything else that wants a terminal
    # gets a sane answer too.
    environment.TERM = "linux";

    serviceConfig = {
      Type = "idle";
      StandardInput = "tty";
      StandardOutput = "tty";
      TTYPath = "/dev/tty1";
      TTYReset = true;
      TTYVHangup = true;
      ExecStart = lib.getExe inputs.self.packages.${pkgs.stdenv.hostPlatform.system}.install;
      # Finished, aborted or crashed, do not respawn a TUI in a loop.
      Restart = "no";
    };
  };

  # image.baseName, not isoImage.isoName. The latter still evaluates -- it is a
  # renamed alias since 25.05 -- so setting it looks like it worked, right up
  # until the built file is called nixos-minimal-*.iso anyway. The filename is
  # derived from image.baseName.
  # mkForce because installation-cd-base sets this too, at the same priority.
  image.baseName = lib.mkForce "nixarchy-${inputs.self.shortRev or "dirty"}-x86_64";

  isoImage = {
    volumeID = "NIXARCHY";
    makeEfiBootable = true;
    makeUsbBootable = true;
  };

  # The same caches the installed machine uses, so an install from this image
  # never compiles a compositor. Keys copied from modules/nixos.nix -- do not
  # retype them.
  nix.settings = {
    substituters = [
      "https://cache.nixos.org"
      "https://nixarchy.cachix.org"
      "https://hyprland.cachix.org"
    ];
    trusted-public-keys = [
      "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
      "nixarchy.cachix.org-1:05JOuIlsQOWY2/5DQMq7JEA1hwlhgvmMWowMfka8mMM="
      "hyprland.cachix.org-1:a7pgxzMz7+chwVL3/pzj6jIITemDosxrE9/Kb+PfYvE="
    ];
  };

  system.stateVersion = "25.05";
}
