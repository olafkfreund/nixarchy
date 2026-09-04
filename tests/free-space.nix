{ inputs, pkgs }:
# Does a free-space install leave the other operating system alone?
#
# checks.install asks whether the installer's output boots. This asks the
# question that costs somebody their data if the answer is wrong: nixarchy is
# installed into free space on a disk that already carries partitions, and
# those partitions have to come out the other side BYTE-IDENTICAL. Not
# "still present", not "still mountable" -- identical, hashed at the block
# device.
#
# The fixture is shaped like the machine this mode exists for. /dev/vdb gets:
#
#   p1  a 128 MiB EFI system partition with EFI/Microsoft/Boot/bootmgfw.efi
#       in it. It is a real, usable, correctly-typed ESP -- which is exactly
#       what makes it worth having here. A free-space install must NOT adopt
#       it, and the assertion that it did not is that the whole partition
#       hashes the same afterwards: writing a bootloader into it, or even
#       mounting it read-write, would change the bytes.
#
#   p2  256 MiB of random data with a Microsoft-basic-data type code, standing
#       in for the Windows volume. Raw rather than a filesystem on purpose:
#       a filesystem's own metadata drifts on mount, and "byte-identical" has
#       to mean what it says.
#
#   ~19 GiB of free space after them, which is where nixarchy goes.
#
# What would make this check pass on broken code, and therefore what was
# verified by hand before trusting it: the partition table is compared entry
# by entry (sgdisk -i, which prints type GUID, unique GUID, first and last
# sector, attributes and name) as well as by content hash. Restoring disko's
# positional numbering in installer/install.sh -- `--new=1:` with the
# --change-name fallback disko's gpt type uses -- fails this check on p1's
# entry, which is the failure mode #47 is about.
#
# encrypt=no, for the same reason checks.install uses it: an encrypted target
# stops at a passphrase prompt the driver would have to type through on a
# screen it cannot reliably read. Which layout LUKS produces is a different
# question and this is not the check for it.
let
  # hyprland does not follow nixpkgs, so its inputs are separate locked entries
  # and are needed to evaluate the generated flake. Collected rather than
  # listed: enumerating aquamarine, hyprlang, hyprutils and the rest by hand is
  # a list that goes stale on the next bump and fails as a network fetch inside
  # a VM that has no network.
  collectInputs =
    flake:
    [ flake.outPath ] ++ builtins.concatMap collectInputs (builtins.attrValues (flake.inputs or { }));

  inputPaths = pkgs.lib.unique (builtins.concatMap collectInputs (builtins.attrValues inputs));

  reference = inputs.self.nixosConfigurations.reference.config.system.build;

  # A fixed hash, not a plaintext password. `password=` makes the installer
  # call mkpasswd, which salts randomly -- so the installed toplevel would be a
  # different store path on every run and could never match anything seeded
  # here. This is "omarchy", on a disposable VM.
  #
  # Generated, never typed. The value that stood here before was written out by
  # hand and was not the hash of anything: the install completed, the machine
  # booted, and the greeter rejected the only password the test knew, which
  # reads as a broken desktop rather than a broken fixture. Regenerate with
  #
  #   mkpasswd -m sha-512 -R 100000 -S nixarchytestsalt omarchy
  #
  # and check it round-trips before trusting it.
  passwordHash = "$6$rounds=100000$nixarchytestsalt$zoz9HmOtqvELBidMdICVEOuvNl5LQCo.yhxsVpM6bgkeTdCG9D91zOaGX9Bu/YsQTlWLwuQF1SrOL0DY8Bu/V/";

  # The NixOS test backdoor, as a module the generated flake can import.
  #
  # An installed machine has no reason to carry it, and the installer is right
  # not to write it -- but without it the driver cannot run a single command on
  # the target: wait_for_unit, succeed and the rest all talk to a root shell on
  # /dev/hvc0 that only this module provides. The alternative is to type every
  # assertion into a getty and scrape the console for it, which is a worse test
  # of the same things.
  #
  # So the installer runs untouched and writes what it would write; then this
  # is added and nixos-install is run a second time, which is a copy rather
  # than a build because the instrumented system is seeded too. What boots is
  # the disk the installer produced, plus a serial shell.
  #
  # modulesPath, not an absolute store path: the generated flake evaluates in
  # pure mode, where a path outside its own tree is an error, and modulesPath
  # points into the nixpkgs the flake already has.
  instrumentation = {
    imports = [ "${inputs.nixpkgs}/nixos/modules/testing/test-instrumentation.nix" ];
  };

  # What nixos-generate-config writes on the target, as a module.
  #
  # This is the file the install generates INSIDE the VM, and #12 called it
  # unknowable from outside -- which is why this check could not pass. It is
  # not unknowable, it is just late: the machine is qemu, its devices are the
  # ones the test driver gives it, and the output is the same every run. What
  # is genuinely variable is one line, the host CPU's KVM module, so both
  # values are seeded and the install picks whichever it wrote.
  #
  # The file's TEXT does not have to match. It is imported as Nix source, not
  # copied to the store, so only the configuration it produces matters -- and
  # that is what this reproduces. If qemu's devices ever change, the install
  # falls back to building the difference, finds no network, and fails here
  # with the derivation it wanted; update this to match.
  hardwareConfig = cpuModule: {
    imports = [ "${inputs.nixpkgs}/nixos/modules/profiles/qemu-guest.nix" ];
    boot = {
      initrd.availableKernelModules = [
        "virtio_pci"
        "uhci_hcd"
        "ehci_pci"
        "ahci"
        "sr_mod"
        "virtio_blk"
      ];
      initrd.kernelModules = [ ];
      kernelModules = [ cpuModule ];
      extraModulePackages = [ ];
    };
    nixpkgs.hostPlatform = pkgs.lib.mkDefault pkgs.stdenv.hostPlatform.system;
  };

  # And the pin installer/install.sh adds underneath it.
  #
  # The installer forces both initrd lists to what the medium carries, so the
  # machine can reuse the initrd already there instead of building a
  # near-identical one -- see reuse_baked_initrd. That means the system this
  # test seeds has to carry the same force, or the installed system differs
  # from the seeded one by exactly an initrd and the install has to build it
  # with no network. Which is not a subtle failure: it is the source bootstrap,
  # and it ends by trying to download a patch from salsa.debian.org.
  #
  # reference-unencrypted, because this test installs with encrypt=no and LUKS
  # adds a dozen crypto modules to the other one.
  initrdPin =
    let
      ref = inputs.self.nixosConfigurations.reference-unencrypted.config;
    in
    {
      boot.initrd.availableKernelModules = pkgs.lib.mkForce ref.boot.initrd.availableKernelModules;
      boot.initrd.kernelModules = pkgs.lib.mkForce ref.boot.initrd.kernelModules;
    };

  # The exact disko script the generated flake will evaluate to. The reference
  # host's is for /dev/vda -- its placeholder device -- and this test installs
  # to /dev/vdb, so they are different derivations and the VM would have to
  # build one with no network. Seeding it here is what the ISO does for the
  # whole closure in #15; the test meets the same requirement early.
  targetSystemFor =
    {
      cpuModule,
      instrumented ? false,
    }:
    (inputs.nixpkgs.lib.nixosSystem {
      # Not `inherit (pkgs) system`: pkgs.system is deprecated in favour of
      # stdenv.hostPlatform.system, and nixpkgs warns on every evaluation of
      # this check. Written out rather than inherited because the inherit form
      # is what hid it -- a grep for `pkgs.system` does not find it.
      system = pkgs.stdenv.hostPlatform.system;
      specialArgs = { inherit inputs; };
      modules = [
        inputs.self.nixosModules.nixarchy
        inputs.home-manager.nixosModules.home-manager
        inputs.disko.nixosModules.disko

        # The machine, as ONE module whose imports are the three files
        # installer/template/host/default.nix imports -- not as three entries
        # in this list.
        #
        # The shape is load-bearing and was not, before the hosts/ layout. A
        # module's `imports` and a nixosSystem's `modules` merge in different
        # orders, so listing these flat gives the same packages in a different
        # environment.systemPackages ORDER; system-path hashes that order into
        # chosenOutputs, so it is a different derivation, so the toplevel is,
        # and the install has to build what it can no longer copy -- offline,
        # which means stdenv, which means 459 derivations from hex0-seed and a
        # fetch of a Debian patch that never arrives.
        #
        # So this mirrors hosts/<name>/default.nix, and the block below mirrors
        # the configuration.nix that sits beside it. Keep both in step with
        # installer/template/host/ -- a mismatch shows up as "cannot build",
        # which is a clear enough signal.
        {
          imports = [
            (import ../installer/host.nix {
              hostname = "installed";
              username = "omarchy";
            })
            (import ../installer/disk-config.nix {
              # The whole point. mode = "free" addresses two partitions by
              # partlabel and declares no partition table at all, so this is a
              # different toplevel from the whole-disk reference and has to be
              # seeded separately or the install builds it with no network.
              mode = "free";
              device = "/dev/vdb";
              encrypt = false;
            })
            {
              time.timeZone = "UTC";
              console.keyMap = "us";
              nixpkgs.config.allowUnfree = true;
              services.displayManager.autoLogin = {
                enable = false;
                user = "omarchy";
              };
              users.users.omarchy.hashedPassword = passwordHash;
            }
          ];
        }
        (hardwareConfig cpuModule)
        initrdPin
      ]
      ++ pkgs.lib.optional instrumented instrumentation;
    }).config.system.build;

  # Every system the target might end up being: two CPU vendors, with and
  # without the backdoor. They share all but a handful of derivations, so the
  # four cost barely more than one, and between them they remove the only two
  # variables this test cannot control.
  targetSystems =
    pkgs.lib.concatMap
      (cpuModule: [
        (targetSystemFor { inherit cpuModule; })
        (targetSystemFor {
          inherit cpuModule;
          instrumented = true;
        })
      ])
      [
        "kvm-amd"
        "kvm-intel"
      ];

  # The same helper nixpkgs' own boot tests use to pick a qemu binary, rather
  # than hardcoding qemu-system-x86_64 and losing KVM.
  qemuCommon = import "${inputs.nixpkgs}/nixos/lib/qemu-common.nix" {
    inherit (pkgs) lib stdenv;
  };

  # The code drive only. The VARIABLE drive is added by the test script, as a
  # WRITABLE COPY, and that is not a detail.
  #
  # checks.install attaches ${pkgs.OVMF.variables} with readonly=on, which is
  # fine when there is one ESP on the disk and wrong here. A firmware with no
  # writable variable store falls back to keeping its variables in a file
  # called NvVars in the root of the first FAT partition it finds -- and the
  # first ESP on this disk is the fixture's, standing in for Windows'. The
  # post-boot byte-identity assertion caught it: /dev/vdb1 came back changed,
  # and mounting it showed bootmgfw.efi untouched beside a brand new NvVars,
  # written by OVMF and not by anything nixarchy installed.
  #
  # A machine with working NVRAM is also the honest fixture, so the fix is to
  # give it one rather than to weaken the assertion. Worth knowing anyway: on
  # a real machine whose firmware cannot write its own variables, the firmware
  # will do this to somebody's ESP no matter what any installer does.
  # Without the disk, which is added at runtime: the driver starts qemu with
  # cwd set to the TARGET's state directory, so a path relative to the test
  # root -- vm-state-installer/empty0.qcow2, where the installer's second disk
  # actually is -- resolves inside vm-state-target/ instead, and qemu exits
  # before it says anything. The failure is a bare ConnectionResetError on the
  # QMP socket, which names nothing.
  targetCommand = pkgs.lib.concatStringsSep " " [
    (qemuCommon.qemuBinary pkgs.qemu_test)
    "-cpu max -m 4096 -smp 4"
    "-drive if=pflash,format=raw,unit=0,readonly=on,file=${pkgs.OVMF.firmware}"
  ];

  # Copied at runtime, because a store path is read-only and a pflash drive
  # qemu can write to cannot be one.
  ovmfVariables = "${pkgs.OVMF.variables}";
