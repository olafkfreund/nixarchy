{ inputs, pkgs }:
# Does the installer's *output* boot?
#
# What this cost, so nobody pays it twice. Three things were wrong, and the
# first two hid the third:
#
#   The installer died before it wrote a line of its log, because `clear` is
#   ncurses and ncurses will not emit a byte until it has found a terminfo
#   entry for $TERM. A test runs commands with no TERM and no terminal. That is
#   fixed in installer/lib/ui.sh, which now writes the escape itself.
#
#   The seeded system did not include hardware-configuration.nix, which
#   nixos-generate-config writes on the target. #12 called that unknowable from
#   outside and stopped there. It is knowable: the machine is qemu and the file
#   is the same every run bar one line, so it is reproduced below and both CPU
#   variants are seeded.
#
#   And then the real one: NixOS marks its own assembly derivations -- the
#   toplevel, etc, system-units, every X-Restart-Triggers-* -- allowSubstitutes
#   = false, so nixos-install would not copy them into the target store, tried
#   to rebuild them, needed stdenv to do it, and worked backwards to the source
#   bootstrap. 1129 derivations, offline, ending at bash's tarball. The fix is
#   in installer/install.sh, not here, and it is worth more than this test:
#   with a network it is why the install downloaded 4.6 GiB of a closure that
#   was already on the disk.
#
# Every other check here boots a system the test itself built. This one boots a
# disk: a partition table, a bootloader and a generated flake that
# nixarchy-install wrote, with nothing from the test's own store handed to the
# kernel. That is the only way to find out whether the thing a person ends up
# with actually starts.
#
# Two phases on one disk image.
#
#   installer  a normal test node standing in for the ISO. It has the install
#              package, a blank /dev/vdb, and the whole reference closure in
#              its store, because a test VM has no network and nixos-install
#              copies from wherever it can reach.
#
#   target     NOT a second node. A node boots through qemu's -kernel from the
#              store, which is exactly what must not happen: the point is the
#              bootloader the installer wrote. So the installer is shut down
#              and a machine is built by hand on the same qcow2, with OVMF,
#              the way nixpkgs' own nixos/tests/installer.nix does it.
#
# encrypt=no, deliberately. The layout defaults to LUKS and an encrypted target
# would stop at a passphrase prompt this test would have to type through on a
# screen it cannot reliably read. This comment used to say "which layout LUKS
# produces is what the disko check proves" -- and there is no disko check. A
# comment claiming coverage that does not exist is the same failure as a test
# that cannot fail, and every install test choosing encrypt=no is exactly how
# an encrypted install shipped unable to unlock its root (#322). So, honestly:
# this one proves the UNENCRYPTED install flow, and the encrypted layout is
# proved by nothing here. Narrowing was still cheaper than an OCR anchor on a
# passphrase prompt; the gap belongs to a check of its own.
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

  # Both pflash drives, not just the code one. Without unit=1 the firmware has
  # nowhere to keep EFI variables, and a machine that cannot write them is a
  # different machine from the one a person installs onto.
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
    "-drive if=pflash,format=raw,unit=1,readonly=on,file=${pkgs.OVMF.variables}"
  ];
