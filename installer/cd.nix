{
  inputs,
  lib,
  pkgs,
  modulesPath,
  # Whether this image carries the desktop or downloads it. True is the real
  # product -- see the header. False builds the same installer over the network
  # instead, which is the same install path the `install` check has always
  # exercised: without the marker file at the bottom of this file, install.sh
  # keeps the substituters it already has.
  #
  # Passed by both nixosConfigurations, with no default here on purpose. A
  # module argument's default is not a function default: the module system
  # cannot see one without consulting _module.args, which needs `config`,
  # which is what is being evaluated -- so `offline ? true` fails the ISO
  # build outright rather than defaulting. Making both callers say which
  # image they want is also the honest reading of a flag this load-bearing.
  offline,
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
# This image installs with no network. Nothing is fetched, and the installer
# is told not to try -- see `substituters` below for why being told matters as
# much as having the paths.
#
# Two halves, which fail in different places and are worth telling apart:
#
#   storeContents puts the OUTPUTS on the image, so nixos-install copies a
#   desktop instead of downloading one. A gap here reads as
#   "cannot build ... hyprland ... no substituter".
#
#   extraDependencies puts the SOURCES on it, so `nix` can evaluate the
#   generated flake at all. A gap here reads as "unable to download
#   'https://api.github.com/...'", and it happens BEFORE any copying, which
#   is what makes it easy to mistake for the other one.
#
# An ISO can still only install from a PUBLISHED commit.
#
# The flake this writes to /etc/nixos pins `github:olafkfreund/nixarchy/<rev>`,
# and <rev> is whatever commit the image was built from. Offline that resolves
# from the store by narHash and the rev is never dereferenced -- so an image
# built from an unpushed commit installs fine and then hands its owner a flake
# that 404s on the first `nix flake update`. Offline installs hide this rather
# than fixing it; #19 builds release images from tags, which does fix it.
#
# nixosModules.nixarchy is deliberately NOT imported. The live image does not
# need a desktop; importing the module would make it one, at several gigabytes,
# to run a text installer for ninety seconds.
let
  # Every locked input, transitively, as a store path.
  #
  # Not the top-level inputs: hyprland does not follow nixpkgs, so it brings
  # its own nixpkgs, aquamarine, hyprlang, hyprutils, hyprcursor, hyprgraphics,
  # hyprwayland-scanner and xdph, and each of those brings more. Collected
  # rather than listed, because a hand-written list goes stale on the next bump
  # and the staleness only shows up as a network fetch on a machine that has no
  # network.
  collectInputs =
    flake: [ flake.outPath ] ++ lib.concatMap collectInputs (lib.attrValues (flake.inputs or { }));

  inputSources = lib.unique (collectInputs inputs.self);

  # Both disk modes, because the installer offers both.
  #
  # The image bakes a machine that does not exist -- hostname "nixarchy", the
  # placeholder disk -- so that the machine the user does install shares
  # everything expensive with it. Encryption is the one answer that changes
  # the shared part: 51 derivations differ between the two, 180 MiB, all of
  # them unit files and etc fragments. Small, but not present is not present,
  # and on an image with no network a missing text derivation means building
  # stdenv to produce it, which means the source bootstrap, which means the
  # install stops.
  #
  # Found the hard way: an image carrying only the encrypted reference
  # installs an encrypted machine perfectly and dies partway through an
  # unencrypted one.
  referenceConfigs = map (c: c.config) [
    inputs.self.nixosConfigurations.reference
    inputs.self.nixosConfigurations.reference-unencrypted
  ];

  references = map (c: c.system.build) referenceConfigs;

  # What an installed machine will have to BUILD, and therefore what it needs
  # the parts for.
  #
  # A real machine gets a hardware-configuration.nix that the reference host
  # does not have, and that is not a detail: it changes the initrd, which
  # changes the module closure, which changes the toplevel. Twelve derivations
  # differ -- measured, not guessed -- and every one of them has to be built on
  # the target, from parts, with no network.
  #
  # inputDerivation is nixpkgs' own answer to "realise everything this
  # derivation is built FROM". Seeding it for the toplevel, the initrd and etc
  # puts their build inputs on the image, so building a differently-configured
  # one is a matter of assembling parts rather than of finding a compiler.
  #
  # Without it the install gets a long way -- partitions the disk, evaluates
  # the flake offline, starts copying -- and then tries to build the initrd,
  # finds no stdenv to build it with, works backwards to the source bootstrap
  # and dies fetching a perl tarball from CPAN.
  buildInputsOfWhatChanges =
    map (c: c.system.build.toplevel.inputDerivation) referenceConfigs
    ++ map (c: c.system.build.initialRamdisk.inputDerivation) referenceConfigs
    ++ map (c: c.system.build.etc.inputDerivation) referenceConfigs
    # The module closure is shrunk from this tree by kmod, and neither the tree
    # nor the tools are in any runtime closure.
    ++ map (c: c.system.modulesTree) referenceConfigs
    ++ [
      pkgs.kmod
      pkgs.nukeReferences

      # kmod's `dev` output, and it is worth saying why one output of one
      # package gets its own entry.
      #
      # The installed machine has to build its own initrd, because a systemd
      # initrd embeds the hostname -- initrd-hostname, initrd-group,
      # initrd-release are all per-machine, so no baked initrd can ever match
      # one belonging to a machine with a different name. Building it means
      # building linux-<v>-modules-shrunk, and that wants kmod's dev output.
      # Everything else it wants is here: stdenv, the module tree, nuke-refs,
      # bash. Just not this.
      #
      # Nix does not degrade over a missing build input; it builds it. Building
      # kmod means a compiler, which is not here either, so it works backwards
      # to the source bootstrap and the install ends several minutes later
      # trying to download a perl tarball from CPAN. Measured on this graph:
      # without this line 619 derivations have to be built and the bootstrap is
      # reachable; with it, 76, and it is not. All 76 are per-machine text
      # files that assemble from parts already on the image.
      #
      # The general lesson, since this cost a day: a `-dev` output is a real
      # build input. Seeding a package by name gives you `out`, and that is not
      # the same thing.
      pkgs.kmod.dev
    ];
in
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

    # The desktop, on the image. This is the difference between an install
    # that copies and one that downloads, and it is most of the image's size:
    # the reference closure is 15.3 GiB unpacked, and the squashfs is zstd.
    #
    # The REFERENCE host's closure, not the user's. Their hostname, username
    # and disk differ, so their toplevel is a different store path and is not
    # here -- but everything expensive underneath it is, and the handful of
    # text derivations that differ are built on the spot from the build
    # environment below.
    #
    # Not nixosConfigurations.vm: it imports qemu-vm.nix and carries guest
    # tooling nobody installs on metal.
    #
    # This is the whole difference between the two images. Dropped entirely
    # when `offline` is false: the desktop then comes from the binary caches
    # named under nix.settings below.
    #
    # ## The size budget, measured 2026-09-01
    #
    #   reference closure   15.3 GiB unpacked   what the install produces
    #   packages.iso         5.6 GB             this image, offline
    #   packages.iso-net     1.54 GiB           the network image
    #
    # Budgets, enforced by checks.iso-budget rather than written down and
    # forgotten:
    #
    #   iso       6.5 GiB   headroom over 5.6, tight enough to notice a jump
    #   iso-net   2 GiB     NOT a preference. GitHub refuses a release asset
    #                       over 2 GiB, so crossing this does not make the
    #                       download annoying, it makes it impossible to
    #                       publish as one file. See .github/workflows/
    #                       release.yml, which splits the image above and
    #                       ships this one whole.
    #
    # ## No apps on the image, deliberately
    #
    # The reference host enables no programs.nixarchy.apps.*, and should not
    # start. The 52 selectable apps are a post-install concern, reached
    # through the Install menu once the machine is the user's: several are
    # unfree, several are hundreds of megabytes each, and baking even the free
    # half would roughly double an image for apps most people never pick. The
    # base desktop is what everyone gets and therefore what is worth carrying.
    #
    # ## Compression: nothing to tune here
    #
    # isoImage.squashfsCompression is `zstd -Xcompression-level 19` -- the
    # nixpkgs default, already, so the argument for moving off xz (~100 MB/s
    # decompressing a live root read cold, against zstd's ~900 MB/s) is one
    # this image already wins. Level 19 over level 6 costs build time on a
    # machine with plenty and saves a download for every user, which is the
    # right way round.
    #
    # Storing the tree UNCOMPRESSED inside the squashfs -- what Omarchy does
    # with its package mirror -- does not port. Theirs is already-compressed
    # pacman packages, where the outer compression buys nothing. A Nix store
    # is not: 15.3 GiB becomes 5.6 GB here, 2.7x. Uncompressed would mean a
    # ~15 GB image to save decompression on a file read once.
    storeContents = lib.optionals offline (
      map (r: r.toplevel) references
      # The installer runs this before anything else, and it is not part of
      # any runtime closure.
      ++ map (r: r.diskoScript) references
    );
  };

  # Everything needed to EVALUATE the generated flake, and to build the few
  # derivations that are genuinely per-machine.
  #
  # extraDependencies rather than storeContents for these: the option's stated
  # purpose is "paths that must be in the store for this system to be usable",
  # which is exactly the claim being made.
  #
  # inputSources stays on BOTH images. It is the flake sources rather than the
  # desktop, it costs little, and it means evaluation starts immediately
  # instead of fetching a nixpkgs tarball before the first question. The build
  # environment below is offline-only: with a network, anything missing is
  # downloaded rather than built.
  system.extraDependencies =
    inputSources
    ++ lib.optionals offline [
      # nixos-install builds roughly twenty derivations for the real hostname,
      # user and disk -- etc, users-groups.json, system-path, the bootloader
      # entry, the toplevel -- and their build inputs are in no runtime
      # closure. Measured by installing offline and reading what was missing,
      # not guessed.
      #
      # isoImage.includeSystemBuildDependencies would cover this and is not
      # usable: it pulls the entire build graph of the image's own system,
      # compilers and source tarballs included, at tens of gigabytes.
      pkgs.stdenv
      pkgs.stdenvNoCC
      pkgs.stdenv.cc
      pkgs.gnumake
      pkgs.gnutar
      pkgs.diffutils
      pkgs.patchelf
      pkgs.file
      pkgs.findutils
      pkgs.gawk
      pkgs.gnused
      pkgs.gnugrep
      pkgs.gzip
      pkgs.xz
      pkgs.bash
      pkgs.bashInteractive
      pkgs.coreutils
      pkgs.perl
      # systemd-boot-builder.
      pkgs.python3
      pkgs.jq
    ]
    ++ lib.optionals offline buildInputsOfWhatChanges;

  nix.settings = {
    # flake-registry is a flakes setting, and nix.conf is validated at build
    # time: setting it without this fails the ISO build with "Ignoring setting
    # 'flake-registry' because experimental feature 'flakes' is not enabled",
    # which is at least an honest error rather than a silently ignored line.
    #
    # install.sh passes --extra-experimental-features on every nix call
    # because a stock live medium may not have them. This is not a stock live
    # medium.
    experimental-features = [
      "nix-command"
      "flakes"
    ];
  }
  # Everything below is one choice made twice. The offline image must be told
  # there is nothing to fetch; the network image must be told where to fetch
  # from. Neither set is a sensible default for the other, and the failure when
  # they are crossed is a hang rather than an error.
  // lib.optionalAttrs offline {
    # Nothing to fetch, and nothing that may try.
    #
    # An empty list is not the same as an unreachable one. With a substituter
    # configured and no network, nix waits out a connection timeout for every
    # path before falling back to the local store, and an install that is
    # actually working looks hung for several minutes. Saying there are none
    # makes the store the first answer rather than the last.
    #
    # It also means the image's completeness is tested by everyone who uses
    # it, rather than silently patched over on machines that happen to have a
    # network.
    substituters = lib.mkForce [ ];

    # An indirect reference -- `nixpkgs#hello`, or any flake input that is not
    # already locked -- sends nix to channels.nixos.org for the global
    # registry. There is no network, so that is a timeout rather than an
    # answer.
    flake-registry = "";

    # Never re-fetch a locked input whose source is already here.
    #
    # This is the line that makes the image offline, and it is not obvious.
    # Every input's source IS on the image, and `nix eval --offline` resolves
    # all of them from the store by narHash -- but the default tarball-ttl is
    # an hour, so a locked github: input older than that is considered stale
    # and nix goes to fetch it BEFORE looking in the store. With no network
    # that is not a fallback, it is the end of the install:
    #
    #   error: unable to download
    #   'https://github.com/olafkfreund/nixarchy/archive/<rev>.tar.gz':
    #   Could not resolve host: github.com
    #
    # -- after the disk has been partitioned. An infinite ttl makes the store
    # the first answer.
    #
    # This is the `tarball-ttl` half of what `nix --offline` sets. The other
    # half, `substitute = false`, must NOT be set: nixos-install builds into
    # the target store and copies from this one by declaring it a substituter,
    # so turning substitution off would leave it rebuilding a desktop it
    # already has.
    tarball-ttl = 4294967295;

    # Fail rather than hang, for anything that still tries. Five attempts at
    # fifteen seconds each is over a minute of silence per path on an image
    # that by construction has nothing to download.
    connect-timeout = 1;
    download-attempts = 0;
  }
  // lib.optionalAttrs (!offline) {
    # The same two caches install.sh already knows about and modules/nixos.nix
    # gives every installed machine. They are not a nicety here: CI builds
    # checks.reference-toplevel inside a cachix job, so the whole 15.3 GiB
    # desktop is on nixarchy.cachix.org. Without these the install still
    # succeeds and takes hours, because it compiles Hyprland.
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

  # Read by installer/install.sh, which uses it to decide that it is running
  # from this image and must not reach for a substituter. A marker file rather
  # than a kernel parameter: the installer can also be run by hand from a
  # mounted image, and the file travels with the filesystem.
  #
  # Its ABSENCE is what makes the network image work, and that is the whole
  # mechanism -- install.sh already carries both cachix substituters and only
  # clears them when it finds this file. So there is no second install path to
  # keep working; there is one, and this file switches it.
  environment.etc =
    if offline then
      {
        "nixarchy-iso".text = ''
          ${inputs.self.shortRev or "dirty"}
        '';
      }
    else
      {
        # The mirror of the above, and the installer's cue to make sure there
        # is a network before it asks anything else. A marker of its own rather
        # than "no offline marker": the install check runs with neither, in a
        # sandbox with no network, and must not be told to go and find one.
        "nixarchy-iso-net".text = ''
          ${inputs.self.shortRev or "dirty"}
        '';
      };

  system.stateVersion = "25.05";
}
