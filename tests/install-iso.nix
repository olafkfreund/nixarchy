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

        # The removable fallback, asserted rather than taken on trust.
        #
        # bootctl(1) says `install` always stores a copy of the loader at
        # ESP/EFI/BOOT/BOOT*.EFI, and the note beside the pflash drives leans
        # on that to explain why a target with an empty NVRAM still boots. A
        # promise in a man page about a program we do not build is exactly the
        # kind of thing that is true until it is not, and the failure mode if
        # it changes is a machine that boots on this test's shared variable
        # store and not on a stranger's laptop.
        step FALLBACK test -f /mnt/boot/EFI/BOOT/BOOTX64.EFI

        # ---- make the result observable ---------------------------------
        # Everything above is the product, installed and untouched. What
        # follows adds a serial console to it and nothing else.
        #
        # It has to be added, because the installed machine has none:
        # installer/cd.nix puts console=ttyS0 on the ISO's command line, which
        # is why every step above could be read off the serial line, and
        # installer/host.nix deliberately does not -- an installed desktop
        # logs to its screen. So `isotest login:` was being waited for on a
        # line nothing would ever write it to, and this check timed out at
        # 900s for three nightly runs while the machine under it booted
        # perfectly.
        #
        # NOT OCR (enableOCR + wait_for_text), which was the other candidate:
        # it answers the same question less reliably, and #197 is putting an
        # animated plymouth splash on that screen -- frames drawn by ttfx --
        # which is precisely what an OCR pass would have to see past.
        #
        # The last line of the generated configuration.nix is its closing
        # brace; this puts one option in front of it.
        sed -i '$s|^}|  boot.kernelParams = [ "console=ttyS0,115200" ];\n}|' \
          /mnt/etc/nixos/hosts/isotest/configuration.nix
        grep -q 'console=ttyS0' /mnt/etc/nixos/hosts/isotest/configuration.nix
        step SERIAL test $? -eq 0

        # A flake in a git worktree sees only tracked or staged files.
        git -C /mnt/etc/nixos add -A

        # Built HERE and installed by path, which is what run_install() in
        # installer/install.sh does and for the reason its comment gives:
        # `nixos-install --flake` sets the EVALUATION store to /mnt, resolves
        # the flake's locked inputs against a store that has just been created,
        # and goes to the network for sources sitting in the store one
        # directory up. checks.install can use --flake because its store was
        # seeded by the test driver; an ISO is in the other position.
        #
        # --offline so that if this ever does reach for the network it says so
        # instead of hanging: no network is the whole point of this check.
        #
        # This is the case installer/cd.nix bakes the reference
        # inputDerivations for -- a toplevel that differs from the one on the
        # image has to be BUILT here, from parts, with no stdenv to fetch. If
        # this step ever ends in the source bootstrap, that list is where the
        # answer is.
        step REBUILT nix --extra-experimental-features "nix-command flakes" \
          build --offline --no-link --print-out-paths \
          --option always-allow-substitutes true \
          /mnt/etc/nixos#nixosConfigurations.isotest.config.system.build.toplevel
        system=$(tail -1 /tmp/out)

        # Because `tail -1` is a guess about what nix printed last, and a bad
        # guess would otherwise surface as nixos-install reporting something
        # unrelated about a flake it cannot find.
        step SYSTEM test -x "$system/init"

        step REINSTALLED nixos-install --root /mnt --system "$system" \
          --no-root-password \
          --option extra-experimental-features "nix-command flakes"
        EOF

        truncate -s 1M $out
        mkfs.vfat -n NIXANSWERS $out
        mcopy -i $out answers ::answers
        mcopy -i $out drive ::drive
      '';

  # Only unit=0, the firmware, which is genuinely read-only. The EFI VARIABLE
  # store is unit=1 and is deliberately not here: it has to be one writable
  # file shared by both machines, and a store path is neither writable nor
  # known at evaluation time. The test script copies it into the working
  # directory and hands the flag to both create_machine calls; see there for
  # what a read-only variable store cost us.
  commonFlags = [
    (qemuCommon.qemuBinary pkgs.qemu_test)
    "-m 8192 -smp 4"
    "-drive if=pflash,format=raw,unit=0,readonly=on,file=${pkgs.OVMF.firmware}"
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
    import shutil
    import subprocess
    import time

    # The EFI variable store: writable, and the SAME FILE for both machines.
    #
    # installer/host.nix sets boot.loader.efi.canTouchEfiVariables, so
    # `bootctl install` writes a boot entry to NVRAM during the install. This
    # drive was readonly=on, which threw that write away, and the target then
    # started from the pristine OVMF template as if the install had never
    # touched it. The console says which machine you are looking at:
    #
    #   readonly=on   BdsDxe: starting Boot0002 "UEFI Misc Device"
    #                   from PciRoot(0x0)/Pci(0x5,0x0)
    #   readonly=off  BdsDxe: starting Boot0004 "Linux Boot Manager"
    #                   from HD(1,GPT,...)/\EFI\systemd\systemd-bootx64.efi
    #
    # DO NOT read this as the reason the target used to sit silent for 900s.
    # It is not, and an hour of runtime was spent proving that: both lines
    # above are a successful LoadImage, because `bootctl install` ALWAYS
    # writes the removable fallback at \EFI\BOOT\BOOTX64.EFI (bootctl(1)),
    # so the firmware's own "UEFI Misc Device" entry boots the disk with no
    # NVRAM entry at all. checks.install passes today on exactly that path.
    # What the readonly store cost was fidelity, not a boot: the machine
    # under test was one whose firmware forgets, which is not the machine a
    # person installs onto.
    #
    # Copied out of the store because ${pkgs.OVMF.variables} is a read-only
    # path -- the same thing nixpkgs' own qemu-vm.nix does for NIX_EFI_VARS.
    efi_vars = os.path.abspath("efi-vars.fd")
    shutil.copyfile("${pkgs.OVMF.variables}", efi_vars)
    os.chmod(efi_vars, 0o644)
    efi = f" -drive if=pflash,format=raw,unit=1,readonly=off,file={efi_vars}"

    # Every machine this script makes, and the single place they are killed.
    #
    # A machine made by create_machine is not reaped for us the way a declared
    # node is -- and the happy path is not the one that matters. When an
    # assertion fails the driver stops running this script where it stands,
    # the qemu processes stay up, and the derivation hangs until the JOB's
    # wall clock kills it. GitHub records that as `cancelled`, not `failed`,
    # and nightly.yml's reporter is `if: failure()` -- so the nights of
    # 2026-09-02 and 2026-09-03 both broke here, hung for three hours, and
    # told nobody. A hang is not just slow; it is SILENT, and that is the part
    # worth remembering. checks.install did the same thing for nine hours
    # before anyone noticed.
    #
    # Hence a finally, rather than a `quit` after the last assertion, which is
    # what this file did before and which only ever ran when nothing was
    # wrong.
    #
    # `quit`, not shutdown(): these machines have no backdoor, which is why
    # every wait below is on console text rather than a question put to the
    # guest. If qemu is already gone -- the usual outcome, poweroff having got
    # there first -- the monitor socket went with it and this raises
    # BrokenPipeError, which would otherwise fail the test on the cleanest
    # possible outcome.
    # `vms`, not `machines`: the driver already has a global of that name, and
    # shadowing it fails the test's own type check ("Object of type
    # `BaseMachine` has no attribute `send_monitor_command`") rather than
    # anything you would recognise as a name clash.
    vms = []

    def reap():
        for m in vms:
            try:
                m.send_monitor_command("quit")
            except Exception:
                pass

    try:
        # A blank disk for the install to land on, made here rather than by
        # virtualisation.emptyDiskImages: there is no node to hang that off.
        disk = os.path.abspath("target.qcow2")
        subprocess.check_call(
            ["${pkgs.qemu_test}/bin/qemu-img", "create", "-f", "qcow2", disk, "24G"])

        drives = (
            f" -drive file={disk},if=virtio,format=qcow2,werror=report"
            " -drive file=${answersImage},if=virtio,format=raw,readonly=on")

        installer = create_machine("${installerCommand}" + efi + drives, name="installer")
        vms.append(installer)
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
        step("FALLBACK", 120,
             "the ESP carries the removable fallback loader bootctl promises")
        step("SERIAL", 120)
        step("REBUILT", 1800)
        step("SYSTEM", 120)
        step("REINSTALLED", 1800,
             "the installed flake now carries a serial console, built offline")

        # Typed, not shutdown(). Machine.shutdown() sends poweroff through the
        # backdoor shell, which this image does not have, so it waits for a reply
        # that cannot come -- the install passes, every assertion passes, and the
        # test still fails when nix's build timeout kills it half an hour later.
        installer.send_chars("sudo poweroff\n")
        installer.wait_for_console_text(r"[Pp]ower(ing)? off|System is powering down|reboot: Power down",
                                        timeout=300)
        time.sleep(5)
        # A backstop for a machine that did not power off, here and not left to
        # reap(): the target is about to open the same qcow2, and qemu takes a
        # write lock on it. An installer still running would make that a
        # "Failed to get write lock" at the very step this test exists for.
        try:
            installer.send_monitor_command("quit")
        except Exception:
            pass
        time.sleep(3)

        # ---- boot what was installed ---------------------------------------
        target = create_machine(
            "${targetCommand}"
            + efi
            + f" -drive file={disk},if=virtio,format=qcow2,werror=report",
            name="target")
        vms.append(target)
        target.start()

        # Two waits, at two layers, because they fail differently and a run
        # that only ever asserted the second one left you to bisect which half
        # broke.
        #
        # The menu, not an entry title: with one generation sd-boot titles the
        # entry "NixOS" and with two it spells out the generation, so the
        # titles are a moving target while the menu's own line is not.
        target.wait_for_console_text(r"Reboot Into Firmware Interface", timeout=300)
        print("the bootloader the installer wrote is running, from the ESP it wrote")

        # The getty's BANNER, not "isotest login:", and this one was paid for
        # twice. wait_for_console_text splits the serial stream on newlines
        # (`for _line in self.process.stdout` in the driver's Machine), and a
        # login prompt is written without a trailing one -- so it sits in the
        # reader's buffer forever and the wait times out beside a machine that
        # is sitting at a login prompt. The note on the installer's wait above
        # says exactly this and it still cost a run here: the give-away in that
        # log is `target # isotest login:` appearing AFTER cleanup killed qemu,
        # which flushed the partial line.
        #
        # agetty writes the issue before the prompt, and \l expands to the tty
        # it is running on, so this line is not merely "userspace printed
        # something": it is a getty offering a login ON THE SERIAL LINE, which
        # takes the kernel, systemd's multi-user target and the serial console
        # the step above installed.
        target.wait_for_console_text(r"<<< Welcome to NixOS .* - ttyS0 >>>", timeout=900)
        print("and the system it installed reached multi-user, offering a login")
    finally:
        reap()
  '';
}