in
pkgs.testers.runNixOSTest {
  name = "nixarchy-install";

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
        # The answers the wizard would have collected. device is the blank
        # second disk; /dev/vda is this node's own root.
        "nixarchy/answers".text = ''
          device=/dev/vdb
          encrypt=no
          recovery_passphrase=rescue-me
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
        # The blank target, which appears as /dev/vdb.
        emptyDiskImages = [ 20480 ];
        # nixos-install copies the whole closure into the target, and the
        # default 1 GB store overlay is nowhere near enough.
        diskSize = 32768;
      };
    };

  enableOCR = true;

  testScript = ''
    installer.wait_for_unit("multi-user.target")

    # Is what was seeded actually here? extraDependencies is supposed to put
    # the reference and target closures in this store, and when nixos-install
    # decides to build system-path anyway the useful question is whether the
    # path is missing or merely different.
    print("seeded system-path outputs present:")
    print(installer.succeed("ls -d /nix/store/*-system-path 2>/dev/null | head -5 || echo NONE"))
    print("seeded toplevels present:")
    print(installer.succeed("ls -d /nix/store/*-nixos-system-* 2>/dev/null | head -5 || echo NONE"))

    # The hardware config the install is about to generate, printed because
    # the seeding above claims to reproduce it. When that claim stops being
    # true this is the first place a reader will look.
    print(installer.succeed(
        "nixos-generate-config --no-filesystems --show-hardware-config"))

    # ---- install -------------------------------------------------------
    import os
    import re
    import time
    import subprocess
    started = time.time()
    # execute, not succeed. The dashboard sends every phase to a log file and
    # keeps the screen for the progress bar, so a failed install prints nothing
    # but the palette escapes -- and a test that asserts on that has no idea
    # what went wrong. Take the status, then print the log either way, then
    # assert. The log is the only place the answer ever exists.
    # Not `bash -x`. install.sh says at the top that a passphrase and a
    # password hash pass through it, so a trace would put both in a build log
    # that anyone can read. The installer's own log is the diagnostic.
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
    #
    # Deliberately NOT gated on rc. The first version of this was, and it never
    # fired: the installer exited 0 after building nothing, because a phase
    # that returned non-zero did not stop the group whose status was tested.
    # That is fixed in install.sh now, but the whole point of this block is to
    # be the thing that speaks when the status is not to be trusted, so it does
    # not ask the status first.
    if True:
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

    # ---- how long it took ----------------------------------------------
    # The installer's own number, not the driver's: it excludes the time the
    # test spent getting to the point of running it, and it is the same figure
    # the finish screen shows the person doing the install.
    import json
    state = json.loads(installer.succeed("cat /run/nixarchy-install/state.json"))
    seconds = state["seconds"]
    print(f"install_seconds={seconds}")

    # A ceiling, not the claim.
    #
    # This is a VM on a shared machine with an emulated disk; real hardware is
    # faster, and the README quotes the real figure. What this catches is the
    # regression that matters: with the closure on the medium an install is a
    # copy and an activation, and the moment something falls out of the closure
    # and gets built instead, the time does not drift -- it multiplies. Runs
    # here land around 500s; the budget is set well clear of that so runner
    # variance is not a flake, and a build is still nowhere near it.
    budget = 1800
    assert seconds < budget, (
        f"the install took {seconds}s, over the {budget}s budget. Something "
        "that used to be copied is now being built -- check the log above for "
        "'will be built', and see #49.")

    # Asserted from this side, while the target is still mounted: it localises
    # a failure to "the install" rather than "the boot", which are very
    # different bugs to chase.
    installer.succeed("test -d /mnt/etc/nixos/.git")
    installer.succeed("test -d /mnt/boot/EFI")

    # The install log reached the disk (#239).
    #
    # Asserted under /mnt rather than on the installer, because on the
    # installer it is always there and always will be -- that is the copy that
    # dies with the live session. A user whose install failed rebooted, found
    # no bootloader entry, went looking for the log and found nothing: the
    # target's /var/log is a freshly made subvolume and the real log was on an
    # ISO that no longer existed. The serial dump this test reads everything
    # through is exactly why CI could not see that; a laptop has no serial
    # port.
    installer.succeed("test -s /mnt/var/log/nixarchy-install.log")

    # Root-only, because it is deliberately NOT on the ESP. FAT32 has no
    # permissions, and an installer that handles a crypt hash should not put
    # its transcript somewhere permissions cannot protect it.
    mode = installer.succeed(
        "stat -c '%a %U' /mnt/var/log/nixarchy-install.log").strip()
    assert mode == "600 root", f"the install log is {mode}, not 600 root"
    print("install wrote a flake and an ESP")

    # ---- the login hash is NOT in the repository -----------------------
    #
    # /etc/nixos is a git repository and nixarchy-config-repo exists to push
    # it to GitHub, so a crypt hash written into configuration.nix is a hash
    # published to whoever reads that repo. It used to be. Asserted from this
    # side because the whole tree is visible here, including files a later
    # step might add.
    installer.fail("grep -rq '[$]6[$]' /mnt/etc/nixos")
    installer.succeed("test -f /mnt/var/lib/nixarchy/password.hash")
    mode = installer.succeed(
        "stat -c '%a %U:%G' /mnt/var/lib/nixarchy/password.hash").strip()
    assert mode == "600 root:root", (
        f"the password hash is {mode}, not 600 root:root -- it is readable by "
        "somebody it should not be")
    print("the hash is outside the repo, 0600 root:root")

    # ---- the factory baseline (#172) -----------------------------------
    #
    # Asserted from this side too, and first, because it localises a failure:
    # take_factory_snapshot runs at the very end of the install, and "the
    # snapshot was never taken" and "the snapshot did not survive the boot"
    # are different bugs. The subvolumes are at the btrfs top level, which
    # nothing mounts, so the top level is mounted to look -- exactly what
    # installer/host.nix's unit does when it uses them.
    installer.succeed("mkdir -p /run/toplevel")
    installer.succeed(
        "mount -o subvol=/ $(findmnt -no SOURCE /mnt | sed 's/\\[.*\\]//')"
        " /run/toplevel")
    print(installer.succeed("ls -a /run/toplevel"))
    installer.succeed("test -d /run/toplevel/@factory")
    installer.succeed("test -d /run/toplevel/@factory-home")
    installer.succeed("umount /run/toplevel")
    print("the install left @factory and @factory-home on the disk")

    # ---- make the result observable ------------------------------------
    # Everything above this line is the product. Everything below adds the
    # serial root shell the driver needs and nothing else; see the note on
    # `instrumentation` for why it cannot be there from the start. The second
    # nixos-install copies -- the instrumented system is seeded -- so if this
    # step ever starts building, the seeding has drifted and the offline
    # failure will say which derivation.
    # Into the machine's own directory, beside the configuration.nix that
    # imports it. Relative imports are why: hosts/installed/configuration.nix
    # says ./test-instrumentation.nix, and a copy at the flake root is not
    # that path.
    installer.succeed(
        "cp /etc/nixarchy/test-instrumentation.nix /mnt/etc/nixos/hosts/installed/")
    installer.succeed(
        "sed -i 's|./hardware-configuration.nix|./hardware-configuration.nix\\n"
        "    ./test-instrumentation.nix|'"
        " /mnt/etc/nixos/hosts/installed/configuration.nix")
    installer.succeed(
        "grep -q test-instrumentation"
        " /mnt/etc/nixos/hosts/installed/configuration.nix")
    installer.succeed("git -C /mnt/etc/nixos add -A")
    print(installer.succeed(
        "nixos-install --root /mnt --flake /mnt/etc/nixos#installed"
        " --no-root-password"
        " --option extra-experimental-features 'nix-command flakes'"
        " --option always-allow-substitutes true 2>&1 | tail -20",
        timeout=1800))
    print("the installed flake now carries a serial root shell")

    # The name emptyDiskImages produces for a node called "installer". Asserted
    # rather than assumed: if the driver ever changes it, the failure should say
    # so here and not as a qemu error about a missing file.
    installer.succeed("true")
    print(subprocess.run(["ls", "vm-state-installer"], capture_output=True, text=True).stdout)

    installer.shutdown()

    # ---- boot what was installed ---------------------------------------
    # A command string, not a dict: create_machine's signature is
    # (start_command: str, *, name, keep_machine_state) in current nixpkgs.
    disk = os.path.abspath("vm-state-installer/empty0.qcow2")
    assert os.path.exists(disk), f"the installer's target disk is not at {disk}"
    target = create_machine(
        "${targetCommand}" + f" -drive file={disk},if=virtio,werror=report",
        name="target")
    target.start()
    target.wait_for_unit("multi-user.target")
    print("the installed disk booted on its own bootloader")

    # ---- the desktop comes up ------------------------------------------
    target.wait_for_unit("display-manager.service")
    target.wait_until_succeeds("loginctl list-sessions | grep -q greeter")

    # A blank greeter would still accept the password, so assert something was
    # drawn. Retried rather than slept at: a fixed wait is a guess about how
    # fast the machine is, and the same guess was wrong twice already in this
    # repo's other tests.
    drawn = ""
    for attempt in range(10):
        target.sleep(4)
        target.screenshot("greeter")
        drawn = target.get_screen_text().strip()
        print(f"attempt {attempt}: greeter OCR {drawn!r}")
        if drawn:
            break
    assert drawn, "the greeter never drew anything in 40s"

    target.send_chars("omarchy\n")
    target.wait_until_succeeds(
        "journalctl -b -u display-manager --no-pager"
        " | grep -q 'Authentication for user .*omarchy.* successful'")
    target.wait_until_succeeds("systemctl is-active user@1000.service")
    target.wait_until_succeeds("pgrep -u 1000 -f Hyprland")
    print("the installed machine reaches a Hyprland session")

    # That login is the proof the indirection works: hashedPasswordFile is read
    # at activation rather than baked into the store, so a hash file that was
    # missing, misplaced or unreadable would have failed authentication just
    # now. Assert it survived the boot as well -- /var/lib is not managed by
    # /etc activation, which is exactly why the file is there and not in
    # /etc/nixarchy among the generated symlinks.
    target.succeed("test -f /var/lib/nixarchy/password.hash")
    target.fail("grep -rq '[$]6[$]' /etc/nixos")
    print("the hash survived the boot, and the repo is still clean of it")

    # ---- the flake on disk is the user's -------------------------------
    target.succeed("git -C /etc/nixos rev-parse --is-inside-work-tree")
    for f in ["flake.nix", "flake.lock", "disk-config.nix"]:
        target.succeed(f"test -s /etc/nixos/{f}")
    for f in ["default.nix", "configuration.nix", "hardware-configuration.nix",
              "nixarchy-apps.nix"]:
        target.succeed(f"test -s /etc/nixos/hosts/installed/{f}")
    target.succeed(
        "grep -q 'nixarchy-apps.nix' /etc/nixos/hosts/installed/configuration.nix")
    print("/etc/nixos is a git repository, and the machine is a directory in it")

    # ---- a second machine is a second directory ------------------------
    #
    # The whole point of the layout, so it is asserted rather than assumed.
    # Done here because this machine can evaluate its own flake offline -- its
    # inputs are all in its store -- which nothing outside a booted install
    # can do.
    #
    # git add is not tidiness: a flake in a worktree sees only tracked or
    # staged files, so an unstaged hosts/spare does not exist to the evaluator
    # and the error names a missing path rather than an untracked one.
    target.succeed("cp -r /etc/nixos/hosts/installed /etc/nixos/hosts/spare")
    target.succeed(
        "sed -i 's/installed/spare/g' /etc/nixos/hosts/spare/default.nix")
    target.succeed("git -C /etc/nixos add -A")
    names = target.succeed(
        "cd /etc/nixos && nix --extra-experimental-features 'nix-command flakes'"
        " eval --raw .#nixosConfigurations --apply"
        " 'x: builtins.concatStringsSep \" \" (builtins.attrNames x)'").strip()
    assert names == "installed spare", (
        f"adding a host directory gave {names!r}, not 'installed spare' -- "
        "flake.nix is not finding machines by reading ./hosts")

    # And it is a different machine, not the same one twice.
    spare = target.succeed(
        "cd /etc/nixos && nix --extra-experimental-features 'nix-command flakes'"
        " eval --raw .#nixosConfigurations.spare.config.networking.hostName").strip()
    assert spare == "spare", f"the second host is called {spare!r}"
    target.succeed("git -C /etc/nixos rm -r --cached -q hosts/spare")
    target.succeed("rm -rf /etc/nixos/hosts/spare")
    print("a second machine is a second directory")

    # ---- Invariant 1 ---------------------------------------------------
    # If the flake evaluates to the same store path that is running, then every
    # path in its closure already exists and there is by definition nothing to
    # build. That is stronger than parsing "N derivations will be built", and
    # it does not depend on the wording of Nix's output, which is not a stable
    # interface.
    #
    # Deliberately nixos-rebuild and not `nh os switch`, which is what a user
    # types: nh wraps nixos-rebuild, so asserting through it would test the
    # wrapper rather than the invariant. Do not tidy this up.
    before = target.succeed("readlink -f /run/current-system").strip()
    target.succeed("cd /etc/nixos && nixos-rebuild build --flake .#installed 2>&1 | tail -20")
    built = target.succeed("readlink -f /etc/nixos/result").strip()

    if built != before:
        print(target.succeed(
            "cd /etc/nixos && nix build --dry-run "
            ".#nixosConfigurations.installed.config.system.build.toplevel 2>&1 || true"))
    assert built == before, (
        f"a rebuild of the generated flake evaluates to {built}, not the "
        f"installed {before}: the flake on disk does not describe the machine "
        "it was installed on (Invariant 1).")

    target.succeed("cd /etc/nixos && nixos-rebuild switch --flake .#installed")
    assert target.succeed("readlink -f /run/current-system").strip() == before
    print("a rebuild straight after install builds nothing (Invariant 1)")

    # ---- the factory reset actually resets (#172) -----------------------
    #
    # The one assertion in this feature that cannot be made anywhere cheaper.
    # checks.options exercises every refusal and the staging, with a fake
    # `btrfs` -- but "the unit renames the right subvolume, early enough in
    # the boot that the running system sees the result" is a claim about a
    # real filesystem and a real boot, and this is the only check that has
    # either.
    #
    # Read-only is asserted through `subvolume list -r`, which lists only
    # read-only subvolumes: a baseline that could be written to is one that
    # can drift into being a copy of the machine rather than of the install.
    # The store, home and the journal are on the subvolumes the layout
    # promised -- not sitting inside `@` with empty subvolumes mounted over
    # the top of them.
    #
    # That shape installs cleanly and boots as far as the LUKS prompt, then
    # fstab mounts the empty @nix over /nix, stage 2 loses its init, and the
    # machine drops to an emergency mode whose root account is locked. It was
    # reported from a real install and nothing in this suite could see it:
    # every check installs once onto a fresh disk, and the fault needs a
    # second run over mounts a failed first run left behind.
    #
    # Asserted on the BOOTED machine rather than on /mnt during the install,
    # because that is where it bites -- the installer is checked separately by
    # verify_subvolume_mounts, which refuses to install into this state at all.
    for mp, subvol in [("/nix", "@nix"), ("/home", "@home"), ("/var/log", "@log")]:
        got = target.succeed(
            f"findmnt -no SOURCE --mountpoint {mp}").strip()
        assert f"[/{subvol}]" in got, (
            f"{mp} is not mounted from the {subvol} subvolume (findmnt says "
            f"{got!r}). If it is not a mountpoint at all, the install wrote "
            f"through the root subvolume and the data under {mp} is "
            f"unreachable once {subvol} mounts over it."
        )

    # The recovery passphrase is on the machine and NOT in the repository.
    #
    # `must fail: grep -rq '[$]6[$]' /mnt/etc/nixos` above is the other half of
    # this and it is the one that matters: /etc/nixos is a git repository that
    # nixarchy-config-repo pushes to GitHub, so a crypt hash written into it is
    # published. boot.initrd.systemd.emergencyAccess takes a literal string and
    # would do exactly that, which is why this goes through
    # boot.initrd.secrets instead -- a path read at bootloader-install time.
    #
    # Asserted here rather than trusted because the failure is silent: the
    # machine boots either way, and the difference only shows up in a
    # repository somebody made public.
    shadow = target.succeed("cat /var/lib/nixarchy/initrd-shadow")
    assert shadow.startswith("root:$6$"), (
        f"/var/lib/nixarchy/initrd-shadow is {shadow!r}, not a root shadow "
        "line with a sha-512 hash. If the hash looks mangled, substitution ate "
        "the `$`; if the line is missing its fields, sulogin will not parse it."
    )
    login = target.succeed("cat /var/lib/nixarchy/password.hash").strip()
    assert login not in shadow, (
        "the recovery hash is the login hash. It goes into the initrd on the "
        "unencrypted ESP, so this hands anyone holding the disk the credential "
        "for the account."
    )
    perms = target.succeed(
        "stat -c '%a %U' /var/lib/nixarchy/initrd-shadow").strip()
    assert perms == "600 root", (
        f"/var/lib/nixarchy/initrd-shadow is {perms}, want '600 root'"
    )

    # The config points at that file rather than carrying its contents.
    target.succeed(
        "grep -q '/var/lib/nixarchy/initrd-shadow' /etc/nixos/hosts/*/configuration.nix")

    subvols = target.succeed("btrfs subvolume list -r /")
    print(subvols)
    readonly = [line.split(" path ", 1)[1].strip()
                for line in subvols.splitlines() if " path " in line]
    for want in ["@factory", "@factory-home"]:
        assert want in readonly, (
            f"{want} is not a read-only subvolume on a freshly installed "
            f"machine (read-only subvolumes: {readonly}). It cannot be created "
            "retroactively -- a baseline made later contains everything the "
            "reset exists to undo -- so every machine installed from this "
            "commit would get the 'no factory snapshot' refusal forever.")
    print("the baseline survived the boot, and is still read-only")

    # Something to lose, in both halves of what the reset covers.
    target.succeed("touch /home/omarchy/a-file-the-user-made")
    target.succeed("mkdir -p /var/lib/some-service")
    target.succeed("touch /var/lib/some-service/state")

    target.succeed("omarchy-system-factory-reset --force")
    target.succeed("test -e /var/lib/nixarchy/factory-reset.request")

    # And staging is ALL it did. The script runs inside the session whose
    # /home it is about to replace; if it ever starts doing the work itself,
    # this is the assertion that says so.
    target.succeed("test -e /home/omarchy/a-file-the-user-made")
    target.succeed("test -e /var/lib/some-service/state")
    print("the reset staged a request and changed nothing")

    target.shutdown()
    target.start()
    target.wait_for_unit("multi-user.target")

    # Result= alone is not enough: a unit skipped by ConditionPathExists also
    # reports Result=success, so asserting only that would pass on a machine
    # where the reset never ran. ConditionResult=yes says the condition was
    # met and the unit really started; ExecMainStatus=0 says the script it
    # runs got to the end.
    unit_state = target.succeed(
        "systemctl show nixarchy-factory-reset.service"
        " -p Result -p ConditionResult -p ExecMainStatus").strip()
    print(unit_state)
    for want in ["Result=success", "ConditionResult=yes", "ExecMainStatus=0"]:
        assert want in unit_state.split(), (
            f"nixarchy-factory-reset.service: expected {want}, got "
            f"{unit_state!r}\n"
            + target.succeed(
                "journalctl -b -u nixarchy-factory-reset --no-pager 2>&1 || true"))

    # Both halves gone.
    target.fail("test -e /home/omarchy/a-file-the-user-made")
    target.fail("test -e /var/lib/some-service/state")

    # And the machine is still a machine: the home directory exists, and the
    # login hash came back with /var/lib rather than being lost with it.
    target.succeed("test -d /home/omarchy")
    target.succeed("test -f /var/lib/nixarchy/password.hash")

    # Set aside, not shredded -- which is what the script promises twice
    # before it asks, and what the receipt explains afterwards.
    target.succeed("ls -d /var/lib.before-reset-*")
    target.succeed("btrfs subvolume list / | grep -q @home-before-reset-")
    target.succeed("test -e /var/lib/nixarchy/factory-reset.done")

    # The request is gone, so the next boot is an ordinary one. A reset that
    # repeated every boot would be indistinguishable from a machine that
    # cannot keep anything.
    target.fail("test -e /var/lib/nixarchy/factory-reset.request")

    # The configuration repository is untouched. This is the line that makes
    # the whole feature safe to offer: /etc/nixos is on the same subvolume as
    # /var/lib, and it is the one thing that makes a reinstall recoverable.
    target.succeed("test -s /etc/nixos/flake.nix")
    target.succeed("git -C /etc/nixos rev-parse --is-inside-work-tree")
    print("a factory reset returned /home and /var/lib, and left /etc/nixos alone")

    # Shut the target down, or this check never finishes.
    #
    # `installer` is shut down above; `target` was not, and a machine made by
    # create_machine is not reaped for us the way a declared node is. The test
    # script would reach its end, every assertion passing, and the derivation
    # would then sit forever with a qemu still running -- measured at nine
    # hours against a script that finished in 510 seconds.
    #
    # That is why this check had never once produced a verdict: CI records the
    # 45-minute timeout as `cancelled`, which reads like someone cancelled it
    # rather than like a hang, so the passing test looked like an interrupted
    # one every single time.
    target.shutdown()
  '';
}
