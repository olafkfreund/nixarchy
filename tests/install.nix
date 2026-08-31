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
# screen it cannot reliably read. Which layout LUKS produces is what the disko
# check proves; this one proves the install flow. Narrowing it here is cheaper
# than an OCR anchor on a passphrase prompt.
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
      inherit (pkgs) system;
      specialArgs = { inherit inputs; };
      modules = [
        inputs.self.nixosModules.nixarchy
        inputs.home-manager.nixosModules.home-manager
        inputs.disko.nixosModules.disko
        (import ../installer/host.nix {
          hostname = "installed";
          username = "omarchy";
        })
        (import ../installer/disk-config.nix {
          device = "/dev/vdb";
          encrypt = false;
        })
        # Everything the generated configuration.nix adds. Without these the
        # seeded system is not the system that gets installed: system-path
        # differs, so nixos-install has to rebuild it, and with no network it
        # cannot fetch the inputs to do so. Keep this in step with
        # installer/template/configuration.nix -- a mismatch shows up as
        # "cannot build", which is a clear enough signal.
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

  nodes.installer =
    { ... }:
    {
      imports = [
        inputs.self.nixosModules.nixarchy
        inputs.home-manager.nixosModules.home-manager
      ];

      environment.systemPackages = [
        inputs.self.packages.${pkgs.system}.install
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
    print(installer.execute("cat /var/log/nixarchy-install.log 2>&1")[1])
    print("============================================================")
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
    print("install wrote a flake and an ESP")

    # ---- make the result observable ------------------------------------
    # Everything above this line is the product. Everything below adds the
    # serial root shell the driver needs and nothing else; see the note on
    # `instrumentation` for why it cannot be there from the start. The second
    # nixos-install copies -- the instrumented system is seeded -- so if this
    # step ever starts building, the seeding has drifted and the offline
    # failure will say which derivation.
    installer.succeed(
        "cp /etc/nixarchy/test-instrumentation.nix /mnt/etc/nixos/")
    installer.succeed(
        "sed -i 's|./hardware-configuration.nix|./hardware-configuration.nix\\n"
        "    ./test-instrumentation.nix|' /mnt/etc/nixos/configuration.nix")
    installer.succeed("grep -q test-instrumentation /mnt/etc/nixos/configuration.nix")
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

    # ---- the flake on disk is the user's -------------------------------
    target.succeed("git -C /etc/nixos rev-parse --is-inside-work-tree")
    for f in ["flake.nix", "flake.lock", "configuration.nix",
              "disk-config.nix", "nixarchy-apps.nix"]:
        target.succeed(f"test -s /etc/nixos/{f}")
    target.succeed("grep -q 'nixarchy-apps.nix' /etc/nixos/configuration.nix")
    print("/etc/nixos is a git repository holding the five generated files")

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
  '';
}
