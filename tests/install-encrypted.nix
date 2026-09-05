{ inputs, pkgs }:
# Does an ENCRYPTED install produce a machine that can unlock its root?
#
# checks.install proves the install flow on an unencrypted disk, and its header
# says why it narrowed: an encrypted target stops at a passphrase prompt the
# test "would have to type through on a screen it cannot reliably read". That
# objection dissolves rather than needing to be worked around: the prompt does
# not have to be on a screen. The instrumented target carries
# console=ttyS0,115200 -- exactly what tests/install-iso.nix's SERIAL step adds
# for the same reason -- so stage 1 asks for the passphrase on the serial line,
# wait_for_console_text sees it and send_console answers it. No OCR. Plymouth
# is forced off in the same instrumentation module, because a splash that owns
# the password prompt is precisely what would take it back off the console.
#
# Why this check exists at all: encryption is the DEFAULT answer to the
# interactive question, and until this file every install test in the repo
# passed encrypt=no (tests/install.nix, tests/free-space.nix,
# tests/install-iso.nix, tests/install-iso-net.nix -- each for a locally good
# reason, and jointly leaving the default path of the product with no coverage
# past `nix build`). What that cost is not hypothetical: reuse_baked_initrd
# selected between the two baked module lists on `[ "$encrypt" = "yes" ]` while
# everything upstream of it had already normalised $encrypt to true/false, so
# every encrypted install mkForce-pinned the PLAIN list, the LUKS modules were
# forced out of the initrd, and the machine could not unlock its root on first
# boot. The install succeeded. Every check was green. This file is the check
# that goes red on exactly that: the pin is asserted by content right after the
# install, and the boot then proves the initrd can actually open the volume.
#
# Beyond "it booted", three assertions ride the encrypt axis and exist nowhere
# else:
#
#   * the pinned initrd module list is the ENCRYPTED one -- every module that
#     distinguishes the encrypted reference from the unencrypted one is present
#     in the mkForce pin the installer wrote
#   * autologin reaches a session. install.sh substitutes @autologin@ with the
#     encrypt flag -- an encrypted disk has already authenticated the user --
#     so autologin=true is a configuration only encrypted installs produce, and
#     no test had ever booted it
#   * the recovery credential is where installer/template/host/configuration.nix
#     argues it must be: appended to the initrd on the UNENCRYPTED ESP, which
#     is the one layout where that tradeoff is real -- and the LOGIN hash is
#     NOT there, which is the property that makes the recovery passphrase a
#     spendable credential rather than a published copy of the real one
#
# What is deliberately NOT here: the factory reset, the second-machine
# directory, the install-log placement -- checks.install covers those and they
# do not vary with encryption. This check stays lean because it already pays
# for a full offline install and a LUKS boot.
#
# The mechanics -- seeding, the two-phase disk, the instrumentation dance --
# are tests/install.nix's, and its comments are the reference for them. Where
# this file differs it says so; where it repeats, read the original.
let
  collectInputs =
    flake:
    [ flake.outPath ] ++ builtins.concatMap collectInputs (builtins.attrValues (flake.inputs or { }));

  inputPaths = pkgs.lib.unique (builtins.concatMap collectInputs (builtins.attrValues inputs));

  # The ENCRYPTED reference -- the other half of the pair checks.install seeds.
  reference = inputs.self.nixosConfigurations.reference.config.system.build;

  # Same fixed hash as tests/install.nix, same generation note there.
  passwordHash = "$6$rounds=100000$nixarchytestsalt$zoz9HmOtqvELBidMdICVEOuvNl5LQCo.yhxsVpM6bgkeTdCG9D91zOaGX9Bu/YsQTlWLwuQF1SrOL0DY8Bu/V/";

  # Typed at stage 1 over the serial line, so it stays out of any screen this
  # test would have to read. A disposable VM's secret.
  luksPassphrase = "super-secret-luks";

  # The modules that exist ONLY because of encryption: what LUKS adds to the
  # initrd, computed from the same two configurations whose lists are baked
  # into install.sh as @initrdmodules@ / @initrdmodulesplain@. If the pin the
  # installer writes is missing any of these, it pinned the plain list and the
  # initrd cannot map the LUKS device.
  #
  # Guarded at evaluation: if the two lists ever become equal, this check's
  # central assertion is vacuous and someone has to decide what that means --
  # loudly, not by a grep that can no longer fail.
  encryptedOnlyModules =
    let
      enc = inputs.self.nixosConfigurations.reference.config.boot.initrd.availableKernelModules;
      plain =
        inputs.self.nixosConfigurations.reference-unencrypted.config.boot.initrd.availableKernelModules;
      only = pkgs.lib.subtractLists plain enc;
    in
    if only == [ ] then
      throw ''
        tests/install-encrypted.nix: the encrypted and unencrypted reference
        initrd module lists are identical, so "the ENCRYPTED list was pinned"
        can no longer be told apart from "the plain one was". Either the LUKS
        modules stopped being initrd modules (update this check's central
        assertion) or something collapsed the two references into one (a bug).
      ''
    else
      only;

  # Test backdoor plus the two things this check needs from the target that
  # tests/install.nix's does not:
  #
  #   console=ttyS0 puts stage 1 -- and its passphrase prompt -- on the serial
  #   line the driver reads and types at. Same move as install-iso.nix's SERIAL
  #   step, made here in the instrumentation module because both the seeded
  #   instrumented system and the flake's copy have to agree.
  #
  #   plymouth off, forced: the splash's password agent would take the prompt
  #   off the console, and the splash is not what is under test.
  #
  # Kept semantically identical to the /etc/nixarchy/test-instrumentation.nix
  # text below -- the second nixos-install copies rather than builds only while
  # the two produce the same configuration.
  instrumentation = {
    imports = [ "${inputs.nixpkgs}/nixos/modules/testing/test-instrumentation.nix" ];
    boot.kernelParams = [ "console=ttyS0,115200" ];
    boot.plymouth.enable = pkgs.lib.mkForce false;
  };

  # See tests/install.nix on why this is knowable, and late.
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

  # The pin a CORRECT installer adds for an encrypted install: the encrypted
  # reference's lists. This is what the seeded systems carry, so if the
  # installer pins the other list the installed toplevel differs from every
  # seed -- and before that can surface as an offline build, the assertion on
  # hardware-configuration.nix below names the actual bug.
  initrdPin =
    let
      ref = inputs.self.nixosConfigurations.reference.config;
    in
    {
      boot.initrd.availableKernelModules = pkgs.lib.mkForce ref.boot.initrd.availableKernelModules;
      boot.initrd.kernelModules = pkgs.lib.mkForce ref.boot.initrd.kernelModules;
    };

  targetSystemFor =
    {
      cpuModule,
      instrumented ? false,
    }:
    (inputs.nixpkgs.lib.nixosSystem {
      system = pkgs.stdenv.hostPlatform.system;
      specialArgs = { inherit inputs; };
      modules = [
        inputs.self.nixosModules.nixarchy
        inputs.home-manager.nixosModules.home-manager
        inputs.disko.nixosModules.disko

        # ONE module mirroring installer/template/host/ -- the shape is
        # load-bearing; see tests/install.nix on module merge order. The
        # values are what install.sh substitutes for an ENCRYPTED install:
        # encrypt = true, autologin = true (it follows encryption), and the
        # recovery secret present, since the answers below carry a
        # recovery_passphrase.
        {
          imports = [
            (import ../installer/host.nix {
              hostname = "installed";
              username = "omarchy";
            })
            (import ../installer/disk-config.nix {
              device = "/dev/vdb";
              encrypt = true;
            })
            {
              time.timeZone = "UTC";
              console.keyMap = "us";
              nixpkgs.config.allowUnfree = true;
              services.displayManager.autoLogin = {
                enable = true;
                user = "omarchy";
              };
              users.users.omarchy.hashedPasswordFile = "/var/lib/nixarchy/password.hash";
              boot.initrd.secrets = {
                "/etc/shadow" = "/var/lib/nixarchy/initrd-shadow";
              };
            }
          ];
        }
        (hardwareConfig cpuModule)
        initrdPin
      ]
      ++ pkgs.lib.optional instrumented instrumentation;
    }).config.system.build;

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

  qemuCommon = import "${inputs.nixpkgs}/nixos/lib/qemu-common.nix" {
    inherit (pkgs) lib stdenv;
  };

  # Both pflash drives; see tests/install.nix on why unit=1 matters and why
  # the disk is attached at runtime.
  targetCommand = pkgs.lib.concatStringsSep " " [
    (qemuCommon.qemuBinary pkgs.qemu_test)
    "-cpu max -m 4096 -smp 4"
    "-drive if=pflash,format=raw,unit=0,readonly=on,file=${pkgs.OVMF.firmware}"
    "-drive if=pflash,format=raw,unit=1,readonly=on,file=${pkgs.OVMF.variables}"
  ];
