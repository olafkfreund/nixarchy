{ inputs, pkgs }:
# Does a USER'S image reinstall the user's own machine -- copied, never built,
# nothing fetched, and the machine that boots the exact closure the image
# carried?
#
# checks.install-iso asks this of the reference image. This is the same
# question asked of the #478 reinstall image: installer/cd.nix instantiated
# over a machine that is NOT the reference -- username `kepler`, which no
# baked reference closure can match by accident. The assertion is the one
# #436 taught this repo to make: not "the install succeeded" but "nothing was
# built and nothing was fetched" -- install.sh's `--max-jobs 0` holds on the
# copied path, so a single attempted build fails the INSTALLED step loudly
# rather than compiling for an hour on a machine with no network device.
#
# ---------------------------------------------------------------------------
# THE MISSING PIECE, stated once, here (#480, child of #478)
#
# installer/cd.nix takes `source` (#479, landed), so the image below already
# bakes the user machine's closure. What cd.nix does NOT yet do is write the
# /etc/nixarchy-reference-{true,false} markers from `source.configs` -- they
# hardcode inputs.self.nixosConfigurations.reference{,-unencrypted}. Until
# that is parameterised:
#
#   - the CARRIED step fails: the marker names the reference toplevel, not
#     the user's, so this check has NOT passed and must not be wired as if
#     it had;
#   - the hardcoded marker also drags the reference closure onto every user
#     image through the /etc text's store references, which is its own bug.
#
# This file codes against the intended interface -- the marker names the
# toplevel of the machine in `source.configs` -- and the CARRIED step is the
# single place the gap is asserted. When the cd.nix change lands, nothing
# here should need to move.
# ---------------------------------------------------------------------------
#
# Everything about DRIVING the machine -- no test instrumentation, send_chars
# to tty2, markers on the serial line, the step() protocol on both sides, the
# EFI variable store, reap() -- is install-iso's, deliberately unchanged; the
# reasoning lives in tests/install-iso.nix and is not restated here. What
# differs is WHOSE machine the image carries and what the install must be:
# a copy of a named path, not a build of an equivalent one.
let
  # The user's machine: the same construction tests/install.nix uses for its
  # seeded targets -- installer/host.nix + disk-config.nix + a block
  # mirroring installer/template/host/configuration.nix -- but with a
  # username the reference set never uses. One variable, not two: hostname
  # is out of the closure by design (#436 stage 1), so the username is the
  # only knob that makes this closure distinguishable from the reference's.
  #
  # kernelModules = [ ]: unlike checks.install, nothing here runs
  # nixos-generate-config and rebuilds -- the baked toplevel IS the machine
  # that boots, so there is no generated hardware config to match and no
  # need for the kvm-amd/kvm-intel variants.
  # The whole nixosSystem, not its .config: cd.nix's `source.configs` takes
  # nixosConfigurations-shaped values and reaches for `.config` itself.
  userMachine = inputs.nixpkgs.lib.nixosSystem {
    system = pkgs.stdenv.hostPlatform.system;
    specialArgs = { inherit inputs; };
    modules = [
      inputs.self.nixosModules.nixarchy
      inputs.home-manager.nixosModules.home-manager
      inputs.disko.nixosModules.disko
      {
        imports = [
          (import ../installer/host.nix {
            hostname = "keep";
            username = "kepler";
          })
          (import ../installer/disk-config.nix {
            device = "/dev/vda";
            encrypt = false;
          })
          {
            time.timeZone = "UTC";
            console.keyMap = "us";
            nixpkgs.config.allowUnfree = true;
            services.displayManager.autoLogin = {
              enable = false;
              user = "kepler";
            };
            users.users.kepler.hashedPasswordFile = "/var/lib/nixarchy/password.hash";
          }
        ];
      }
      # The qemu guest hardware, and the initrd pinned to what the medium
      # carries -- tests/install.nix documents both blocks; a drifted
      # initrd offline is the source bootstrap.
      {
        imports = [ "${inputs.nixpkgs}/nixos/modules/profiles/qemu-guest.nix" ];
        boot.initrd.availableKernelModules = pkgs.lib.mkForce inputs.self.nixosConfigurations.reference-unencrypted.config.boot.initrd.availableKernelModules;
        boot.initrd.kernelModules = pkgs.lib.mkForce inputs.self.nixosConfigurations.reference-unencrypted.config.boot.initrd.kernelModules;
        nixpkgs.hostPlatform = pkgs.lib.mkDefault pkgs.stdenv.hostPlatform.system;
      }
    ];
  };

  userToplevel = userMachine.config.system.build.toplevel;

  # The user image: installer/cd.nix over the user's machine instead of the
  # reference set. `flake = inputs.self` because the machine above is defined
  # against this flake's inputs; a real reinstall image passes the user's
  # generated flake here, whose input sources are a superset of these.
  userIso = inputs.nixpkgs.lib.nixosSystem {
    system = pkgs.stdenv.hostPlatform.system;
    specialArgs = {
      inherit inputs;
      offline = true;
      source = {
        flake = inputs.self;
        configs = [ userMachine ];

        # Added after this check was written: #480 made `installed` required,
        # because the markers install.sh reads have to name a machine the
        # image carries. A user's image points both slots at their one
        # machine -- its own configuration already decided whether it is
        # encrypted, so there is no second shape to choose between.
        installed = {
          encrypted = userMachine;
          unencrypted = userMachine;
        };
      };
    };
    modules = [ ../installer/cd.nix ];
  };

  iso = userIso.config.system.build.isoImage;
  isoName = "${userIso.config.image.baseName}.iso";

  qemuCommon = import "${inputs.nixpkgs}/nixos/lib/qemu-common.nix" {
    inherit (pkgs) lib stdenv;
  };

  # "omarchy". Generated, never typed:
  #   mkpasswd -m sha-512 -R 100000 -S nixarchytestsalt omarchy
  # A fixed hash, because `password=` salts randomly and the installed system
  # would be a different store path on every run. The hash is of the
  # PASSWORD, which has nothing to do with the account name.
  passwordHash = "$6$rounds=100000$nixarchytestsalt$zoz9HmOtqvELBidMdICVEOuvNl5LQCo.yhxsVpM6bgkeTdCG9D91zOaGX9Bu/YsQTlWLwuQF1SrOL0DY8Bu/V/";

  answersImage =
    pkgs.runCommand "nixarchy-reinstall-answers.img"
      {
        nativeBuildInputs = [
          pkgs.dosfstools
          pkgs.mtools
        ];
      }
      ''
        # <<'EOF', quoted: the hash is mostly dollar signs and an unquoted
        # heredoc hands them to the shell -- tests/install-iso.nix has the
        # incident.
        cat > answers <<'EOF'
        device=/dev/vda
        encrypt=no
        hostname=keep
        username=kepler
        password_hash=${passwordHash}
        timezone=UTC
        keymap=us
        EOF

        cat > drive <<'EOF'
        #!/bin/sh
        # Run by the test as `sudo sh /a/drive`. step() is install-iso's:
        # marker on the serial line whatever the exit code, output first,
        # install log tail on failure.
        step() {
          tag=$1
          shift
          "$@" > /tmp/got 2>&1
          rc=$?
          cat /tmp/got > /dev/ttyS0
          echo "$tag-$rc-X" > /dev/ttyS0
          [ $rc -eq 0 ] && return 0
          [ -f /var/log/nixarchy-install.log ] &&
            tail -80 /var/log/nixarchy-install.log > /dev/ttyS0
          exit 1
        }

        step STOPPED systemctl stop nixarchy-installer.service
        step MARKER test -f /etc/nixarchy-iso

        # The image names the USER'S toplevel as the system it carries.
        #
        # This is the interface assertion for the MISSING PIECE named in the
        # file header: today cd.nix hardcodes the reference toplevels here,
        # so this step FAILS -- deliberately, because everything after it is
        # only a reinstall check if the path the installer copies is the
        # user's machine. `-false` because answers say encrypt=no.
        step CARRIED sh -c '[ "$(tr -d "[:space:]" </etc/nixarchy-reference-false)" = "${userToplevel}" ]'

        step INSTALLED nixarchy-install --answers /a/answers

        # The copy path was taken, by name. install.sh prints this line only
        # on the baked-marker branch -- the one that arms `--max-jobs 0`, so
        # INSTALLED passing above already means nothing was built; this pins
        # WHICH system was copied to the exact store path this test built.
        step COPIED grep -qF "installing the system this image carries: ${userToplevel}" /var/log/nixarchy-install.log

        step FLAKE test -d /mnt/etc/nixos/.git
        step ESP test -d /mnt/boot/EFI

        # And nothing was fetched. The corrected assertion from
        # tests/install-iso.nix, verbatim, with its reasoning there: a
        # substituted path logs `copying path ... from 'https://...'`, and
        # "unable to download" means a fetch was ATTEMPTED AND FAILED --
        # evidence the machine is offline, not evidence something arrived --
        # except the unavoidable nix-cache-info probes.
        step OFFLINE sh -c '
          log=/var/log/nixarchy-install.log
          ! grep -qE "copying path .* from .https://" "$log" &&
          ! grep "unable to download" "$log" | grep -qv nix-cache-info
        '

        # Byte for byte: the system profile the machine will boot is the
        # toplevel the image carried -- not an equivalent rebuild of it.
        step SAME sh -c '[ "$(readlink -f /mnt/nix/var/nix/profiles/system)" = "${userToplevel}" ]'

        # And the bootloader entry hands the kernel that closure's init, so
        # the machine that boots below is that path and not merely a machine
        # whose profile points at it.
        step BOOTENTRY sh -c 'grep -q "${userToplevel}/init" /mnt/boot/loader/entries/*.conf'

        step FALLBACK test -f /mnt/boot/EFI/BOOT/BOOTX64.EFI

        # The installed desktop has no serial console by design; put one on
        # the kernel command line so the boot below is observable. No
        # rebuild, nothing built -- tests/install-iso.nix has the long form.
        sed -i '/^options /s|$| console=ttyS0,115200|' /mnt/boot/loader/entries/*.conf
        step SERIAL sh -c 'grep -q "console=ttyS0" /mnt/boot/loader/entries/*.conf'
        EOF

        truncate -s 1M $out
        mkfs.vfat -n NIXANSWERS $out
        mcopy -i $out answers ::answers
        mcopy -i $out drive ::drive
      '';

  commonFlags = [
    (qemuCommon.qemuBinary pkgs.qemu_test)
    "-m 8192 -smp 4"
    "-drive if=pflash,format=raw,unit=0,readonly=on,file=${pkgs.OVMF.firmware}"
    # No NIC at all: nothing for a retry to bring back up, nothing for a
    # passing result to be quietly explained by.
    "-nic none"
  ];

  # virtio-scsi, not qemu's default IDE CD -- GRUB fails partway through an
  # image this size on IDE; tests/install-iso.nix has the error text.
  installerCommand = pkgs.lib.concatStringsSep " " (
    commonFlags
    ++ [
      "-device virtio-scsi-pci,id=scsi0"
      "-drive id=cd0,if=none,media=cdrom,readonly=on,format=raw,file=${iso}/iso/${isoName}"
      "-device scsi-cd,bus=scsi0.0,drive=cd0,bootindex=0"
    ]
  );

  targetCommand = pkgs.lib.concatStringsSep " " commonFlags;
in
pkgs.testers.runNixOSTest {
  name = "nixarchy-reinstall-vm";

  # The driver must lose the race to the job, or a hang records as
  # `cancelled` and nothing reports it -- tests/install.nix has the incident.
  # The nightly job this belongs in gets timeout-minutes: 180 (the image
  # build dominates and happens before the driver starts); if that number
  # ever moves, this one moves with it and stays below.
  globalTimeout = 170 * 60;

  nodes = { };

  testScript = ''
    import os
    import shutil
    import subprocess
    import re
    import time

    # The EFI variable store: writable, and the SAME file for both machines,
    # so the boot entry the install writes is the one the target starts from.
    # tests/install-iso.nix documents what a read-only store cost.
    efi_vars = os.path.abspath("efi-vars.fd")
    shutil.copyfile("${pkgs.OVMF.variables}", efi_vars)
    os.chmod(efi_vars, 0o644)
    efi = f" -drive if=pflash,format=raw,unit=1,readonly=off,file={efi_vars}"

    # Machines made by create_machine are not reaped for us, and a failed
    # assertion leaves qemu running until the job's wall clock kills the
    # derivation -- silently. Hence the finally.
    vms = []

    def reap():
        for m in vms:
            try:
                m.send_monitor_command("quit")
            except Exception:
                pass

    try:
        disk = os.path.abspath("target.qcow2")
        subprocess.check_call(
            ["${pkgs.qemu_test}/bin/qemu-img", "create", "-f", "qcow2", disk, "24G"])

        drives = (
            f" -drive file={disk},if=virtio,format=qcow2,werror=report"
            " -drive file=${answersImage},if=virtio,format=raw,readonly=on")

        installer = create_machine("${installerCommand}" + efi + drives, name="installer")
        vms.append(installer)
        installer.start()

        # The image's own bootloader, kernel and store. Matched on the login
        # LINE: a prompt has no trailing newline and never matches.
        installer.wait_for_console_text(r"login: nixos \(automatic login\)", timeout=900)
        print("the user image booted, with no network device present")

        # tty1 is the installer TUI; tty2 has the autologin shell.
        # time.sleep, never machine.sleep -- there is no backdoor for the
        # latter to run `sleep` through.
        installer.send_key("alt-f2")
        time.sleep(8)
        installer.send_chars("\n")
        time.sleep(2)

        installer.send_chars("sudo mkdir -p /a\n")
        time.sleep(2)
        installer.send_chars("sudo mount -L NIXANSWERS /a\n")
        time.sleep(4)
        installer.send_chars("sudo sh /a/drive\n")

        def step(tag, timeout, note=None):
            # Wait for the marker WHATEVER its exit code, then read the code
            # out of the log -- waiting for `-0-X` alone turns every failure
            # into a timeout two minutes after the guest printed the reason.
            installer.wait_for_console_text(rf"{tag}-\d+-X", timeout=timeout)
            codes = re.findall(rf"{tag}-(\d+)-X", installer.get_console_log())
            if codes and codes[-1] != "0":
                raise Exception(
                    f"step {tag} exited {codes[-1]}; its output is above this line"
                )
            if note:
                print(note)

        step("STOPPED", 300, "the answers disk is mounted and the wizard is out of the way")
        step("MARKER", 120, "the image identifies itself to install.sh")
        step("CARRIED", 120,
             "the image names the USER'S toplevel as the system it carries")
        step("INSTALLED", 3600,
             "the install completed -- under --max-jobs 0, so nothing was built")
        step("COPIED", 120, "and what was copied is the user's machine, by store path")
        step("FLAKE", 120)
        step("ESP", 120, "it wrote a flake and an ESP")
        # 600: the passing case reads the whole install log -- every
        # `copying path` line of a multi-GB offline install, on an emulated
        # CPU -- so the scan lives inside the step and gets a real budget.
        step("OFFLINE", 600, "and downloaded nothing")
        step("SAME", 120,
             "the system profile is the image's toplevel, byte for byte")
        step("BOOTENTRY", 120, "and the boot entry hands the kernel that closure's init")
        step("FALLBACK", 120,
             "the ESP carries the removable fallback loader bootctl promises")
        step("SERIAL", 120,
             "the installed machine's own boot entry now names a serial console")

        # Typed, not shutdown(): no backdoor to send poweroff through.
        installer.send_chars("sudo poweroff\n")
        installer.wait_for_console_text(r"[Pp]ower(ing)? off|System is powering down|reboot: Power down",
                                        timeout=300)
        time.sleep(5)
        # Backstop before the target opens the same qcow2 -- qemu takes a
        # write lock on it.
        try:
            installer.send_monitor_command("quit")
        except Exception:
            pass
        time.sleep(3)

        # ---- boot what was reinstalled ------------------------------------
        target = create_machine(
            "${targetCommand}"
            + efi
            + f" -drive file={disk},if=virtio,format=qcow2,werror=report",
            name="target")
        vms.append(target)
        target.start()

        # Two waits at two layers, because they fail differently: the
        # bootloader's own menu line first, then a getty offering a login on
        # the serial console -- which takes the kernel, systemd and the
        # console the SERIAL step installed. The banner, never the login
        # prompt: a prompt has no trailing newline and never matches.
        target.wait_for_console_text(r"Reboot Into Firmware Interface", timeout=300)
        print("the bootloader the reinstall wrote is running, from the ESP it wrote")

        target.wait_for_console_text(r"<<< Welcome to NixOS .* - ttyS0 >>>", timeout=900)
        print("the closure the image carried booted to multi-user, offering a login")
    finally:
        reap()
  '';
}
