{ pkgs, ... }:
{
  # ---------------------------------------------------------------------------
  # The factory baseline, restored (#172).
  #
  # installer/install.sh takes read-only @factory and @factory-home snapshots
  # at the end of every install. omarchy-system-factory-reset asks for them
  # back by writing a request file; this unit is what acts on it, and it is
  # the only thing on the machine that ever touches those snapshots.
  #
  # WHY A BOOT-TIME UNIT AND NOT THE SCRIPT ITSELF
  #
  # /home is mounted, and in use by the session the person is typing the
  # command into. Nothing in a running desktop can put a different /home
  # underneath itself, and the two approaches that look like they can are both
  # worse than this one:
  #
  #   Unmount /home and swap the subvolume. Requires killing the session that
  #   asked for the reset, from inside that session, and a failure halfway
  #   leaves a machine with no /home at all.
  #
  #   Copy files into the live /home. Not atomic, and not complete: to reach
  #   the factory state it would have to delete everything the baseline does
  #   not have, under open file handles, in a home directory being written to
  #   while it works.
  #
  # So nothing at all changes while the system is running. The script writes a
  # request and reboots; this runs on the next boot, after / is writable and
  # BEFORE /home is mounted, and either the whole reset happens or none of it
  # does.
  #
  # WHY HERE AND NOT IN modules/nixos.nix
  #
  # Same reason as services.snapper in host.nix: this file is imported by
  # host.nix, and only by it, which is imported only by flakes the installer
  # generated, so the unit exists on machines whose disk nixarchy laid out and
  # on no others. A machine where somebody imported nixosModules.nixarchy into
  # a configuration of their own has no @factory to return to and no business
  # carrying a unit that looks for one. That is the structural half of the
  # ownership gate; omarchy-system-factory-reset carries the other half and
  # refuses on /etc/nixarchy/managed.
  # ---------------------------------------------------------------------------
  systemd.services.nixarchy-factory-reset = {
    description = "Restore /home and /var/lib from the factory baseline";

    unitConfig = {
      # No implicit ordering against sysinit.target and basic.target: this has
      # to run earlier than either, and the default dependencies would place
      # it after both.
      DefaultDependencies = false;

      # The single predicate. With no request file systemd does not start the
      # unit at all, so a machine that never asks pays one stat() per boot and
      # the destructive code cannot be reached by accident -- not by a
      # `systemctl start`, which the condition also refuses.
      ConditionPathExists = "/var/lib/nixarchy/factory-reset.request";
    };

    # After the root filesystem is writable. systemd-remount-fs.service is
    # ordered Before=local-fs-pre.target, so this is after the rw remount
    # without having to name that unit.
    after = [ "local-fs-pre.target" ];

    # Before home.mount BY NAME, not merely before local-fs.target. Every
    # local mount unit is itself Before=local-fs.target and systemd leaves the
    # order among them unspecified, so "before the target" is not "before the
    # mount" -- and the whole design rests on /home not being mounted yet. A
    # restore that lands after the mount renames a subvolume the kernel is
    # already holding open: the rename succeeds, the running boot keeps
    # showing the old /home, and the user sees a reset that did nothing until
    # they reboot a second time.
    before = [
      "home.mount"
      "local-fs.target"
      "shutdown.target"
    ];
    conflicts = [ "shutdown.target" ];
    wantedBy = [ "local-fs.target" ];

    # Named explicitly rather than inherited: this runs before basic.target,
    # where the system path is not something to rely on.
    path = with pkgs; [
      btrfs-progs
      util-linux
      coreutils
    ];

    # A failure here does not fail the boot: local-fs.target only Wants this
    # unit, so a failed reset leaves the machine booting normally into the
    # state it was already in -- which is the correct outcome for a reset that
    # could not be performed.
    serviceConfig.Type = "oneshot";

    script = ''
      set -euo pipefail

      request=/var/lib/nixarchy/factory-reset.request
      stamp=$(date +%Y%m%d-%H%M%S)

      # Removed FIRST, before anything else can fail. A request that survived a
      # failed attempt would be retried on every subsequent boot, and a reset
      # that retries forever turns a machine that merely could not be reset
      # into one that cannot finish booting.
      rm -f "$request"

      # findmnt reports a btrfs source as DEVICE[/subvol]; the bracket is the
      # subvolume, not part of the device path.
      device=$(findmnt -no SOURCE / | sed 's/\[.*\]//')

      top=$(mktemp -d)
      cleanup() {
        umount "$top" 2>/dev/null || true
        rmdir "$top" 2>/dev/null || true
      }
      trap cleanup EXIT

      # The baseline is not mounted by the running system -- see the comment on
      # take_factory_snapshot in installer/install.sh -- so the top level is
      # mounted here for the length of this unit and unmounted again.
      mount -o subvol=/ "$device" "$top"

      for sub in @factory @factory-home; do
        if [ ! -d "$top/$sub" ]; then
          echo "no $sub on this filesystem: nothing has been changed." >&2
          exit 1
        fi
      done

      # ---- /var/lib -----------------------------------------------------
      #
      # Copied, not swapped. /var/lib is a plain directory inside `@` rather
      # than a subvolume of its own, and rename(2) between two btrfs
      # subvolumes is EXDEV -- there is no swap available at any price.
      # --reflink makes the copy share extents with the baseline, so it costs
      # about what the snapshot did.
      #
      # Copied aside and then moved into place in two renames, rather than
      # written over /var/lib directly: a copy that dies halfway leaves a
      # /var/lib that is neither the machine's nor the factory's, with no way
      # afterwards to tell which files are which.
      #
      # /etc/nixos is NOT touched, here or anywhere in this unit. It is on the
      # same subvolume and it is the user's configuration repository: a reset
      # that ate their commits would destroy the one thing that makes a
      # reinstall recoverable.
      rm -rf /var/lib.factory-new
      cp -a --reflink=auto "$top/@factory/var/lib" /var/lib.factory-new
      mv /var/lib "/var/lib.before-reset-$stamp"
      mv /var/lib.factory-new /var/lib

      # ---- /home --------------------------------------------------------
      #
      # A writable clone of the read-only baseline, then two renames at the
      # top level. Instant, and atomic in the only sense that matters: at no
      # point is there no @home.
      #
      # The old @home is renamed, never deleted. "Factory reset" here means
      # the data is no longer in /home, not that it has been shredded --
      # omarchy-system-factory-reset says exactly that before it asks, twice,
      # and prints the command that removes the leftover. Destroying a
      # person's entire home directory with no way back is not something to do
      # as a side effect of a boot, and the machine being sold is the case the
      # refusal text already answers with "wipe the disk".
      btrfs subvolume snapshot "$top/@factory-home" "$top/@home-factory-$stamp"
      mv "$top/@home" "$top/@home-before-reset-$stamp"
      mv "$top/@home-factory-$stamp" "$top/@home"

      # The receipt, written into the /var/lib that was just restored so that
      # it survives -- and so that a person watching their machine come back
      # empty has something to read that says what happened and where their
      # files went.
      mkdir -p /var/lib/nixarchy
      cat >/var/lib/nixarchy/factory-reset.done <<EOF
      This machine was factory-reset on $stamp.

      /home and /var/lib were restored from the snapshots the installer took
      before anyone logged in. What was there instead is still on the disk:

        the home directory   @home-before-reset-$stamp, a btrfs subvolume at
                             the top level of this filesystem
        the service state    /var/lib.before-reset-$stamp

      Neither is mounted. To read the old home directory:

        sudo mount -o subvol=/ $device /mnt
        ls /mnt/@home-before-reset-$stamp

      To delete it once you are sure:

        sudo btrfs subvolume delete /mnt/@home-before-reset-$stamp
        sudo rm -rf /var/lib.before-reset-$stamp

      /etc/nixos was not touched. The system half resets by rebuilding from
      the first commit in that repository; see omarchy-system-factory-reset.
      EOF

      echo "factory reset complete: /home and /var/lib are as the installer left them."
    '';
  };
}
