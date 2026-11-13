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
  # Still accepted, deliberately unused, and that is the point of stage 1.
  #
  # Every caller passes it -- the generated host, flake.nix's reference
  # machines, tests/machine-name-free.nix -- and the interface is strict (no
  # `...`), so dropping it would break all three for no gain. What changed is
  # that nothing HERE may consume it: the moment this file uses the machine's
  # name, the name is back in the derivation, and two machines that differ
  # only by name have two different systems again. See the note on
  # networking.hostName below.
  #
  # deadnix: skip
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
  imports = [
    ./factory-reset.nix
    ./keyboard.nix
  ];

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
  #
  # NOT set here any more (#527). NixOS's own
  # nixos/modules/misc/nixpkgs-flake.nix already pins the registry, to
  # `nixpkgs.flake.source` -- the nixpkgs actually being evaluated -- which is
  # the same store path this line used to name whenever the machine follows
  # this flake's nixpkgs, and the RIGHT one when it does not.
  #
  # Evaluating against nixos-26.05 is what showed the difference:
  #
  #   error: The option `nix.registry.nixpkgs.to.path' has conflicting
  #   definition values:
  #   - In `nixos/modules/config/nix-flakes.nix':  <this flake's nixpkgs>
  #   - In `nixos/modules/misc/nixpkgs-flake.nix': <the machine's nixpkgs>
  #
  # A tie, because both sides are mkDefault -- so it could not be resolved by
  # lowering ours, and lowering it would have been wrong anyway: on a stable
  # machine, `nixpkgs#foo` pointed at this flake's UNSTABLE nixpkgs is exactly
  # the "binary built against a different glibc" the paragraph above exists to
  # prevent. The requirement stands; NixOS is now what meets it.
  nix = {
    settings = {
      flake-registry = "";

      # The free-space floor -- #583, and the half `programs.nh.clean` below
      # does NOT do.
      #
      # Two different problems, and conflating them is how a collection policy
      # eats the thing it was meant to protect:
      #
      #   nh.clean collects GENERATIONS (`--keep-since 14d --keep 5`), and
      #   generations are what rollback is made of. That is why it is
      #   conservative, and why `nix.gc.automatic` is NOT set here -- nixpkgs
      #   warns that the two together conflict, and checks.config-warnings
      #   fails on the warning rather than letting it print for weeks.
      #
      #   min-free/max-free collects GARBAGE -- paths nothing references --
      #   under space pressure rather than on a timer. That is exactly what
      #   `nixarchy try` leaves behind: a tried package has no GC root, so an
      #   application the user evaluated and rejected is pure garbage, and
      #   collecting it can never cost a rollback. The flake's input sources
      #   would be garbage too -- nothing references them -- and an offline
      #   machine could not evaluate itself after a collection (#701), so
      #   system.extraDependencies (beside system.name, below) keeps them.
      #
      # 3 GiB floor, 8 GiB target, sized for the smallest disk nixarchy supports,
      # 32 GiB (#708): a 2 GiB ESP and about 14 GiB of closure leave about 16 GiB
      # free on a fresh install, so neither number is reached from the start, and
      # a collection that does run has a target it can reach. The old 5/20 on a
      # small disk collected constantly toward a target it could never hit, and
      # Nix 2.34 crashed doing it mid-switch (see nix.package below). The floor
      # still leaves room for a switch to write a generation. checks.install
      # asserts a fresh install keeps at least max-free free.
      min-free = 3 * 1024 * 1024 * 1024;
      max-free = 8 * 1024 * 1024 * 1024;
    };

    # Deduplicate live store files on NixOS's low-priority, AC-only timer.
    optimise.automatic = true;

    # Nix 2.35 for its fix to NixOS/nix#15614: 2.34's automatic collection thread
    # outlived the store that started it and segfaulted during
    # `nixos-rebuild switch` (#701, #708). Unstable's nix is 2.35 now, stable's still 2.34.8;
    # drop this line once both channels' `pkgs.nix` are 2.35 or later.
    package = pkgs.nixVersions.nix_2_35;
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
    # No "docker" here. modules/nixos.nix adds it if and only if the rooted
    # daemon is enabled, which by default it is not; listing it outright left
    # the group on every installed machine even with Docker off -- a group
    # granting root to whatever installs a socket there later, which is the
    # exact outcome that conditional exists to prevent.
    extraGroups = [
      "wheel"
      "video"
      "input"
      "i2c"
    ];
    # The password is a FILE, not an evaluation input, and that is what makes
    # the account usable on a machine installed offline.
    #
    # It used to say "no password here -- the installer writes hashedPassword
    # into the generated configuration.nix". True, and it left the REFERENCE
    # account with no password of any kind: hashedPassword, hashedPasswordFile
    # and initialPassword all null. That is fine while every install evaluates
    # the user's own configuration.nix, and a LOCKOUT the moment one installs
    # the reference closure instead -- which is the whole point of #436.
    #
    # Same shape as the hostname below: the installer writes a file
    # (install.sh:1907, mode 0600, root-owned) and the system reads it at
    # runtime, so the value never enters a derivation and two machines with
    # different passwords are still the same closure.
    #
    # The generated configuration.nix sets the identical line for the user's
    # own account. Both may define it because they name the same file, and
    # hashedPasswordFile merges by equality.
    hashedPasswordFile = "/var/lib/nixarchy/password.hash";
  };

  # The machine's name, kept OUT of the derivation on purpose.
  #
  # Stage 1 of making an offline install build nothing. `networking.hostName`
  # reaches further than it looks: nixos/modules/system/boot/systemd/initrd.nix
  # line 597 writes it into the INITRD unconditionally
  # (`"/etc/hostname".text = config.networking.hostName`), so two machines
  # whose only difference is their name have two different initrds. A
  # different initrd is a build, and on an image with no network a build is
  # the stage0 source bootstrap -- which is the whole of #404.
  #
  # Empty is a supported value, not a trick: the option's type is
  # `strMatching "^$|..."` and its own documentation says "Leave it empty if
  # you want to obtain it from a DHCP server". /etc/hostname is then not
  # written at all (network-interfaces.nix:1812 gates it on `!= ""`), which is
  # what leaves the closure identical across machines.
  #
  # The name is not lost -- nixarchy-set-hostname below applies it on first
  # boot, from a file the installer writes. What changes is WHEN: a fact about
  # the running machine rather than an input to its derivation.
  #
  # system.name is pinned for the same reason and is NOT cosmetic: the
  # toplevel derivation is named "nixos-system-''${system.name}-''${label}"
  # (top-level.nix:60) and system.name defaults to the hostname, so leaving it
  # would put the machine's name in the store path of every system it ever
  # builds.
  networking.hostName = "";
  system = {
    name = "nixarchy";

    # Every input the host was given, transitively, in the system closure: the
    # sources `nix eval /etc/nixos` needs, kept safe from min-free's collection
    # (nix.settings above). `self` here is nixarchy, never the user's flake, so
    # editing /etc/nixos does not change the closure (#701).
    extraDependencies = inputs.self.lib.inputSources inputs;
  };

  # The name, applied once, from what the installer collected.
  #
  # A file rather than a Nix value, because the point of the exercise is that
  # this string never enters an evaluation. /etc/nixarchy/hostname is written
  # by the installer and read here; a machine without one keeps the default,
  # which is what an unattended or re-imaged machine should do.
  #
  # `ConditionPathExists` rather than a flag file: the unit is idempotent, and
  # hostnamectl on every boot costs nothing and survives someone deleting the
  # marker. Ordered before network-online so anything that cares about the
  # name sees it set.
  systemd.services.nixarchy-set-hostname = {
    description = "Apply the hostname chosen at install time";
    wantedBy = [ "multi-user.target" ];
    before = [ "network-pre.target" ];
    unitConfig.ConditionPathExists = "/etc/nixarchy/hostname";
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      name=$(tr -d '[:space:]' < /etc/nixarchy/hostname)
      [ -n "$name" ] || exit 0
      current=$(cat /proc/sys/kernel/hostname)
      [ "$current" = "$name" ] && exit 0
      echo "nixarchy: setting hostname to $name"
      ${pkgs.systemd}/bin/hostnamectl set-hostname "$name" \
        || echo "$name" > /proc/sys/kernel/hostname
    '';
  };

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

    # The boot menu is a list a human reads under time pressure, with a
    # keyboard and no scrollback. Uncapped it grows one entry per switch, and
    # `nh os switch` is the loop this machine lives in -- a month of ordinary
    # use buries "the one from before the thing I just broke" somewhere in the
    # middle of forty near-identical lines.
    #
    # This caps the MENU, not the generations: `nix-env --list-generations`
    # still shows everything the store holds, and `nixos-rebuild --rollback`
    # still reaches the one before this. Only the ESP entries are trimmed.
    # The ESP is 2G (installer/disk-config.nix), so this is about a list
    # somebody can read, not about space.
    systemd-boot.configurationLimit = 20;
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
