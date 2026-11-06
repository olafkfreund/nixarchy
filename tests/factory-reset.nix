{ inputs, pkgs }:
# Why: tests/AGENTS.md#factory-reset
let
  inherit (pkgs.extend inputs.self.overlays.default) omarchy;
  resetCommand = pkgs.runCommand "omarchy-system-factory-reset" { } ''
    mkdir -p $out/bin
    install -m755 ${omarchy}/share/omarchy/bin/omarchy-system-factory-reset $out/bin/omarchy-system-factory-reset
  '';
  exchWrapper = pkgs.writeShellScriptBin "exch" ''
    calls=$(cat /run/test-exch-calls 2>/dev/null || echo 0)
    calls=$((calls + 1))
    printf '%s\n' "$calls" > /run/test-exch-calls
    if [ -e /test-control/exch-fail-from ] && [ "$calls" -ge "$(cat /test-control/exch-fail-from)" ]; then
      echo "injected exch failure on call $calls" >&2
      exit 1
    fi
    exec ${pkgs.util-linux}/bin/exch "$@"
  '';
  dateWrapper = pkgs.writeShellScriptBin "date" ''
    if [ -e /test-control/date ]; then
      cat /test-control/date
    else
      exec ${pkgs.coreutils}/bin/date "$@"
    fi
  '';
