{
  inputs,
  config,
  lib,
  pkgs,
  modulesPath,
  # The flake whose inputs the image carries. Passed through specialArgs;
  # module arguments cannot use a function default here.
  source,
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
# The flake inputs are on the image so evaluation can start without fetching
# them. The installed system comes from the configured caches.
#
# nixosModules.nixarchy is deliberately NOT imported. The live image does not
# need a desktop; importing the module would make it one, at several gigabytes,
# to run a text installer for ninety seconds.
let
  # Every locked input, transitively, as a store path -- the same walk the
  # installed host roots its inputs with (#701); see lib.inputSources in flake.nix.
  inputSources = inputs.self.lib.inputSources { inherit (source) flake; };

  version = inputs.self.packages.${pkgs.stdenv.hostPlatform.system}.omarchy.version;

  # See the plymouth-start override below. Upstream's own ExecStart, plus the
  # one flag, written once because it has to be identical in the initrd and in
  # the real root.
  plymouthdExec = [
    ""
    "${config.boot.plymouth.package}/sbin/plymouthd --mode=boot --pid-file=/run/plymouth/pid --attach-to-session --ignore-serial-consoles"
  ];

  variant = "-net";
  labelVariant = "_NET";
  # The installer, plus whatever the kernel command line asked for.
  #
  # The unit used to exec the installer with no arguments, so there was no way
  # to tell this image anything: the boot menu is suppressed (timeout 0, and
  # deliberately), and nothing read /proc/cmdline or scanned attached media. An
  # unattended install therefore meant building a bespoke image.
  #
  # The kernel command line is how qemu (-append), PXE and cloud metadata all
  # inject parameters, so an admin's fleet story becomes "netboot iso-net with
  # three arguments" and needs no new infrastructure. That is also where
  # unattended installs actually happen, which is why scanning attached media
  # for a labelled answers file is NOT here -- it can be added when somebody
  # with a physical fleet asks.
  #
  # With none of them present the behaviour is exactly what it was: an
  # interactive install.
  nixarchyInstallerLauncher = pkgs.writeShellScript "nixarchy-installer-launcher" ''
    set -u
    args=()

    # Word-split the command line and match whole parameters. A substring
    # match would find nixarchy.host= inside nixarchy.hostname= and hand the
    # installer half of somebody else's argument.
    for p in $(cat /proc/cmdline); do
      case "$p" in
        nixarchy.answers=*) args+=(--answers "''${p#nixarchy.answers=}") ;;
        nixarchy.from=*) args+=(--from "''${p#nixarchy.from=}") ;;
        nixarchy.host=*) args+=(--host "''${p#nixarchy.host=}") ;;
      esac
    done

    exec ${
      lib.getExe inputs.self.packages.${pkgs.stdenv.hostPlatform.system}.install
    } "''${args[@]+"''${args[@]}"}"
  '';

