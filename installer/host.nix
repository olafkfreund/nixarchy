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

    # "Nixarchy wrote this machine." This file is imported only by a
    # hosts/<name>/default.nix the installer generated, so a configuration that
    # evaluates it is one nixarchy shaped -- which is what the armed commands
    # (nixarchy-config-repo and the post-boot nudge that offers it) need to know
    # before they commit, push or rewrite anything. Surfaced to them as
    # /etc/nixarchy/managed; see modules/nixos.nix for why this and not
    # .nixarchy-url, which `--from` copies onto machines nixarchy never touched.
    installerManaged = true;

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

  # ---------------------------------------------------------------------------
  # The factory baseline, restored (#172).
  #
  # installer/install.sh takes read-only @factory and @factory-home snapshots
  # at the end of every install. omarchy-system-factory-reset asks for them
  # back by writing a request file; this unit is what acts on it, and it is
  # the only thing on the machine that ever touches those snapshots.
  #
  # WHY A BOOT-TIME UNIT AND NOT THE SCRIPT ITSELF
  #
  # /home is mounted, and in use by the session the person is typing the
  # command into. Nothing in a running desktop can put a different /home
  # underneath itself, and the two approaches that look like they can are both
  # worse than this one:
  #
  #   Unmount /home and swap the subvolume. Requires killing the session that
  #   asked for the reset, from inside that session, and a failure halfway
  #   leaves a machine with no /home at all.
  #
  #   Copy files into the live /home. Not atomic, and not complete: to reach
  #   the factory state it would have to delete everything the baseline does
  #   not have, under open file handles, in a home directory being written to
  #   while it works.
  #
  # So nothing at all changes while the system is running. The script writes a
  # request and reboots; this runs on the next boot, after / is writable and
  # BEFORE /home is mounted, and either the whole reset happens or none of it
  # does.
  #
  # WHY HERE AND NOT IN modules/nixos.nix
  #
  # Same reason as services.snapper above: this file is imported only by
  # flakes the installer generated, so the unit exists on machines whose disk
  # nixarchy laid out and on no others. A machine where somebody imported
  # nixosModules.nixarchy into a configuration of their own has no @factory to
  # return to and no business carrying a unit that looks for one. That is the
  # structural half of the ownership gate; omarchy-system-factory-reset
  # carries the other half and refuses on /etc/nixarchy/managed.
  # ---------------------------------------------------------------------------
  systemd.services.nixarchy-factory-reset = {
    description = "Restore /home and /var/lib from the factory baseline";

    unitConfig = {
      # No implicit ordering against sysinit.target and basic.target: this has
      # to run earlier than either, and the default dependencies would place
      # it after both.
      DefaultDependencies = false;

      # The single predicate. With no request file systemd does not start the
      # unit at all, so a machine that never asks pays one stat() per boot and
      # the destructive code cannot be reached by accident -- not by a
      # `systemctl start`, which the condition also refuses.
      ConditionPathExists = "/var/lib/nixarchy/factory-reset.request";
    };

    # After the root filesystem is writable. systemd-remount-fs.service is
    # ordered Before=local-fs-pre.target, so this is after the rw remount
    # without having to name that unit.
    after = [ "local-fs-pre.target" ];

    # Before home.mount BY NAME, not merely before local-fs.target. Every
    # local mount unit is itself Before=local-fs.target and systemd leaves the
    # order among them unspecified, so "before the target" is not "before the
    # mount" -- and the whole design rests on /home not being mounted yet. A
    # restore that lands after the mount renames a subvolume the kernel is
    # already holding open: the rename succeeds, the running boot keeps
    # showing the old /home, and the user sees a reset that did nothing until
    # they reboot a second time.
    before = [
      "home.mount"
      "local-fs.target"
      "shutdown.target"
    ];
    conflicts = [ "shutdown.target" ];
    wantedBy = [ "local-fs.target" ];

    # Named explicitly rather than inherited: this runs before basic.target,
    # where the system path is not something to rely on.
    path = with pkgs; [
      btrfs-progs
      util-linux
      coreutils
    ];

    # A failure here does not fail the boot: local-fs.target only Wants this
    # unit, so a failed reset leaves the machine booting normally into the
    # state it was already in -- which is the correct outcome for a reset that
    # could not be performed.
    serviceConfig.Type = "oneshot";

    script = ''
      set -euo pipefail

      request=/var/lib/nixarchy/factory-reset.request
      stamp=$(date +%Y%m%d-%H%M%S)

      # Removed FIRST, before anything else can fail. A request that survived a
      # failed attempt would be retried on every subsequent boot, and a reset
      # that retries forever turns a machine that merely could not be reset
      # into one that cannot finish booting.
      rm -f "$request"

      # findmnt reports a btrfs source as DEVICE[/subvol]; the bracket is the
      # subvolume, not part of the device path.
      device=$(findmnt -no SOURCE / | sed 's/\[.*\]//')

      top=$(mktemp -d)
      cleanup() {
        umount "$top" 2>/dev/null || true
        rmdir "$top" 2>/dev/null || true
      }
      trap cleanup EXIT

      # The baseline is not mounted by the running system -- see the comment on
      # take_factory_snapshot in installer/install.sh -- so the top level is
      # mounted here for the length of this unit and unmounted again.
      mount -o subvol=/ "$device" "$top"

      for sub in @factory @factory-home; do
        if [ ! -d "$top/$sub" ]; then
          echo "no $sub on this filesystem: nothing has been changed." >&2
          exit 1
        fi
      done

      # ---- /var/lib -----------------------------------------------------
      #
      # Copied, not swapped. /var/lib is a plain directory inside `@` rather
      # than a subvolume of its own, and rename(2) between two btrfs
      # subvolumes is EXDEV -- there is no swap available at any price.
      # --reflink makes the copy share extents with the baseline, so it costs
      # about what the snapshot did.
      #
      # Copied aside and then moved into place in two renames, rather than
      # written over /var/lib directly: a copy that dies halfway leaves a
      # /var/lib that is neither the machine's nor the factory's, with no way
      # afterwards to tell which files are which.
      #
      # /etc/nixos is NOT touched, here or anywhere in this unit. It is on the
      # same subvolume and it is the user's configuration repository: a reset
      # that ate their commits would destroy the one thing that makes a
      # reinstall recoverable.
      rm -rf /var/lib.factory-new
      cp -a --reflink=auto "$top/@factory/var/lib" /var/lib.factory-new
      mv /var/lib "/var/lib.before-reset-$stamp"
      mv /var/lib.factory-new /var/lib

      # ---- /home --------------------------------------------------------
      #
      # A writable clone of the read-only baseline, then two renames at the
      # top level. Instant, and atomic in the only sense that matters: at no
      # point is there no @home.
      #
      # The old @home is renamed, never deleted. "Factory reset" here means
      # the data is no longer in /home, not that it has been shredded --
      # omarchy-system-factory-reset says exactly that before it asks, twice,
      # and prints the command that removes the leftover. Destroying a
      # person's entire home directory with no way back is not something to do
      # as a side effect of a boot, and the machine being sold is the case the
      # refusal text already answers with "wipe the disk".
      btrfs subvolume snapshot "$top/@factory-home" "$top/@home-factory-$stamp"
      mv "$top/@home" "$top/@home-before-reset-$stamp"
      mv "$top/@home-factory-$stamp" "$top/@home"

      # The receipt, written into the /var/lib that was just restored so that
      # it survives -- and so that a person watching their machine come back
      # empty has something to read that says what happened and where their
      # files went.
      mkdir -p /var/lib/nixarchy
      cat >/var/lib/nixarchy/factory-reset.done <<EOF
      This machine was factory-reset on $stamp.

      /home and /var/lib were restored from the snapshots the installer took
      before anyone logged in. What was there instead is still on the disk:

        the home directory   @home-before-reset-$stamp, a btrfs subvolume at
                             the top level of this filesystem
        the service state    /var/lib.before-reset-$stamp

      Neither is mounted. To read the old home directory:

        sudo mount -o subvol=/ $device /mnt
        ls /mnt/@home-before-reset-$stamp

      To delete it once you are sure:

        sudo btrfs subvolume delete /mnt/@home-before-reset-$stamp
        sudo rm -rf /var/lib.before-reset-$stamp

      /etc/nixos was not touched. The system half resets by rebuilding from
      the first commit in that repository; see omarchy-system-factory-reset.
      EOF

      echo "factory reset complete: /home and /var/lib are as the installer left them."
    '';
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
  #
  # btrfs-progs is stated rather than inherited. NixOS puts it on the path
  # anyway once btrfs is in boot.supportedFilesystems, which disko's layout
  # makes true -- but that is a fact about the filesystem module, not a promise
  # to this file, and omarchy-system-factory-reset asks
  # `btrfs subvolume list -r` whether this machine has a factory baseline. With
  # no btrfs the question answers "no" on a machine that has one, and the user
  # is told there is no baseline in the same words a pre-#172 machine is told
  # it truthfully. A refusal that cannot be told apart from an honest one is
  # the failure mode this whole feature was written to avoid.
  environment.systemPackages = with pkgs; [
    git
    btrfs-progs
  ];

  system.stateVersion = "25.05";
}
