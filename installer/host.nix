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

  # The storage this machine might boot from, decided before we know what it
  # is.
  #
  # nixos-generate-config inspects the running machine and writes the modules
  # it found. Those are correct and they are also the reason an install has to
  # BUILD an initrd instead of copying the one already on the ISO -- a
  # different module list is a different initrd is a different toplevel, and
  # on an image with no network, building it means having a compiler, which
  # means the source bootstrap, which means the install stops.
  #
  # So the reference host carries a superset instead, and the installer pins
  # the installed machine to it when what it detected fits inside. NixOS's own
  # default set (boot.initrd.includeDefaultModules) already has nvme, ahci,
  # sd_mod, xhci_pci and mmc_block, which covers most real hardware; what it
  # lacks is everything below.
  #
  # This is not a guess about what a machine needs. It is a promise that the
  # ISO carries an initrd able to find these, so that the common cases never
  # build anything. A machine needing something outside it is still installed
  # correctly -- installer/install.sh notices and keeps the detected list,
  # which costs a build.
  boot.initrd.availableKernelModules = [
    # Virtual machines, which is where this is tested and where the default
    # set is weakest: without virtio_blk a guest cannot find its own root.
    "virtio_pci"
    "virtio_blk"
    "virtio_scsi"
    "virtio_mmio"
    # Installing from, or booting off, USB.
    "usb_storage"
    "uas"
    # SD and eMMC, on laptops and small machines.
    "sdhci_pci"
    "sdhci_acpi"
    "rtsx_pci_sdmmc"
    # qemu's default machine has a floppy controller, so every VM install
    # detects this and would otherwise be refused the baked initrd over a
    # drive nobody has had for twenty years.
    "floppy"
  ];

  # Point `nixpkgs#...` and `nixarchy#...` at what this machine was built from.
  #
  # Without this, an indirect flake reference sends nix to
  # channels.nixos.org for the global registry and then downloads a nixpkgs --
  # a different one from the machine's, so `nix shell nixpkgs#foo` can hand you
  # a binary built against a different glibc than the system's, and does it
  # after a download the machine did not need. With it, both resolve to store
  # paths that are already here, which also means they resolve with no network
  # at all: the first thing someone does on a freshly installed laptop is often
  # `nix shell nixpkgs#<the wifi tool they need>`.
  #
  # flake-registry = "" turns off the global fallback, so anything not pinned
  # here fails saying so rather than timing out against a network that may not
  # exist yet.
  # nixpkgs only, deliberately.
  #
  # A `nixarchy.flake = inputs.self` entry here looks like the obvious
  # companion and cannot work: the registry file records the flake's identity,
  # and `self` is a path in a store when the flake is evaluated locally but a
  # github pin on an installed machine. The two are never the same string, so
  # the installed system's etc -- and therefore its toplevel -- can never match
  # anything built anywhere else.
  #
  # That is not just a test problem. It means the machine's own toplevel is
  # unreproducible from the flake it was installed from, which is Invariant 1,
  # and it is why checks.install went red the moment this was added. nixpkgs is
  # safe because both sides resolve the same lock entry to the same store path.
  nix.registry.nixpkgs.flake = inputs.nixpkgs;
  nix.settings.flake-registry = "";

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

  # Snapshots, for the half of the machine generations do not cover.
  #
  # A NixOS generation restores the system closure and the /etc Nix writes.
  # It does not restore /home, and it does not restore /var/lib -- so the
  # config a person spent an evening on, and the state their services keep,
  # have had no undo at all. That is what this is for, and it is the only
  # thing it is for: the system half is already better served by generations
  # and nixarchy-rollback.
  #
  # Deliberately in host.nix and not in modules/nixos.nix. This file is
  # imported only by flakes the installer generated, so snapper reaches
  # machines nixarchy built and never a machine where somebody imported the
  # module into a configuration of their own. Taking snapshots of somebody
  # else's disk, on a schedule they did not ask for, is not this module's
  # business.
  #
  # Upstream takes a snapshot before every update and offers to boot one.
  # Neither transfers. `@` here holds almost no operating system -- the
  # kernels are on the ESP and the system is in `@nix`, a separate subvolume
  # that these snapshots exclude -- so booting a snapshot of `@` would get you
  # the same system with older /etc. Generations already are the bootable
  # snapshot, which is why the bootloader is unchanged and there is no
  # limine-snapper-sync here.
  services.snapper = {
    # Hourly timeline snapshots of the user's data, and a snapper the desktop
    # user can drive without sudo -- ALLOW_USERS is what makes `snapper -c
    # home list` and an undo of their own file something they can do.
    configs.home = {
      SUBVOLUME = "/home";
      ALLOW_USERS = [ username ];
      TIMELINE_CREATE = true;
      TIMELINE_CLEANUP = true;
    };

    # Root gets a snapshot at boot and no timeline. The timeline is for data
    # that changes while you work; /var/lib changes when a service decides to,
    # and an hourly snapshot of it is mostly noise. One per boot is the useful
    # one: it is the state you were in before whatever you are about to do.
    configs.root = {
      SUBVOLUME = "/";
      TIMELINE_CREATE = false;
      TIMELINE_CLEANUP = false;
    };
    snapshotRootOnBoot = true;

    # A laptop is asleep at some point every day, and a non-persistent timer
    # skips what it missed rather than running it late. On a machine that is
    # only ever awake this changes nothing.
    persistentTimer = true;
  };

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