in
{
  imports = [ "${modulesPath}/installer/cd-dvd/installation-cd-minimal.nix" ];

  environment.systemPackages = [
    inputs.self.packages.${pkgs.stdenv.hostPlatform.system}.install
    pkgs.git
  ];

  # NetworkManager, for the same reason the installed machine uses it and for
  # anyone reaching for nmtui when the wireless does not come up on its own.
  #
  # `networking.wireless.enable` is deliberately NOT forced off here, and the
  # line that used to do it made every Wi-Fi install impossible:
  #
  #   device (wlp0s20f3): Couldn't initialize supplicant interface:
  #     Failed to D-Bus activate wpa_supplicant service
  #
  # repeating every thirteen seconds, forever, on a card whose driver was bound
  # and whose radio rfkill reported unblocked.
  #
  # NetworkManager does not avoid wpa_supplicant -- it DRIVES it. Its own
  # module says so and sets it up (networkmanager.nix:694-698):
  #
  #   # Enable wpa_supplicant but fully control it over DBus
  #   wireless.enable = true;
  #   wireless.autoDetectInterfaces = false;
  #   wireless.dbusControlled = true;
  #
  # A mkForce here overrode that and left NM with a backend it was told to use
  # and had no way to start. The conflict the old comment described -- a
  # STANDALONE supplicant grabbing interfaces behind NM's back -- is exactly
  # what those other two settings prevent, so the answer was already in the
  # module and forcing the switch off threw it away.
  #
  # The premise was also stale: nothing in nixpkgs' installation media enables
  # networking.wireless any more. installation-device.nix's only mention is the
  # login banner telling you to run nmtui.
  networking.networkmanager.enable = true;

  # Straight into the installer, with no boot menu -- upstream shows none and
  # a menu nobody reads is a menu that only ever delays the install.
  #
  # The splash, which #46 held up until the artwork was ours rather than
  # upstream's. It is now: every image omarchy.script draws is drawn by
  # pkgs/omarchy/nixarchy-logo.py and nixarchy-plymouth-chrome.py, and
  # checks.options asserts that for this image and the installed one both.
  #
  # boot.plymouth is set HERE, directly, which nothing else in the tree does.
  # programs.nixarchy.bootSplash is the option for this and it is out of
  # scope: nixosModules.nixarchy is deliberately not imported (see the header),
  # so there is no option to set. The two halves that option exists to keep
  # together -- theme and themePackages -- are therefore kept together here.
  #
  # themePackages is nixarchy-plymouth and not the omarchy package. They carry
  # the same share/plymouth/themes/omarchy; the difference is everything else.
  # nixpkgs' plymouth module puts themePackages into environment.etc, so the
  # named package joins the system closure whole -- 411.9 MiB of desktop on an
  # image that carries none, which iso-net cannot afford against the 2.00 GiB
  # GitHub refuses a release asset over. See the overlay entry in flake.nix.
  #
  # The theme is still called `omarchy`, because the DIRECTORY name is what
  # boot.plymouth.theme names and renaming it moves two options at once -- the
  # trap the bootSplash option's own comment documents. What it calls itself,
  # Name= in omarchy.plymouth, is nixarchy.
  boot = {
    loader.timeout = lib.mkForce 0;

    # No ZFS on this image (#1399): the kernel below is linuxPackages_latest,
    # which regularly outruns ZFS -- 7.3 marked zfs-kernel 2.4.4 broken and the
    # ISO stopped evaluating. nixpkgs ships the same trade as
    # installation-cd-minimal-new-kernel-no-zfs. Installs are btrfs; only
    # reaching an existing pool from the live image is lost.
    supportedFilesystems.zfs = lib.mkForce false;

    # This silences an evaluation warning by ANSWERING it, which is the only
    # reason it is here -- nixpkgs asks a question the installer profile
    # leaves unanswered, and an unanswered question that prints on every eval
    # trains everyone to read past warnings.
    #
    # mdadm: swraid.nix:62 warns that mdmon crashes with neither MAILADDR nor
    # PROGRAM set, and the installer profile enables swraid without setting
    # either. Answered rather than disabled: turning boot.swraid.enable off
    # would silence it too, but it would also take mdadm and the md/raid
    # initrd modules off the image, and a user with an existing array would
    # then have an installer that cannot see their disks.
    #
    # root is where NixOS mail goes with no MTA configured, and on a live
    # image that is the point -- this exists so mdmon starts, not so anyone
    # reads it.
    swraid.mdadmConf = "MAILADDR root";

    # OFF on the installer image, and this is a reversal worth reading.
    #
    # Two users could not boot v4.0.2-8 on real hardware -- a ThinkPad E15 --
    # while the same published file boots to a login prompt in a VM. The
    # difference between this image and the one NixOS ships is almost entirely
    # here: stock installation-cd-minimal runs NO plymouth, and its kernel is
    # the same 6.18.49 we use, so the kernel was never the variable.
    #
    # plymouth takes over KMS before the root filesystem exists. On a machine
    # with real graphics that hand-off is a thing that can hang, and when it
    # does there is nothing to see -- because nixpkgs' plymouth module adds
    # `splash` and `loglevel=0` to the command line, so not even a panic
    # prints. An installer image whose failures are invisible cannot be
    # debugged by the person holding the laptop, which is the only person who
    # can debug it.
    #
    # The branding cost is smaller than it looks. What a user sees during the
    # install -- the wordmark, the bar, the tips -- is the installer's own TUI
    # in installer/lib/ui.sh, not plymouth. plymouth only covered the few
    # seconds of kernel boot before that starts.
    #
    # The INSTALLED machine keeps its splash: programs.nixarchy.bootSplash is
    # untouched, and modules/nixos.nix still sets it. This is the boot medium
    # only.
    plymouth.enable = false;

    # `quiet` alone is not enough. It lowers the console log level but leaves
    # anything at KERN_ERR and above going straight to tty1, which is where the
    # installer draws -- an OOM kill or a disk warning paints itself across the
    # progress bar and the screen never recovers. loglevel=3 keeps the console
    # for the installer; everything still reaches the journal and dmesg.
    kernelParams = [
      # loglevel=4 is what stock installation-cd-minimal uses: warnings and
      # worse on the console, the rest in the journal. `quiet`, loglevel=3,
      # udev.log_level=3 and rd.systemd.show_status=false all used to be here,
      # to keep the console clean for the installer's own screen -- and the
      # cost of that was a boot failure nobody could see. Two users hit one on
      # real hardware and could report nothing but "it crashes".
      #
      # The installer still owns the screen once it starts: it clears it
      # (installer/lib/ui.sh) and systemd's status list has stopped by then.
      # What changes is that everything BEFORE that is now visible, which is
      # exactly the window where an unbootable machine fails.
      "loglevel=4"
      # Kernel messages to the serial line as well. tty0 is listed LAST and so
      # stays the primary console -- the installer keeps the screen, and a
      # headless run or a support request still has somewhere to read from.
      "console=ttyS0,115200"
      "console=tty0"
    ];
    # 4, as stock installation-cd-minimal has it. This is rendered as a
    # `loglevel=` parameter and appended AFTER the list above, so a 0 here
    # silently overrode the loglevel set there -- which is how an image meant
    # to be quiet became an image that could not report a panic.
    consoleLogLevel = 4;

    # The newest kernel nixpkgs has, and on the boot medium it matters more
    # than it does on the installed system.
    #
    # An installed machine that is a kernel behind is slow or missing a
    # feature. A LIVE IMAGE that is a kernel behind cannot be used at all:
    # there is no screen to read the error on and no network to fetch the fix
    # with. omacom/omarchy#6551 is that exact deadlock -- a Dell XPS 13 whose
    # Intel BE213 wifi had no driver on the install media, on a machine with
    # no other way to reach a network.
    #
    # Stock NixOS keeps its installer conservative because it installs servers
    # too. This image installs laptops bought this year, so it takes the other
    # side of that trade. modules/nixos.nix carries the same line and the
    # longer argument; this is set separately because the live image
    # deliberately does not import nixosModules.nixarchy.
    kernelPackages = pkgs.linuxPackages_latest;
  };

  # And the flag without which the splash above is dead weight.
  #
  # `console=ttyS0,115200` is on the command line four lines up, deliberately.
  # plymouthd sees a serial console there and falls back to text on every
  # display it has, including the framebuffer -- so the image boots to the
  # systemd status list it was already showing and nothing is drawn. That is
  # not a theory: booting the image's own kernel, initrd and store twice with
  # only that one parameter differing, the wordmark is on screen in one and
  # absent in the other. Nothing in the log says so; the screen is simply
  # wrong, which is how this would have shipped.
  #
  # --ignore-serial-consoles is plymouthd's own answer and costs the serial
  # line nothing: kernel messages still go there, because that is the kernel's
  # doing and not plymouth's.
  #
  # Both units, and the initrd one is the one that matters -- it is what draws
  # the splash before the root filesystem exists. Upstream's unit is shipped by
  # the package (systemd.packages), so this is an ExecStart override: the empty
  # string clears the packaged line rather than appending a second one.
  systemd.services.plymouth-start.serviceConfig.ExecStart = plymouthdExec;
  boot.initrd.systemd.services.plymouth-start.serviceConfig.ExecStart = plymouthdExec;

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
      # And after the splash has let go of the console.
      #
      # Plymouth owns the VT while it is drawing, and a terminal it owns
      # answers stty with 80x25 however large the screen is. The installer
      # measures once, at start, so starting beside plymouth rather than after
      # it puts the whole TUI back in the 80-column corner this file's
      # kernel-module list exists to get it out of -- measured on the built
      # image, not reasoned about. plymouth-quit-wait is already wanted by
      # multi-user.target, so this orders against a unit that runs anyway.
      "plymouth-quit-wait.service"
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
      TTYVTDisallocate = true;
      ExecStart = nixarchyInstallerLauncher;
      # Finished, aborted or crashed, do not respawn a TUI in a loop.
      Restart = "no";
    };
  };

  # image.baseName, not isoImage.isoName. The latter still evaluates -- it is a
  # renamed alias since 25.05 -- so setting it looks like it worked, right up
  # until the built file is called nixos-minimal-*.iso anyway. The filename is
  # derived from image.baseName.
  # mkForce because installation-cd-base sets this too, at the same priority.
  # Version, network suffix, then the commit identify the image and its source.
  #
  # The version comes from the omarchy package rather than a second binding,
  # so it cannot drift from what is actually on the image.
  image.baseName = lib.mkForce "nixarchy-${version}${variant}-${
    source.flake.shortRev or "dirty"
  }-x86_64";

  # A volume ID that overflows 32 characters or carries a character outside
  # [A-Z0-9_] is silently truncated or mangled by the ISO tooling, and the
  # failure shows up as a stick that will not boot -- long after the build
  # that caused it. Fail here instead.
  assertions = [
    {
      assertion = builtins.stringLength config.isoImage.volumeID <= 32;
      message = "isoImage.volumeID is ${toString (builtins.stringLength config.isoImage.volumeID)} characters, over the 32 the ISO 9660 label allows: ${config.isoImage.volumeID}";
    }
    {
      assertion = builtins.match "[A-Z0-9_]+" config.isoImage.volumeID != null;
      message = "isoImage.volumeID must be [A-Z0-9_] for the bootloader to find the root by label: ${config.isoImage.volumeID}";
    }
  ];

  isoImage = {
    # The label the bootloader finds the root by, so it is [A-Z0-9_] and at
    # most 32 characters -- asserted below rather than left to a truncation
    # nobody notices until a stick fails to boot.
    # #1398: edge's version is edge-YYYYMMDD-rev, too long and not [A-Z0-9_]; its label is the rev.
    volumeID =
      if lib.hasPrefix "edge-" version then
        "NIXARCHY_EDGE_${lib.toUpper (lib.last (lib.splitString "-" version))}${labelVariant}"
      else
        "NIXARCHY_${lib.toUpper (lib.replaceStrings [ "." "-" ] [ "_" "_" ] version)}${labelVariant}";
    makeEfiBootable = true;
    makeUsbBootable = true;

    # The desktop is fetched from the configured caches. The image measured
    # 1.63 GiB on 2026-09-14; checks.iso-budget enforces the 2 GiB release
    # asset limit.
  };

  system.extraDependencies = inputSources;

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
      "hyprland.cachix.org-1:a7pgxzMz7+chwVL3/pzj6jIBMioiJM7ypFP8PwtkuGc="
    ];
  };

  # A rescue reinstall is the flow that needs it: boot this ISO because the
  # disk will not, mount it at /mnt, and re-run
  #
  #   nixos-install --root /mnt --flake /mnt/etc/nixos#<host>
  #
  # /mnt/etc/nixos belongs to the installed user -- installer/install.sh
  # chowns it -- and nix opens the flake through libgit2, which refuses a
  # repository owned by anybody else and reports it as
  #
  #   error: opening Git repository "/mnt/etc/nixos": ... is not owned by
  #   current user (libgit2 error code = 7)
  #   error: could not find a flake.nix file
  #
  # The live image autologins as root and nothing here goes through sudo, so
  # there is no SUDO_UID for git's usual root exemption to match, and the
  # refusal stands. `git -c safe.directory=...` does not help: it fixes the
  # one git command it is passed to and never reaches nixos-install's own
  # libgit2. Only a real config file does. See modules/nixos.nix, which ships
  # the same entry to the installed machine for its own root contexts.
  environment.etc = {
    "gitconfig".text = ''
      [safe]
      	directory = /mnt/etc/nixos
    '';
    "nixarchy-iso-net".text = ''
      ${inputs.self.shortRev or "dirty"}
    '';
  };

  system.stateVersion = "25.05";
}
