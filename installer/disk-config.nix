# The one disk layout the installer offers. Imported by the installed system
# too, so the layout is declared once and is what `fileSystems` derives from --
# epic invariant 1 applied to the disk: text in the user's flake, not a side
# effect of an install script.
#
# `device` is the whole disk. Installing beside an existing OS is a second
# mode with a different shape, tracked as #47; it cannot reuse this GPT block,
# because disko only clears a partition table on a disk with no signatures and
# its partition numbers are positional. It reuses the `btrfs` block below,
# which is the reason that block is a binding rather than written out twice.
{
  device,
  encrypt ? true,
}:
let
  # Omarchy's layout on Arch is @ @home @log and @pkg for pacman's cache.
  # @nix replaces @pkg: the store is the thing worth its own subvolume here,
  # and there is no package cache to keep.
  mountOptions = [
    "compress=zstd"
    "noatime"
  ];

  btrfs = {
    type = "btrfs";
    extraArgs = [ "-f" ];
    subvolumes = {
      "@" = {
        mountpoint = "/";
        inherit mountOptions;
      };
      "@home" = {
        mountpoint = "/home";
        inherit mountOptions;
      };
      "@nix" = {
        mountpoint = "/nix";
        inherit mountOptions;
      };
      "@log" = {
        mountpoint = "/var/log";
        inherit mountOptions;
      };
    };
  };
in
{
  disko.devices.disk.main = {
    inherit device;
    type = "disk";
    content = {
      type = "gpt";
      partitions = {
        # /boot rather than /boot/efi: it is what boot.loader.systemd-boot
        # expects with no further options, and what Omarchy does with Limine.
        # 2G because a NixOS /boot holds every generation's kernel and initrd,
        # and the usual 512M runs out quietly, mid-rebuild.
        esp = {
          size = "2G";
          type = "EF00";
          content = {
            type = "filesystem";
            format = "vfat";
            mountpoint = "/boot";
            mountOptions = [ "umask=0077" ];
          };
        };
        root = {
          size = "100%";
          content =
            if encrypt then
              {
                type = "luks";
                name = "cryptroot";
                # Read once, by the disko script, at format time. The installer
                # writes it and removes it; the installed system never sees this
                # path -- its initrd prompts for the passphrase instead, and
                # nothing about this leaks into the closure. Never put it in the
                # generated flake directory: that becomes /etc/nixos and a git
                # repository.
                passwordFile = "/tmp/nixarchy-luks.key";
                # TRIM through LUKS. Upstream accepts the trade -- it makes the
                # free-space pattern visible on the device -- and so do we.
                settings.allowDiscards = true;
                content = btrfs;
              }
            else
              btrfs;
        };
      };
    };
  };
}