in
pkgs.testers.runNixOSTest {
  name = "nixarchy-install-encrypted";

  # Same budget and the same reasoning as tests/install.nix: under the job's
  # timeout, so a hang is a reported failure and not a `cancelled`.
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
        # For reading the appended initrd secret back out of the ESP: the
        # initrd and its secrets are compressed, and the assertion decompresses
        # rather than trusting that the append happened.
        pkgs.zstd
      ];

      nix.settings = {
        experimental-features = [
          "nix-command"
          "flakes"
        ];
        substituters = pkgs.lib.mkForce [ ];
        # See tests/install.nix: seeded paths are unsigned, and /mnt would
        # otherwise refuse every one of them and fall back to the source
        # bootstrap.
        require-sigs = false;
      };

      environment.etc = {
        # encrypt=yes: the whole subject. luks_passphrase is required with it
        # and is what the target boot types back at stage 1.
        "nixarchy/answers".text = ''
          device=/dev/vdb
          encrypt=yes
          luks_passphrase=${luksPassphrase}
          recovery_passphrase=rescue-me
          hostname=installed
          username=omarchy
          password_hash=${passwordHash}
          timezone=UTC
          keymap=us
        '';

        # Must produce the same configuration as `instrumentation` above.
        "nixarchy/test-instrumentation.nix".text = ''
          { modulesPath, lib, ... }:
          {
            imports = [ "''${modulesPath}/testing/test-instrumentation.nix" ];
            boot.kernelParams = [ "console=ttyS0,115200" ];
            boot.plymouth.enable = lib.mkForce false;
          }
        '';
      };

      # The offline seeding contract, unchanged from tests/install.nix except
      # that every system here is the encrypted one. Read the notes there
      # before widening anything.
      system.extraDependencies = [
        reference.toplevel
        reference.diskoScript
        (targetSystemFor { cpuModule = "kvm-amd"; }).diskoScript
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
        useEFIBoot = true;
        emptyDiskImages = [ 20480 ];
        diskSize = 32768;
      };
    };

  testScript = ''
    installer.wait_for_unit("multi-user.target")

    # ---- install -------------------------------------------------------
    import os
    import re
    import time
    import subprocess
    started = time.time()
    # execute, not succeed, and no `bash -x`: the log is the diagnostic and a
    # LUKS passphrase passes through this script. See tests/install.nix.
    rc, out = installer.execute(
        "nixarchy-install --answers /etc/nixarchy/answers 2>&1", timeout=1800)
    print(f"driver_seconds={int(time.time() - started)}")
    print(out)
    print("=============== /var/log/nixarchy-install.log ===============")
    installer_log = installer.execute("cat /var/log/nixarchy-install.log 2>&1")[1]
    print(installer_log)
    print("============================================================")

    # ---- the ENCRYPTED module list was pinned --------------------------
    #
    # FIRST, before the offline-download explainer and before the exit-status
    # assertion, because when this one is wrong it is the cause of both: a pin
    # to the plain list is a toplevel no seed matches, the install falls back
    # to building offline, and everything downstream misreports. Naming the
    # actual bug beats naming its symptoms.
    #
    # Content, not reachability: the file the installer wrote into the user's
    # flake either carries the LUKS modules in its mkForce pin or it does not.
    # This is the end-to-end form of the guard on reuse_baked_initrd -- a shell
    # function whose encrypted branch once compared against a value that could
    # no longer occur, shipping machines that could not unlock their root while
    # every test stayed green on encrypt=no.
    hw = "/mnt/etc/nixos/hosts/installed/hardware-configuration.nix"
    hw_rc, hw_text = installer.execute(f"cat {hw}")
    if hw_rc == 0:
        print(hw_text)
        pinned = re.search(
            r"^\s*boot\.initrd\.availableKernelModules\s*=\s*lib\.mkForce\s*\[([^]]*)\]",
            hw_text, re.M)
        if pinned:
            missing = [m for m in "${toString encryptedOnlyModules}".split()
                       if f'"{m}"' not in pinned.group(1)]
            assert not missing, (
                f"the ENCRYPTED install pinned an initrd module list missing "
                f"{missing} -- that is the PLAIN baked list. reuse_baked_initrd "
                "chose the wrong side of the encryption question, the LUKS "
                "modules are mkForce'd out of the initrd, and this machine "
                "cannot unlock its root on first boot. The install itself "
                "may well have 'succeeded'.")
            print("the pin carries every LUKS-only module")
        else:
            # No pin at all is the legitimate other branch: something detected
            # was not on the medium and the install builds its own initrd. On
            # THIS fixture that never happens -- the detected list is seeded
            # and known covered -- so reaching here means the pin logic broke
            # differently. Say so.
            raise AssertionError(
                "hardware-configuration.nix carries no mkForce pin at all; on "
                "this fixture every detected module is in the baked list, so "
                "reuse_baked_initrd should have pinned. Its refusal path has "
                "changed -- read the install log above.")

    # ---- offline explainer + status ------------------------------------
    # Same block as tests/install.nix, same reasons, deliberately not gated
    # on rc.
    if True:
        wanted = sorted(set(re.findall(r"unable to download '([^']+)'", installer_log)))
        sources = [u for u in wanted if not u.endswith("/nix-cache-info")]
        if sources:
            listed = "\n  ".join(sources[:5])
            more = f"\n  ... and {len(sources) - 5} more" if len(sources) > 5 else ""
            raise AssertionError(
                "the install had to BUILD something, and this machine has no "
                "network to fetch its source with. Either a nixpkgs rebuild "
                "has not reached cache.nixos.org yet (clears on its own; see "
                "tests/install.nix), or the seeded ENCRYPTED systems have "
                "drifted from what the installer writes -- and on this check "
                "the first thing to suspect is the initrd pin asserted "
                "above.\n\n"
                f"  {listed}{more}")

    assert rc == 0, f"nixarchy-install exited {rc}; the log above says why"

    import json
    state = json.loads(installer.succeed("cat /run/nixarchy-install/state.json"))
    print(f"install_seconds={state['seconds']}")
    assert state["seconds"] < 1800, (
        f"the install took {state['seconds']}s, over budget -- something that "
        "used to be copied is being built; check the log for 'will be built'")

    installer.succeed("test -d /mnt/etc/nixos/.git")
    installer.succeed("test -d /mnt/boot/EFI")

    # The login hash stays out of the repository on this layout too.
    installer.fail("grep -rq '[$]6[$]' /mnt/etc/nixos")
    installer.succeed("test -f /mnt/var/lib/nixarchy/password.hash")

    # And the root really is LUKS: the installer must not have quietly taken
    # the unencrypted layout while reporting the encrypted one. blkid on the
    # partition disko created; the mapped device is what carries btrfs.
    installer.succeed("blkid /dev/vdb2 | grep -q crypto_LUKS"
                      " || { blkid /dev/vdb; exit 1; }")
    print("the target root partition is crypto_LUKS")

    # ---- make the result observable ------------------------------------
    # As in tests/install.nix, plus this file's serial console and plymouth
    # switch-off riding in the same module.
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

    # ---- the recovery credential is in the initrd on the ESP -----------
    #
    # installer/template/host/configuration.nix argues the whole tradeoff:
    # the recovery hash is appended to the initrd at bootloader-install time,
    # the initrd sits on the unencrypted ESP, and that is acceptable ONLY
    # because it is a credential of its own that the installer refuses to let
    # equal the login password. Both halves are asserted here, on the ESP
    # itself, because the failure is silent in both directions: an append
    # that never happened leaves a machine whose emergency shell is locked
    # (the generated root:* stands), and a login hash that leaked into the
    # initrd hands anyone holding the disk the account credential --
    # defeating the encryption this check exists to prove.
    #
    # Decompressed rather than trusted: the appended secrets ride as a
    # separate compressed archive after the initrd image, so the grep runs
    # over every stream the file yields. zstd and gzip are the two
    # compressors NixOS uses here; raw cat covers an uncompressed append.
    recovery_hash = installer.succeed(
        "cut -d: -f2 /mnt/var/lib/nixarchy/initrd-shadow").strip()
    assert recovery_hash.startswith("$6$"), (
        f"initrd-shadow's hash field is {recovery_hash!r}, not sha-512 crypt")
    login_hash = installer.succeed(
        "cat /mnt/var/lib/nixarchy/password.hash").strip()
    assert recovery_hash != login_hash, "the recovery hash IS the login hash"

    # grep reads to EOF, deliberately: -q exits on the first match, the
    # decompressors behind it then die of EPIPE, and the driver's shell runs
    # under pipefail -- so the FIRST version of this assertion FAILED on the
    # very initrd that carried the hash, with `cat: write error: Broken pipe`
    # as the only clue. That is #273's exact shape -- an early-exiting reader
    # killing its producer -- reproduced in the test that was written knowing
    # about #273. `-c >/dev/null` consumes the whole stream and still exits
    # 0 only on a match.
    initrds = installer.succeed(
        "ls /mnt/boot/EFI/nixos/*initrd*").split()
    assert initrds, "no initrd on the ESP at all"
    for f in initrds:
        streams = (f"{{ zstdcat {f} 2>/dev/null; zcat {f} 2>/dev/null; "
                   f"cat {f}; }}")
        installer.succeed(
            f"{streams} | grep -a -F -c -- '{recovery_hash}' >/dev/null || "
            f"{{ echo 'the recovery hash is NOT in {f}: the secret append "
            f"failed and the emergency shell on this machine is locked'; "
            f"exit 1; }}")
        installer.fail(
            f"{streams} | grep -a -F -c -- '{login_hash}' >/dev/null")
    print(f"the recovery hash is in {len(initrds)} ESP initrd(s); "
          "the login hash is in none")

    installer.shutdown()

    # ---- boot it, through the passphrase prompt ------------------------
    disk = os.path.abspath("vm-state-installer/empty0.qcow2")
    assert os.path.exists(disk), f"the installer's target disk is not at {disk}"
    print(subprocess.run(["ls", "vm-state-installer"],
                         capture_output=True, text=True).stdout)
    target = create_machine(
        "${targetCommand}" + f" -drive file={disk},if=virtio,werror=report",
        name="target")
    target.start()

    # Stage 1 asks on the serial console -- console=ttyS0 in the
    # instrumentation, plymouth off. The pattern covers both stage-1
    # implementations: scripted prints "Passphrase for <device>", systemd
    # prints "Please enter passphrase for disk ...".
    target.wait_for_console_text(r"[Pp]assphrase for", timeout=600)
    target.send_console("${luksPassphrase}\n")
    print("stage 1 asked for the passphrase on the serial console")

    target.wait_for_unit("multi-user.target")
    print("the encrypted disk unlocked and booted on its own bootloader")

    # The root the machine is running on is the mapped LUKS device -- not a
    # plaintext partition that happened to boot.
    src = target.succeed("findmnt -no SOURCE /").strip()
    assert src.startswith("/dev/mapper/"), (
        f"/ is mounted from {src}, not from a dm-crypt mapping -- the boot "
        "did not go through LUKS")

    # ---- autologin reaches a session -----------------------------------
    #
    # Nothing is typed. install.sh sets @autologin@ from the encrypt answer,
    # so this configuration exists only on encrypted installs -- and reaching
    # Hyprland without a keystroke is the assertion. A greeter sitting there
    # waiting for a password fails this by timeout.
    target.wait_for_unit("display-manager.service")
    target.wait_until_succeeds("systemctl is-active user@1000.service")
    target.wait_until_succeeds("pgrep -u 1000 -f Hyprland")
    print("autologin reached a Hyprland session with no keystrokes")

    # And it is configuration, not coincidence: the flake the installer wrote
    # says so, in the block the @autologin@ token was substituted into.
    target.succeed(
        "grep -A2 'autoLogin' /etc/nixos/hosts/installed/configuration.nix"
        " | grep -q 'enable = true'")

    # The repository is still clean of hashes, seen from the booted machine.
    target.fail("grep -rq '[$]6[$]' /etc/nixos")
    target.succeed("test -f /var/lib/nixarchy/password.hash")

    # ---- Invariant 1, on the encrypted layout ---------------------------
    # Same assertion as tests/install.nix and the same reasoning; repeated
    # because the encrypted disk-config is a different layout, and a layout
    # is exactly the sort of thing that ends up describing a machine other
    # than the one it produced.
    before = target.succeed("readlink -f /run/current-system").strip()
    target.succeed(
        "cd /etc/nixos && nixos-rebuild build --flake .#installed 2>&1 | tail -20")
    built = target.succeed("readlink -f /etc/nixos/result").strip()
    if built != before:
        print(target.succeed(
            "cd /etc/nixos && nix build --dry-run "
            ".#nixosConfigurations.installed.config.system.build.toplevel 2>&1 || true"))
    assert built == before, (
        f"a rebuild of the generated flake evaluates to {built}, not the "
        f"installed {before}: the encrypted layout does not describe the "
        "machine it produced (Invariant 1).")
    print("a rebuild straight after an encrypted install builds nothing")

    # Or this check never finishes; see tests/install.nix, which paid for
    # this once.
    target.shutdown()
  '';
}
