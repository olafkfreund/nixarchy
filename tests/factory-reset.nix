{ pkgs, ... }:
# Why: tests/AGENTS.md#factory-reset
pkgs.testers.runNixOSTest {
  name = "nixarchy-factory-reset";

  nodes.machine = {
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
    boot.initrd.systemd = {
      enable = true;
      repart = {
        enable = true;
        device = "/dev/vda";
        empty = "allow";
      };
    };
    users.users.omarchy = {
      isNormalUser = true;
      extraGroups = [ "wheel" ];
    };
    environment.systemPackages = [
      pkgs.btrfs-progs
      pkgs.e2fsprogs
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

    machine.reboot()
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

    machine.fail("runuser -u omarchy -- btrfs subvolume list -r /")

    machine.succeed("btrfs subvolume delete /top/@spike /top/@spike-ro")
    machine.succeed("rm /var/lib.spike/spike-sentinel /var/lib/spike-sentinel /home/spike-sentinel")
    machine.succeed("rmdir /var/lib.spike && umount /top && rmdir /top")
  '';
}
