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
  # BEFORE /home is mounted. A single failing command leaves /home and /var/lib
  # both reset or both untouched. A failed rollback is reported for repair;
  # power loss is outside that promise.
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
      failed=/var/lib/nixarchy/factory-reset.failed
      stamp=$(date +%Y%m%d-%H%M%S)
      oldvar=/var/lib.before-reset-$stamp
      top=""
      oldhome=""
      device=""
      phase=guard
      step="moving the request aside"

      # A failed report must not change the unit's result.
      report() {
        printf '%s\n' "$@" >"$failed" || echo "could not write $failed" >&2
      }
      remove_staged() {
        rm -rf "$oldvar" || echo "could not remove $oldvar" >&2
        if [ -e "$oldhome" ]; then
          btrfs subvolume delete "$oldhome" || echo "could not remove $oldhome" >&2
        fi
      }
      on_exit() {
        rc=$?
        set +e
        case $phase in
          guard)
            report "nothing changed" "Failed while $step. See: journalctl -u nixarchy-factory-reset"
            ;;
          stage)
            remove_staged
            report "nothing changed" "Failed while $step. See: journalctl -u nixarchy-factory-reset"
            ;;
          home-swapped)
            if exch "$top/@home" "$oldhome"; then
              remove_staged
              report "rolled back" "Failed while $step, and /home was put back. Nothing changed."
            else
              # $oldhome holds the person's home. Nothing is removed.
              report "rollback failed" "Failed while $step, and /home could not be put back." \
                "/home is reset and /var/lib is not. Your home is @home-before-reset-$stamp. To repair:" \
                "  sudo mkdir -p /mnt" \
                "  sudo mount -o subvol=/ $device /mnt" \
                "  sudo exch /mnt/@home /mnt/@home-before-reset-$stamp" \
                "  sudo rm -rf $oldvar    # the unused factory copy" \
                "  sudo rm $failed        # so this is not repeated: a second exch undoes the first" \
                "  systemctl reboot" \
                "Then @home-before-reset-$stamp holds only the factory copy, and can be deleted:" \
                "  sudo mount -o subvol=/ $device /mnt" \
                "  sudo btrfs subvolume delete /mnt/@home-before-reset-$stamp"
            fi
            ;;
          done) ;;
        esac
        if [ -n "$top" ]; then
          umount "$top" 2>/dev/null
          rmdir "$top" 2>/dev/null
        fi
        exit "$rc"
      }
      trap on_exit EXIT

      # One rename removes the trigger and creates the record, so a crash still leaves one.
      mv "$request" "$failed"

      # findmnt reports a btrfs source as DEVICE[/subvol]; the bracket is the
      # subvolume, not part of the device path.
      step="mounting the top level"
      device=$(findmnt -no SOURCE / | sed 's/\[.*\]//')
      top=$(mktemp -d)
      # The baseline is not mounted by the running system -- see the comment on
      # take_factory_snapshot in installer/install.sh -- so the top level is
      # mounted here for the length of this unit and unmounted again.
      mount -o subvol=/ "$device" "$top"
      oldhome=$top/@home-before-reset-$stamp

      for sub in @factory @factory-home @home; do
        step="checking $sub"
        if ! btrfs subvolume show "$top/$sub" >/dev/null 2>&1; then
          echo "$sub is not a subvolume here: nothing has been changed." >&2
          exit 1
        fi
      done
      step="checking the names are free"
      if [ -e "$oldvar" ] || [ -L "$oldvar" ] || [ -e "$oldhome" ] || [ -L "$oldhome" ]; then
        echo "$oldvar or $oldhome already exists: nothing has been changed." >&2
        exit 1
      fi

      # ---- /var/lib -----------------------------------------------------
      #
      # /var/lib and its staged copy share /, so exch swaps them atomically.
      # A failed copy only removes the staged directory.
      # /etc/nixos is NOT touched, here or anywhere in this unit. It is on the
      # same subvolume and it is the user's configuration repository: a reset
      # that ate their commits would destroy the one thing that makes a
      # reinstall recoverable.
      phase=stage
      step="copying the factory /var/lib"
      cp -a --reflink=auto "$top/@factory/var/lib" "$oldvar"

      # The receipt is staged with the factory copy so the exchange commits it.
      step="writing the receipt"
      mkdir -p "$oldvar/nixarchy"
      printf '%s\n' \
        "This machine was factory-reset on $stamp." \
        "" \
        "/home and /var/lib were restored from the snapshots the installer took" \
        "before anyone logged in. What was there instead is still on the disk:" \
        "" \
        "  the home directory   @home-before-reset-$stamp, a btrfs subvolume at" \
        "                       the top level of this filesystem" \
        "  the service state    /var/lib.before-reset-$stamp" \
        "" \
        "Neither is mounted. To read the old home directory:" \
        "" \
        "  sudo mkdir -p /mnt" \
        "  sudo mount -o subvol=/ $device /mnt" \
        "  ls /mnt/@home-before-reset-$stamp" \
        "" \
        "To delete it once you are sure:" \
        "" \
        "  sudo btrfs subvolume delete /mnt/@home-before-reset-$stamp" \
        "  sudo rm -rf /var/lib.before-reset-$stamp" \
        "" \
        "An earlier failed attempt can leave more of these. To list them:" \
        "" \
        "  ls -d /var/lib.before-reset-* /mnt/@home-before-reset-*" \
        "" \
        "/etc/nixos was not touched. The system half resets by rebuilding from" \
        "the first commit in that repository; see omarchy-system-factory-reset." \
        >"$oldvar/nixarchy/factory-reset.done"

      # The old @home is renamed, never deleted. "Factory reset" here means
      # the data is no longer in /home, not that it has been shredded --
      # omarchy-system-factory-reset says exactly that before it asks, twice,
      # and prints the command that removes the leftover. Destroying a
      # person's entire home directory with no way back is not something to do
      # as a side effect of a boot, and the machine being sold is the case the
      # refusal text already answers with "wipe the disk".
      step="snapshotting @factory-home"
      btrfs subvolume snapshot "$top/@factory-home" "$oldhome"
      step="syncing the filesystem"
      btrfs filesystem sync "$top"

      step="exchanging @home"
      exch "$top/@home" "$oldhome"
      phase=home-swapped
      echo "phase=$phase"
      step="exchanging /var/lib"
      exch /var/lib "$oldvar"
      phase=done
      echo "phase=$phase"
      # Created by this run. Left there, restoring that directory would report a crashed reset.
      rm -f "$oldvar/nixarchy/factory-reset.failed" || true
      btrfs filesystem sync "$top" || true

      echo "factory reset complete: /home and /var/lib are as the installer left them."
    '';
  };
}