in
pkgs.testers.runNixOSTest {
  name = "nixarchy-factory-reset";

  nodes.machine = {
    imports = [ ../installer/factory-reset.nix ];
    systemd.services.nixarchy-factory-reset.path = pkgs.lib.mkBefore [
      exchWrapper
      dateWrapper
    ];
    virtualisation = {
      useDefaultFilesystems = false;
      rootDevice = "/dev/vda";
      diskSize = 2048;
      memorySize = 1024;
      fileSystems = {
        "/" = {
          device = "/dev/disk/by-label/storage";
          fsType = "btrfs";
          options = [ "subvol=@" ];
        };
        "/home" = {
          device = "/dev/disk/by-label/storage";
          fsType = "btrfs";
          options = [ "subvol=@home" ];
        };
      };
    };
    systemd.repart.partitions."00-root" = {
      Type = "linux-generic";
      Format = "btrfs";
      Label = "storage";
      Subvolumes = [
        "/@"
        "/@home"
      ];
      MakeDirectories = [
        "/@"
        "/@home"
      ];
    };
    boot.initrd.supportedFilesystems = [ "btrfs" ];
    boot.initrd.systemd.repart = {
      enable = true;
      device = "/dev/vda";
      empty = "allow";
    };
    users.users.omarchy = {
      isNormalUser = true;
      extraGroups = [ "wheel" ];
    };
    environment.etc."nixarchy/managed".text = "";
    security.sudo.wheelNeedsPassword = false;
    environment.systemPackages = [
      pkgs.btrfs-progs
      pkgs.e2fsprogs
      pkgs.git
      pkgs.gum
      resetCommand
    ];
  };

  testScript = ''
    machine.wait_for_unit("multi-user.target")
    root = machine.succeed("findmnt -no SOURCE --mountpoint /").strip()
    home = machine.succeed("findmnt -no SOURCE --mountpoint /home").strip()
    assert root.endswith("[/@]"), root
    assert home.endswith("[/@home]"), home

    machine.succeed("printf old > /home/spike-sentinel")
    machine.succeed("mkdir /top && mount -o subvol=/ /dev/disk/by-label/storage /top")
    machine.succeed("btrfs subvolume snapshot -r /top/@home /top/@spike-ro")
    machine.succeed("btrfs subvolume snapshot /top/@spike-ro /top/@spike")
    machine.succeed("printf new > /top/@spike/spike-sentinel")

    machine.succeed("umount /home")
    machine.succeed("exch /top/@home /top/@spike")
    machine.succeed("mount /home")
    assert machine.succeed("cat /home/spike-sentinel").strip() == "new"
    assert machine.succeed("cat /top/@spike/spike-sentinel").strip() == "old"
    machine.succeed("umount /top")

    machine.shutdown()
    machine.start()
    machine.wait_for_unit("multi-user.target")
    assert machine.succeed("cat /home/spike-sentinel").strip() == "new"
    machine.succeed("mount -o subvol=/ /dev/disk/by-label/storage /top")
    machine.succeed("umount /home")
    machine.succeed("exch /top/@home /top/@spike")
    machine.succeed("mount /home")
    assert machine.succeed("cat /home/spike-sentinel").strip() == "old"

    machine.succeed("printf old > /var/lib/spike-sentinel")
    machine.succeed("mkdir /var/lib.spike && printf new > /var/lib.spike/spike-sentinel")
    machine.succeed("exch /var/lib /var/lib.spike")
    assert machine.succeed("cat /var/lib/spike-sentinel").strip() == "new"
    assert machine.succeed("cat /var/lib.spike/spike-sentinel").strip() == "old"
    machine.succeed("exch /var/lib /var/lib.spike")

    machine.succeed("btrfs subvolume delete /top/@spike /top/@spike-ro")
    machine.succeed("rm /var/lib.spike/spike-sentinel /var/lib/spike-sentinel /home/spike-sentinel")
    machine.succeed("rmdir /var/lib.spike")

    machine.succeed("btrfs subvolume snapshot -r /top/@ /top/@factory")
    machine.succeed("btrfs subvolume snapshot -r /top/@home /top/@factory-home")
    machine.succeed("umount /top && rmdir /top")

    def boot():
        machine.shutdown()
        machine.start()
        machine.wait_for_unit("multi-user.target")

    def top():
        machine.succeed("mkdir -p /top && mount -o subvol=/ /dev/disk/by-label/storage /top")

    def untop():
        machine.succeed("umount /top && rmdir /top")

    def arm(name, fail_from=None):
        machine.succeed("mkdir -p /test-control /var/lib/nixarchy")
        machine.succeed(f"printf '%s\\n' {name} > /test-control/date")
        machine.succeed("rm -f /run/test-exch-calls /test-control/exch-fail-from")
        if fail_from is not None:
            machine.succeed(f"printf '%s\\n' {fail_from} > /test-control/exch-fail-from")
        machine.succeed("install -m 600 /dev/null /var/lib/nixarchy/factory-reset.request")
        boot()

    # Not ConditionResult: local-fs.target re-queues the unit once the request has gone,
    # so that field reads "no" after a run as well as instead of one.
    def unit_ran(result):
        log = journal()
        assert "Starting Restore /home" in log, log
        if result == "success":
            assert "Finished Restore /home" in log, log
        else:
            assert "Failed with result" in log, log

    def journal():
        return machine.succeed("journalctl -b -u nixarchy-factory-reset.service --no-pager")

    def failed(first):
        report = machine.succeed("cat /var/lib/nixarchy/factory-reset.failed")
        assert report.splitlines()[0] == first, report
        unit_ran("exit-code")
        return report

    def old():
        assert machine.succeed("cat /home/reset-sentinel").strip() == "old-home"
        assert machine.succeed("cat /var/lib/reset-sentinel").strip() == "old-var"

    def clean():
        machine.succeed("rm -f /var/lib/nixarchy/factory-reset.failed /test-control/date /test-control/exch-fail-from /run/test-exch-calls")
        machine.succeed("printf old-home > /home/reset-sentinel")
        machine.succeed("printf old-var > /var/lib/reset-sentinel")

    machine.succeed("mkdir -p /etc/nixos && printf keep > /etc/nixos/reset-sentinel")
    clean()

    # 1: successful reset, including the receipt's own recovery commands.
    arm("case1")
    unit_ran("success")
    assert "phase=done" in journal()
    machine.fail("test -e /home/reset-sentinel")
    machine.fail("test -e /var/lib/reset-sentinel")
    machine.fail("test -e /var/lib/nixarchy/factory-reset.failed")
    assert machine.succeed("cat /etc/nixos/reset-sentinel").strip() == "keep"
    receipt = machine.succeed("cat /var/lib/nixarchy/factory-reset.done")
    assert "@home-before-reset-case1" in receipt and "/var/lib.before-reset-case1" in receipt
    assert "ls /mnt/@home-before-reset-case1" in receipt
    for command in receipt.split("To read the old home directory:\n", 1)[1].splitlines()[1:4]:
        output = machine.succeed(command.strip())
        if command.strip().startswith("ls "):
            assert "reset-sentinel" in output, output
    assert machine.succeed("cat /var/lib.before-reset-case1/reset-sentinel").strip() == "old-var"
    machine.fail("test -e /var/lib.before-reset-case1/nixarchy/factory-reset.failed")
    machine.succeed("umount /mnt")

    # 11: occupied names are a guard failure, never staged data to remove.
    clean()
    top()
    machine.succeed("mkdir /var/lib.before-reset-case11 && printf keep > /var/lib.before-reset-case11/guard-sentinel")
    machine.succeed("btrfs subvolume snapshot /top/@home /top/@home-before-reset-case11")
    machine.succeed("printf keep > /top/@home-before-reset-case11/guard-sentinel")
    untop()
    arm("case11")
    assert "checking the names are free" in journal()
    failed("nothing changed")
    old()
    assert machine.succeed("cat /var/lib.before-reset-case11/guard-sentinel").strip() == "keep"
    top()
    assert machine.succeed("cat /top/@home-before-reset-case11/guard-sentinel").strip() == "keep"
    machine.succeed("btrfs subvolume delete /top/@home-before-reset-case11")
    untop()
    machine.succeed("rm -rf /var/lib.before-reset-case11")

    # 11b: -e misses a dangling symlink, but the guard must retain it.
    clean()
    machine.succeed("ln -s /missing /var/lib.before-reset-case11b")
    arm("case11b")
    assert "checking the names are free" in journal()
    failed("nothing changed")
    old()
    machine.succeed("test -L /var/lib.before-reset-case11b")
    machine.succeed("rm /var/lib.before-reset-case11b")

    # 6: a plain directory cannot stand in for the factory home subvolume.
    clean()
    top()
    machine.succeed("mv /top/@factory-home /top/@factory-home.saved && mkdir /top/@factory-home")
    untop()
    arm("case6")
    assert "@factory-home is not a subvolume" in journal()
    report = failed("nothing changed")
    assert "Failed while checking @factory-home" in report, report
    assert "copying the factory" not in journal()
    old()
    top()
    machine.succeed("rmdir /top/@factory-home && mv /top/@factory-home.saved /top/@factory-home")
    untop()

    # 2: the copy fails before either exchange, then cannot retry on next boot.
    clean()
    machine.succeed("chattr +i /var")
    arm("case2")
    log = journal()
    assert "cp:" in log and "copying the factory /var/lib" in log, log
    failed("nothing changed")
    old()
    machine.succeed("chattr -i /var")
    boot()
    assert "Starting Restore /home" not in journal(), journal()
    old()

    # 10: the command elevates before reading the root-only failure record.
    status, output = machine.execute("runuser -u omarchy -- omarchy-system-factory-reset")
    assert status == 1 and "The last factory reset did not finish." in output, (status, output)
    assert output.index("The last factory reset did not finish.") < output.index("nothing changed"), output
    machine.fail("test -e /var/lib/nixarchy/factory-reset.request")
    status, output = machine.execute("omarchy-system-factory-reset --check")
    assert status == 0 and output == "", (status, output)
    machine.succeed("truncate -s 0 /var/lib/nixarchy/factory-reset.failed")
    status, output = machine.execute("runuser -u omarchy -- omarchy-system-factory-reset")
    assert status == 1 and "left no reason" in output, (status, output)
    machine.fail("test -e /var/lib/nixarchy/factory-reset.request")

    # 3: the snapshot fails after copy, and stage cleanup removes both names.
    clean()
    top()
    machine.succeed("chattr +i /top")
    untop()
    arm("case3")
    log = journal()
    assert "snapshotting @factory-home" in log and "Could not create subvolume" in log, log
    failed("nothing changed")
    old()
    machine.fail("test -e /var/lib.before-reset-case3")
    top()
    machine.fail("test -e /top/@home-before-reset-case3")
    machine.succeed("chattr -i /top")
    untop()

    # 4: the second exchange fails; the first must be rolled back.
    clean()
    machine.succeed("chattr +i /var/lib")
    arm("case4")
    log = journal()
    assert "phase=home-swapped" in log and "exchanging /var/lib" in log and "exch:" in log, log
    failed("rolled back")
    old()
    machine.succeed("chattr -i /var/lib")

    # 7: the real kernel refuses the baseline query to an unprivileged user.
    machine.fail("runuser -u omarchy -- btrfs subvolume list -r /")

    # 5: the second exchange and rollback both fail; run the printed repair.
    clean()
    arm("case5", fail_from=2)
    log = journal()
    assert "phase=home-swapped" in log and "injected exch failure on call 2" in log, log
    assert "injected exch failure on call 3" in log, log
    report = failed("rollback failed")
    assert "@home-before-reset-case5" in report, report
    assert machine.succeed("cat /var/lib/reset-sentinel").strip() == "old-var"
    top()
    assert machine.succeed("cat /top/@home-before-reset-case5/reset-sentinel").strip() == "old-home"
    untop()
    repair = report.split("To repair:\n", 1)[1].split("Then @home-before", 1)[0].splitlines()
    for command in repair:
        if command.strip() == "systemctl reboot":
            break
        machine.succeed(command.strip().split("    #", 1)[0])
    boot()
    old()
    machine.fail("test -e /var/lib/nixarchy/factory-reset.failed")
    for command in report.split("Then @home-before", 1)[1].splitlines()[1:]:
        if command.strip().startswith("sudo "):
            machine.succeed(command.strip())
    machine.succeed("umount /mnt")

    # 12: a failed first exchange cleans the staged directory and subvolume.
    clean()
    arm("case12", fail_from=1)
    log = journal()
    assert "injected exch failure on call 1" in log and "exchanging @home" in log, log
    failed("nothing changed")
    old()
    machine.fail("test -e /var/lib.before-reset-case12")
    top()
    machine.fail("test -e /top/@home-before-reset-case12")
    untop()

    # 8: an unprivileged check stays quiet; an interactive run elevates.
    clean()
    status, output = machine.execute("runuser -u omarchy -- omarchy-system-factory-reset --check")
    assert status == 3 and output == "", (status, output)
    machine.succeed("chown omarchy:users /etc/nixos")
    machine.succeed("runuser -u omarchy -- git -C /etc/nixos init")
    machine.succeed("runuser -u omarchy -- git -C /etc/nixos add reset-sentinel")
    machine.succeed("runuser -u omarchy -- git -C /etc/nixos -c user.name=Test -c user.email=test@example.invalid commit -m initial")
    machine.succeed("mkdir -p /test-control/fake-bin")
    machine.succeed("printf '#!/bin/sh\\ntouch /tmp/factory-reset-fake-gum\\nexit 1\\n' > /test-control/fake-bin/gum && chmod +x /test-control/fake-bin/gum")
    status, output = machine.execute("runuser -u omarchy -- sh -c 'PATH=/test-control/fake-bin:/run/wrappers/bin:/run/current-system/sw/bin omarchy-system-factory-reset'")
    assert status == 0 and "Factory reset" in output and "first commit" in output, (status, output)
    machine.fail("test -e /var/lib/nixarchy/factory-reset.request")
    machine.fail("test -e /tmp/factory-reset-fake-gum")
    machine.succeed("install -m755 /run/current-system/sw/bin/omarchy-system-factory-reset /tmp/factory-reset-copy")
    status, output = machine.execute("runuser -u omarchy -- /tmp/factory-reset-copy")
    assert status == 1 and "not the installed command" in output, (status, output)
    machine.fail("test -e /var/lib/nixarchy/factory-reset.request")

    # 9: root reports a failed baseline query as unknown, not absent.
    status, output = machine.execute("NIXARCHY_BTRFS=false omarchy-system-factory-reset")
    assert status == 1 and "Could not ask" in output and "no factory snapshot" not in output, (status, output)
    machine.fail("test -e /var/lib/nixarchy/factory-reset.request")
  '';
}
