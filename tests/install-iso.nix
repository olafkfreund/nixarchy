{ inputs, pkgs }:
# Does the ISO install a desktop with no network?
#
# checks.install answers the same question from a test node that the framework
# handed the closure to. This one answers it from the artefact people actually
# download, with `-nic none`: not a disconnected interface, no interface at
# all, so there is nothing for a retry to bring back up and nothing for a
# passing result to be quietly explained by.
#
# The two halves fail in different places and are worth telling apart:
#
#   The SOURCES have to be on the image, or nix cannot evaluate the generated
#   flake and stops before copying anything. That reads as "unable to download
#   'https://github.com/...'", and it is asserted on its own below, with
#   `nix eval --offline`, because it is quick and it localises the failure.
#
#   The OUTPUTS have to be on it, or nixos-install has a desktop to assemble
#   and no parts. That reads as "cannot build ... hyprland".
#
# encrypt=no deliberately, and it is the interesting half. The image bakes
# both disk modes, but the encrypted one is what it would carry anyway, since
# the reference host defaults to it. Installing WITHOUT encryption is what
# proves the second variant is really there -- an image carrying only the
# reference installs an encrypted machine perfectly and dies partway through
# this one. It also keeps a passphrase prompt out of the boot path, which this
# test would otherwise have to answer on a screen it cannot read.
#
# No nodes. A test node boots through qemu's -kernel from the host store,
# which is exactly what must not happen here: the point is the image's own
# bootloader and the image's own store. The machines are built by hand, the
# way nixpkgs' own nixos/tests/boot.nix does it.
#
# ---------------------------------------------------------------------------
# Driving a machine with no backdoor
#
# The shipped image has no test instrumentation and no reason to carry any:
# succeed() and wait_for_unit() talk to a root shell on /dev/hvc0 that only
# testing/test-instrumentation.nix provides. So the guest is driven the way a
# person would drive it, and the two directions go to different places:
#
#   send_chars types on the VIRTUAL KEYBOARD, reaching whichever VT is in
#   front. The installer TUI owns tty1, so this switches to tty2, where the
#   image leaves an autologin shell.
#
#   wait_for_console_text reads the SERIAL line, which tty2 does not write to.
#
# So everything the guest has to do lives in one script on the answers disk,
# which echoes a marker to /dev/ttyS0 after each step, and the test types one
# short command to start it. Typing more than that does not work: at one
# keystroke per 10ms, a two-hundred-character line of shell holding a crypt
# hash drops a character often enough to matter, and the result is not an
# error -- it is an unterminated quote, a shell waiting for the rest of the
# line, and a test waiting for a marker that will never come.
let
  iso = inputs.self.nixosConfigurations.iso.config.system.build.isoImage;
  isoName = "${inputs.self.nixosConfigurations.iso.config.image.baseName}.iso";

  # The same helper nixpkgs' boot tests use to pick a qemu binary, rather than
  # hardcoding qemu-system-x86_64 and losing KVM.
  qemuCommon = import "${inputs.nixpkgs}/nixos/lib/qemu-common.nix" {
    inherit (pkgs) lib stdenv;
  };

  # This is "omarchy". Generated, never typed:
  #
  #   mkpasswd -m sha-512 -R 100000 -S nixarchytestsalt omarchy
  #
  # A fixed hash rather than a plaintext password, because `password=` makes
  # the installer call mkpasswd, which salts randomly, and the installed
  # system would be a different store path on every run.
  passwordHash = "$6$rounds=100000$nixarchytestsalt$zoz9HmOtqvELBidMdICVEOuvNl5LQCo.yhxsVpM6bgkeTdCG9D91zOaGX9Bu/YsQTlWLwuQF1SrOL0DY8Bu/V/";

  # Everything the guest does, on a disk it can mount.
  #
  # Each step echoes "<name>-<status>-X" to the serial line and the test waits
  # for the zero; a non-zero status never matches, so the wait times out and
  # the step's own output is already on the console above it. That tee is not
  # decoration: on a test whose interesting part is twenty minutes in, seeing
  # why a step failed rather than only that it failed is worth three runs.
  answersImage =
    pkgs.runCommand "nixarchy-test-answers.img"
      {
        nativeBuildInputs = [
          pkgs.dosfstools
          pkgs.mtools
        ];
      }
      ''
        # <<'EOF', quoted. Nix interpolates ${passwordHash} into this script
        # before any shell sees it, and a crypt hash is mostly dollar signs --
        # so an unquoted heredoc hands $6$rounds to the SHELL, which expands
        # each one to nothing and writes a password_hash of "100000". The
        # installer catches it ("not a crypt(3) hash"), which is the only
        # reason this was a one-line fix rather than a mystery about why the
        # greeter rejects the password.
        cat > answers <<'EOF'
        device=/dev/vda
        encrypt=no
        hostname=isotest
        username=omarchy
        password_hash=${passwordHash}
        timezone=UTC
        keymap=us
        EOF

        cat > drive <<'EOF'
        #!/bin/sh
        # Run by the test as `sudo sh /a/drive`, as root: every step needs it,
        # and asking once beats a sudo on every line.
        step() {
          tag=$1
          shift
          "$@" > /tmp/out 2>&1
          rc=$?
          cat /tmp/out > /dev/ttyS0
          echo "$tag-$rc-X" > /dev/ttyS0
          [ $rc -eq 0 ] && return 0
          # The installer hides its output behind a progress bar on purpose,
          # so its stdout is a picture of a dashboard and its log is where the
          # reason lives. Dump the tail of it, or a failure here is a screen
          # saying "the whole log is at /var/log/nixarchy-install.log" on a
          # machine that is about to be destroyed.
          [ -f /var/log/nixarchy-install.log ] &&
            tail -80 /var/log/nixarchy-install.log > /dev/ttyS0
          exit 1
        }

        # The wizard owns tty1 and would race the install. --answers is the
        # same code path with the questions already answered.
        step STOPPED systemctl stop nixarchy-installer.service

        # The marker installer/cd.nix writes, which install.sh reads to decide
        # it must not reach for a substituter.
        step MARKER test -f /etc/nixarchy-iso

        # --dry-run writes the flake and touches no disk, so the evaluation
        # below can be asserted before anything is destroyed.
        step GENERATED nixarchy-install --dry-run --answers /a/answers
        cp /tmp/out /tmp/dry
        work=$(tail -1 /tmp/dry)

        # --offline turns an attempted fetch into an error rather than a hang,
        # which is the behaviour worth asserting: it fails loudly if a locked
        # input is resolved over the network instead of from the store.
        step EVALUATED nix eval --offline --raw "$work#nixosConfigurations.isotest.config.system.build.toplevel.drvPath"

        grep -q -- -nixos-system-isotest /tmp/out
        step RESOLVED test $? -eq 0

        step INSTALLED nixarchy-install --answers /a/answers

        # Asserted while the target is still mounted: it localises a failure to
        # "the install" rather than "the boot", which are different bugs.
        step FLAKE test -d /mnt/etc/nixos/.git
        step ESP test -d /mnt/boot/EFI

        # And nothing was fetched. The image carries no substituter and the
        # machine has no interface, so a download here would mean every
        # assertion above is measuring something other than what it claims.
        grep -q "unable to download" /var/log/nixarchy-install.log
        step OFFLINE test $? -ne 0
        EOF

        truncate -s 1M $out
        mkfs.vfat -n NIXANSWERS $out
        mcopy -i $out answers ::answers
        mcopy -i $out drive ::drive
      '';

  # Both pflash drives. Without unit=1 the firmware has nowhere to keep EFI
  # variables, and a machine that cannot write them is a different machine
  # from the one a person installs onto.
  commonFlags = [
    (qemuCommon.qemuBinary pkgs.qemu_test)
    "-m 8192 -smp 4"
    "-drive if=pflash,format=raw,unit=0,readonly=on,file=${pkgs.OVMF.firmware}"
    "-drive if=pflash,format=raw,unit=1,readonly=on,file=${pkgs.OVMF.variables}"
    # No NIC at all. Bringing an interface down inside the guest leaves
    # something a retry could bring back up; this leaves nothing.
    "-nic none"
  ];

  # The image on a virtio-scsi CD, not qemu's default IDE one.
  #
  # On IDE, GRUB gets partway through this image and stops with
  #
  #   error: failure reading sector 0x46c0 from `cd0'
  #   error: you need to load the kernel first
  #
  # which looks like a corrupt ISO and is not: the same file boots from AHCI
  # or, as here, from virtio-scsi. Worth knowing before someone rebuilds a
  # 5.6 GiB image three times looking for the corruption.
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
  name = "nixarchy-install-iso";

  nodes = { };

  testScript = ''
    import os
    import subprocess
    import time

    # A blank disk for the install to land on, made here rather than by
    # virtualisation.emptyDiskImages: there is no node to hang that off.
    disk = os.path.abspath("target.qcow2")
    subprocess.check_call(
        ["${pkgs.qemu_test}/bin/qemu-img", "create", "-f", "qcow2", disk, "24G"])

    drives = (
        f" -drive file={disk},if=virtio,format=qcow2,werror=report"
        " -drive file=${answersImage},if=virtio,format=raw,readonly=on")

    installer = create_machine("${installerCommand}" + drives, name="installer")
    installer.start()

    # The image's own bootloader, its own kernel, its own store.
    #
    # Matched on the login line, not the shell prompt: a prompt is written
    # without a trailing newline, and wait_for_console_text works in lines, so
    # waiting for "nixos@nixos" waits for whatever happens to print next --
    # which, on an idle installer, is nothing at all.
    installer.wait_for_console_text(r"login: nixos \(automatic login\)", timeout=900)
    print("the ISO booted, with no network device present")

    # tty1 belongs to the installer TUI; tty2 has the autologin shell.
    #
    # time.sleep, not machine.sleep: the latter sleeps in GUEST time by running
    # `sleep` through the backdoor shell, which this image does not have, so it
    # blocks forever on "waiting for the VM to finish booting" while the
    # machine sits there perfectly booted.
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
        installer.wait_for_console_text(rf"{tag}-0-X", timeout=timeout)
        if note:
            print(note)

    step("STOPPED", 300, "the answers disk is mounted and the wizard is out of the way")
    step("MARKER", 120, "the image identifies itself to install.sh")
    step("GENERATED", 900, "the flake was generated")
    step("EVALUATED", 1800)
    step("RESOLVED", 120,
         "the generated flake evaluates offline, from sources on the image")
    step("INSTALLED", 3600, "the install completed")
    step("FLAKE", 120)
    step("ESP", 120, "it wrote a flake and an ESP")
    step("OFFLINE", 120, "and downloaded nothing")

    # Typed, not shutdown(). Machine.shutdown() sends poweroff through the
    # backdoor shell, which this image does not have, so it waits for a reply
    # that cannot come -- the install passes, every assertion passes, and the
    # test still fails when nix's build timeout kills it half an hour later.
    installer.send_chars("sudo poweroff\n")
    installer.wait_for_console_text(r"[Pp]ower(ing)? off|System is powering down|reboot: Power down",
                                    timeout=300)
    time.sleep(5)
    # A backstop for a machine that did not power off, and nothing more. When
    # poweroff DID work the monitor socket is already gone and this raises
    # BrokenPipeError -- failing the test on the cleanest possible outcome.
    try:
        installer.send_monitor_command("quit")
    except Exception:
        pass
    time.sleep(3)

    # ---- boot what was installed ---------------------------------------
    target = create_machine(
        "${targetCommand}"
        + f" -drive file={disk},if=virtio,format=qcow2,werror=report",
        name="target")
    target.start()
    target.wait_for_console_text(r"isotest login:", timeout=900)
    print("the installed disk booted on its own bootloader")

    # Kill it at the monitor, or this check never finishes.
    #
    # A machine made by create_machine is not reaped for us the way a declared
    # node is: the script reaches its end with every assertion passing and the
    # derivation then sits there forever with a qemu still running. That is
    # not a hypothesis -- checks.install did exactly this for nine hours, and
    # it presents as `cancelled` in CI because a timeout is recorded as a
    # cancellation, which reads like a person stopped it rather than like a
    # hang.
    #
    # `quit`, not shutdown(): this machine has no backdoor, which is why the
    # line above waits on console text rather than asking it anything. Same
    # treatment the installer machine gets above, and the same try/except --
    # if qemu is already gone the monitor socket is gone with it.
    try:
        target.send_monitor_command("quit")
    except Exception:
        pass
  '';
}