in
pkgs.testers.runNixOSTest {
  name = "nixarchy-free-space";

  # The driver has to lose the race to the job, or a hang is invisible.
  #
  # runNixOSTest's globalTimeout defaults to one hour, and this check has been
  # finishing in 37 to 59 minutes -- a budget sized to the median of something
  # that legitimately takes most of an hour. On 2026-09-03 three install jobs
  # overlapped on the one self-hosted machine, this one took 63 minutes against
  # a tree that had passed the same check at 57 minutes an hour earlier, and
  # the driver killed it: `timeout reached; test terminating`, exit 143. No
  # regression, no headroom.
  #
  # 85 minutes, deliberately UNDER install-check.yml's `timeout-minutes: 90`.
  # Which of the two fires first decides what a hang looks like: the driver
  # ending it is a failure, with a log and a reported check, while GitHub
  # ending it is recorded as `cancelled` -- which #200 established is the state
  # nothing reports on and nobody sees. If that job timeout ever moves, this
  # number moves with it and stays below.
  globalTimeout = 85 * 60;

  nodes.installer =
    { ... }:
    {
      imports = [
        inputs.self.nixosModules.nixarchy
        inputs.home-manager.nixosModules.home-manager
      ];

      environment.systemPackages = [
        inputs.self.packages.${pkgs.stdenv.hostPlatform.system}.install
        pkgs.git
        # The fixture's own tools. The installer carries these too, but the
        # test builds the "existing OS" with them before the installer runs,
        # and a fixture that depends on the thing under test having the right
        # runtime inputs would hide a missing one.
        pkgs.gptfdisk
        pkgs.dosfstools
      ];

      nix.settings = {
        experimental-features = [
          "nix-command"
          "flakes"
        ];
        # There is no network. Saying so explicitly turns "tried to fetch" into
        # a clear failure rather than a timeout that reads like flakiness.
        substituters = pkgs.lib.mkForce [ ];

        # nixos-install builds with --store /mnt and offers the host store as
        # a substituter (auto?trusted=1). Every path this test seeded was put
        # there by the test itself and carries no signature, so with
        # require-sigs on, /mnt refuses all of them -- "cannot add path ...
        # because it lacks a signature by a trusted key" -- and falls back to
        # building what it cannot copy. That is not a handful of derivations:
        # building anything at all offline means building stdenv, so the whole
        # source bootstrap from stage0-posix appears and the install dies
        # fetching bash's tarball.
        #
        # The store is the test's own output, on a medium the test built. An
        # offline ISO is in exactly the same position -- its closure is baked
        # in unsigned -- so #15 and #16 will need this too.
        require-sigs = false;
      };

      environment.etc = {
        # The answers the wizard would have collected. device is the second
        # disk, which the test script partitions first; /dev/vda is this
        # node's own root. disk_mode=free is the whole subject of this check,
        # and install.sh refuses it -- rather than quietly falling back to
        # erasing the disk -- if the disk cannot take one.
        "nixarchy/answers".text = ''
          device=/dev/vdb
          disk_mode=free
          encrypt=no
          hostname=installed
          username=omarchy
          password_hash=${passwordHash}
          timezone=UTC
          keymap=us
        '';

        # Copied into the generated flake after the install; see the note on
        # `instrumentation`. modulesPath rather than an absolute store path,
        # because the flake it joins evaluates in pure mode.
        "nixarchy/test-instrumentation.nix".text = ''
          { modulesPath, ... }:
          {
            imports = [ "''${modulesPath}/testing/test-instrumentation.nix" ];
          }
        '';
      };

      # Everything the install will copy or evaluate, already present: the test
      # meets the offline reality that the ISO phase will have to solve for
      # real. If something is missing it surfaces as a fetch attempt with no
      # network, which is a clearer failure than a silent download would be.
      system.extraDependencies = [
        reference.toplevel
        reference.diskoScript
        (targetSystemFor { cpuModule = "kvm-amd"; }).diskoScript
        # A build environment, for the little that still has to be built here
        # rather than copied: disko's script runs on this machine, not the
        # target. It is deliberately not the answer to "the install wants to
        # build something" -- when that happens the seeded system has drifted
        # from the installed one, and the fix is to make them match again, not
        # to widen this list until the difference can be compiled.
        #
        # system.includeBuildDependencies would cover far more and is not
        # usable: on a desktop this size the evaluation alone passed 3.4 GB
        # resident with no end in sight.
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
        pkgs.python3
        pkgs.jq
      ]
      ++ map (t: t.toplevel) targetSystems

      # And the parts the few per-machine derivations are built FROM.
      #
      # The installed machine's hostname is not the reference's, and a systemd
      # initrd embeds the hostname -- initrd-hostname, initrd-group,
      # initrd-release. So an initrd has to be built here no matter what is
      # seeded, and building it needs kmod's dev output, and the toplevel's
      # own wrapper check needs libcap. Neither is in any runtime closure, so
      # neither arrives with the systems above, and nix does not degrade over
      # a missing build input -- it builds it, needs a compiler, has none, and
      # walks back to the source bootstrap. The install then ends several
      # minutes later trying to fetch a patch from salsa.debian.org.
      #
      # inputDerivation is nixpkgs' own "realise everything this is built
      # from", which is exactly the question, and it keeps working when the
      # answer changes. installer/cd.nix carries the same list for the ISO.
      ++ map (t: t.toplevel.inputDerivation) targetSystems
      ++ map (t: t.initialRamdisk.inputDerivation) targetSystems
      ++ map (t: t.etc.inputDerivation) targetSystems
      ++ [
        pkgs.kmod
        pkgs.kmod.dev
        pkgs.libcap
        pkgs.nukeReferences
      ]
      ++ inputPaths;

      virtualisation = {
        memorySize = 6144;
        cores = 4;
        # The installer refuses to run where /sys/firmware/efi does not exist,
        # and is right to -- the layout is an ESP with systemd-boot and there
        # is no BIOS path. A default test node boots through -kernel with no
        # firmware at all, so the node has to be given some.
        useEFIBoot = true;
        # The target, which appears as /dev/vdb. Bigger than checks.install's
        # because it has to hold the fixture's two partitions AND leave more
        # than the 32 GiB free region install.sh insists on -- below that the
        # free-space mode is not offered at all, which would turn this check
        # into a whole-disk install that passes for the wrong reason.
        emptyDiskImages = [ 36864 ];
        # nixos-install copies the whole closure into the target, and the
        # default 1 GB store overlay is nowhere near enough.
        diskSize = 32768;
      };
    };

  testScript = ''
    installer.wait_for_unit("multi-user.target")

    # ---- build the machine we are not allowed to break --------------------
    #
    # Written here rather than as a prepared image because the assertion is
    # about bytes, and bytes that this script wrote are bytes nothing else
    # could have put there.
    installer.succeed("sgdisk --clear /dev/vdb")
    installer.succeed(
        "sgdisk --new=1:2048:+128M --typecode=1:EF00"
        " --change-name=1:'EFI system partition' /dev/vdb")
    installer.succeed(
        "sgdisk --new=2:0:+256M --typecode=2:0700"
        " --change-name=2:'Basic data partition' /dev/vdb")
    installer.succeed("partx -u /dev/vdb || partx -a /dev/vdb || true")
    installer.succeed("udevadm settle")

    # A real ESP with a real Windows bootloader path in it. mkfs, mount, write,
    # unmount -- and then never touch it again, so that the hash taken in a
    # moment is the hash of a filesystem nobody has opened since.
    installer.succeed("mkfs.vfat -n SYSTEM /dev/vdb1")
    installer.succeed("mkdir -p /win && mount /dev/vdb1 /win")
    installer.succeed("mkdir -p /win/EFI/Microsoft/Boot")
    installer.succeed("head -c 65536 /dev/urandom > /win/EFI/Microsoft/Boot/bootmgfw.efi")
    installer.succeed("umount /win")

    # And the volume itself: raw, so "byte-identical" means byte-identical and
    # not "the filesystem still mounts".
    installer.succeed("dd if=/dev/urandom of=/dev/vdb2 bs=1M count=256 conv=fsync")

    installer.succeed("udevadm settle")
    before_hashes = installer.succeed("sha256sum /dev/vdb1 /dev/vdb2")
    before_p1 = installer.succeed("sgdisk -i 1 /dev/vdb")
    before_p2 = installer.succeed("sgdisk -i 2 /dev/vdb")
    print("the disk this install must not break:")
    print(installer.succeed("sgdisk -p /dev/vdb"))
    print(before_hashes)

    # ---- install into what is left ----------------------------------------
    import os
    import re
    import time
    import subprocess
    started = time.time()
    # execute, not succeed, and then print the log whatever happened: the
    # dashboard keeps the screen and sends every phase to a file, so a failed
    # install prints nothing a test can read. Same reasoning as checks.install,
    # and the same refusal to use `bash -x` -- a passphrase goes through here.
    rc, out = installer.execute(
        "nixarchy-install --answers /etc/nixarchy/answers 2>&1", timeout=1800)
    print(f"driver_seconds={int(time.time() - started)}")
    print(out)
    print("=============== /var/log/nixarchy-install.log ===============")
    installer_log = installer.execute("cat /var/log/nixarchy-install.log 2>&1")[1]
    print(installer_log)
    print("============================================================")

    # Name the cause before the ESP assertion gets to misreport it.
    #
    # This machine has no network, on purpose. So when a path the install needs
    # is neither in this store nor substitutable, nix falls back to building
    # it, a build fetches its source, the fetch fails, and the failure climbs:
    # a source tarball -> its package -> system-path -> the toplevel -> nothing
    # installed -> no ESP. The assertion that fires is `test -d /mnt/boot/EFI`,
    # which is five frames above the only line that says what happened and
    # sends the reader to disko.
    #
    # It cost two people an evening. The cause was a nixpkgs mass-rebuild that
    # had not reached cache.nixos.org yet: the same commit failed at 23:06 and
    # passed at 23:43 on the same runner, because the window closed. Nothing
    # about the machine, the disk or the change under test mattered, and every
    # theory that blamed one of those was wrong.
    #
    # So: if the log says a download failed, say that, and say it here.
    if rc != 0:
        wanted = sorted(set(re.findall(r"unable to download '([^']+)'", installer_log)))
        # Substituter metadata is not evidence of this: a nix-cache-info that
        # cannot be reached is what a no-network VM is supposed to look like,
        # and install.sh only configures those caches when the ISO marker is
        # absent. Source fetches are the ones that mean a path was missing.
        sources = [u for u in wanted if not u.endswith("/nix-cache-info")]
        if sources:
            listed = "\n  ".join(sources[:5])
            more = f"\n  ... and {len(sources) - 5} more" if len(sources) > 5 else ""
            raise AssertionError(
                "the install had to BUILD something, and this machine has no "
                "network to fetch its source with. That is a closure that was "
                "not substitutable when the runner realised it -- usually a "
                "nixpkgs rebuild that has not reached cache.nixos.org yet, "
                "which clears on its own in under an hour.\n\n"
                f"  {listed}{more}\n\n"
                "It is very probably not the change under test. Check whether "
                "these are substitutable now:\n"
                "  nix path-info --store https://cache.nixos.org <path>\n"
                "and if they are, re-run. If they are not, wait rather than "
                "widening system.extraDependencies -- see the note there about "
                "seeded systems drifting from installed ones.")

    assert rc == 0, f"nixarchy-install exited {rc}; the log above says why"

    print("the disk afterwards:")
    print(installer.succeed("sgdisk -p /dev/vdb"))

    # ---- THE ASSERTION ----------------------------------------------------
    #
    # Content first, because it is the one that matters. sha256sum reads the
    # block devices, not a mounted view of them, so a single changed byte
    # anywhere in either partition fails this -- including a filesystem's own
    # "last mounted" bookkeeping, which is what makes it also the proof that
    # the existing ESP was never adopted.
    after_hashes = installer.succeed("sha256sum /dev/vdb1 /dev/vdb2")
    assert after_hashes == before_hashes, (
        "a partition this install did not create has changed.\n"
        f"before:\n{before_hashes}\nafter:\n{after_hashes}")

    # And the table entries, which a content hash cannot see: a partition
    # relabelled or retyped in place holds the same bytes. This is the exact
    # damage disko's gpt type does when its positional partition 1 collides
    # with an existing one -- see installer/disk-config.nix, mode = "free".
    after_p1 = installer.succeed("sgdisk -i 1 /dev/vdb")
    after_p2 = installer.succeed("sgdisk -i 2 /dev/vdb")
    assert after_p1 == before_p1, (
        f"partition 1's table entry changed.\nbefore:\n{before_p1}\nafter:\n{after_p1}")
    assert after_p2 == before_p2, (
        f"partition 2's table entry changed.\nbefore:\n{before_p2}\nafter:\n{after_p2}")
    print("both pre-existing partitions are byte-identical, entry and content")

    # ---- and nixarchy is where it should be -------------------------------
    #
    # The other half of the claim: the partitions survived AND the install
    # actually happened. Either one alone passes for the wrong reason -- an
    # installer that did nothing at all would sail through the block above.
    table = installer.succeed("sgdisk -p /dev/vdb")
    assert "nixarchy-esp" in table and "nixarchy-root" in table, table
    assert installer.succeed(
        "findmnt -no SOURCE /mnt/boot").strip() == "/dev/vdb3", (
        "/mnt/boot is not the ESP this install created")
    assert installer.succeed("findmnt -no SOURCE /mnt").strip().startswith("/dev/vdb4"), (
        "/mnt is not the root this install created")
    installer.succeed("test -f /mnt/boot/EFI/BOOT/BOOTX64.EFI")
    installer.succeed("test -d /mnt/boot/EFI/systemd")
    # The existing ESP is still Windows'. Nothing of ours is in it -- checked
    # as well as hashed, because a reader should not have to reason from a
    # hash to see what the rule is.
    installer.succeed("mkdir -p /win && mount -o ro /dev/vdb1 /win")
    installer.succeed("test -f /win/EFI/Microsoft/Boot/bootmgfw.efi")
    installer.fail("test -e /win/EFI/systemd")
    installer.fail("test -e /win/loader")
    installer.succeed("umount /win")
    print("nixarchy is on its own new ESP, and Windows' is untouched")

    # ---- no gpt type in the generated layout ------------------------------
    #
    # #47's other done-when, asserted rather than reviewed: if a `gpt` block
    # ever appears in the free-space layout, the path that relabels somebody
    # else's partition has been reintroduced. Evaluated from the file the
    # installer actually wrote into the user's flake, with the arguments the
    # generated host passes it.
    layout = installer.succeed(
        "nix --extra-experimental-features 'nix-command flakes' eval --impure --raw"
        " --expr 'builtins.toJSON (import /mnt/etc/nixos/disk-config.nix"
        " { mode = \"free\"; device = \"/dev/vdb\"; encrypt = false; })'")
    assert '"gpt"' not in layout, f"the free-space layout declares a gpt type: {layout}"
    assert "by-partlabel/nixarchy-root" in layout, layout
    print("the generated layout declares no partition table")
    installer.succeed(
        "grep -q 'mode = \"free\"' /mnt/etc/nixos/hosts/installed/default.nix")

    # ---- make the result observable ---------------------------------------
    # Identical to checks.install, and for the same reason: an installed
    # machine has no serial root shell and the driver cannot assert anything on
    # one without it. See tests/install.nix's note on `instrumentation`.
    installer.succeed(
        "cp /etc/nixarchy/test-instrumentation.nix /mnt/etc/nixos/hosts/installed/")
    installer.succeed(
        "sed -i 's|./hardware-configuration.nix|./hardware-configuration.nix\\n"
        "    ./test-instrumentation.nix|'"
        " /mnt/etc/nixos/hosts/installed/configuration.nix")
    installer.succeed("git -C /mnt/etc/nixos add -A")
    print(installer.succeed(
        "nixos-install --root /mnt --flake /mnt/etc/nixos#installed"
        " --no-root-password"
        " --option extra-experimental-features 'nix-command flakes'"
        " --option always-allow-substitutes true 2>&1 | tail -20",
        timeout=1800))

    installer.shutdown()

    # ---- boot it ----------------------------------------------------------
    #
    # On the bootloader the installer wrote, from the ESP it created, with two
    # ESPs on the disk. The firmware gets no boot variables -- OVMF's are
    # attached read-only -- so it falls back to scanning for
    # EFI/BOOT/BOOTX64.EFI, and the only ESP that has one is ours. That is the
    # honest version of the case: a machine whose NVRAM entry was lost still
    # has to come up.
    disk = os.path.abspath("vm-state-installer/empty0.qcow2")
    assert os.path.exists(disk), f"the installer's target disk is not at {disk}"
    print(subprocess.run(["ls", "vm-state-installer"], capture_output=True, text=True).stdout)
    import shutil
    variables = os.path.abspath("OVMF_VARS.fd")
    shutil.copyfile("${ovmfVariables}", variables)
    os.chmod(variables, 0o644)
    target = create_machine(
        "${targetCommand}"
        + f" -drive if=pflash,format=raw,unit=1,file={variables}"
        + f" -drive file={disk},if=virtio,werror=report",
        name="target")
    target.start()
    target.wait_for_unit("multi-user.target")
    print("a free-space install boots on its own bootloader")

    # The neighbour is still there, seen from the installed machine this time.
    after_boot = target.succeed("sha256sum /dev/vda1 /dev/vda2").replace("/dev/vda", "/dev/vdb")
    if after_boot != before_hashes:
        # "the bytes differ" is not a diagnosis, and the answer is always the
        # same two questions: who mounted it, and what appeared in it. Both
        # asked here so a failure arrives with its own explanation. Read-only,
        # and measured: a mount and unmount of a vfat with no writes does not
        # change a byte, so this cannot be what broke the comparison.
        print(target.succeed("findmnt --raw -no SOURCE,TARGET,OPTIONS || true"))
        target.succeed("mkdir -p /win && mount -o ro /dev/vda1 /win")
        print(target.succeed("find /win | head -40"))
        target.succeed("umount /win")
    assert after_boot == before_hashes, (
        "booting the installed machine changed a partition it does not own.\n"
        f"before:\n{before_hashes}\nafter:\n{after_boot}")
    # And nixarchy did not quietly mount it. A dual boot where one side
    # automounts the other's ESP read-write is a slower version of the same
    # accident.
    target.fail("findmnt -no TARGET /dev/vda1")
    target.fail("findmnt -no TARGET /dev/vda2")
    print("the other OS survived the boot too, and is not mounted")

    # ---- Invariant 1 ------------------------------------------------------
    # A rebuild straight after install builds nothing. Same assertion as
    # checks.install and the same reasoning: if the flake evaluates to the
    # store path that is running, there is by definition nothing to build.
    # Repeated here because this mode has a different layout, and a layout is
    # exactly the sort of thing that ends up describing a machine other than
    # the one it produced.
    before_sys = target.succeed("readlink -f /run/current-system").strip()
    target.succeed("cd /etc/nixos && nixos-rebuild build --flake .#installed 2>&1 | tail -20")
    built = target.succeed("readlink -f /etc/nixos/result").strip()
    if built != before_sys:
        print(target.succeed(
            "cd /etc/nixos && nix build --dry-run "
            ".#nixosConfigurations.installed.config.system.build.toplevel 2>&1 || true"))
    assert built == before_sys, (
        f"a rebuild of the generated flake evaluates to {built}, not the "
        f"installed {before_sys}: the free-space layout does not describe the "
        "machine it produced (Invariant 1).")
    print("a rebuild straight after a free-space install builds nothing")

    # Or this check never finishes: a machine from create_machine is not reaped
    # for us the way a declared node is, and the derivation sits with a live
    # qemu until the timeout. See tests/install.nix, which paid for this once.
    target.shutdown()
  '';
}
