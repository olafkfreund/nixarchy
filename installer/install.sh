# nixarchy-install -- bare metal to a working desktop.
#
# Asks a handful of questions, formats one disk with installer/disk-config.nix,
# writes the generated flake (installer/mkFlake.nix) to /mnt/etc/nixos and runs
# nixos-install against it.
#
# The important property: every answer ends up as *text in that flake*. The
# machine this produces belongs to the flake, not to this script -- rerunning
# `nh os switch` on it must build nothing, because nothing here happens that
# the flake does not describe.
#
# No `set -x`, ever: a passphrase and a password hash pass through here.

# Paths are spliced in at build time, so shellcheck cannot follow them here.
# shellcheck source=./gum-env.sh disable=SC1091
source @gumenv@
# shellcheck source=./lib/ui.sh disable=SC1091
source @ui@
# Read by ui.sh, which shellcheck cannot follow through a build-time splice.
export UI_LOGO_WIDE=@logo@
export UI_LOGO_COMPACT=@logocompact@
export UI_LOGO=@logo@
export UI_TIPS=@tips@
export UI_KEYMAPS=@keymaps@
# shellcheck source=./lib/dashboard.sh disable=SC1091
source @dashboard@

# The denominator for the copy half of the progress bar. Measured, from a real
# install onto a blank disk: 1875 paths. A constant rather than something
# computed, because computing it honestly means realising the closure at build
# time -- `nix build .#install` would build an entire desktop to produce one
# number. #15 replaces it with the baked closure's own count.
export UI_EXPECTED_PATHS=1875
ui_palette

TEMPLATE=@template@
TZDIR=@tzdata@/share/zoneinfo
KEYMAPS=@kbd@/share/keymaps

# Flakes are not guaranteed enabled on the live medium, and every nix call here
# needs them. Stock ISOs have enabled them for a few releases; relying on that
# would mean a confusing failure on the one that does not.
NIX_FLAGS=(--extra-experimental-features "nix-command flakes")

# The live ISO's nix.conf knows only cache.nixos.org. programs.nixarchy.binaryCaches
# applies to the installed system, not to the installer's own daemon, so without
# these the first install compiles Hyprland from source. Keys copied from
# nix.settings in modules/nixos.nix -- do not retype them.
SUBSTITUTERS="https://nixarchy.cachix.org https://hyprland.cachix.org"
TRUSTED_KEYS="nixarchy.cachix.org-1:05JOuIlsQOWY2/5DQMq7JEA1hwlhgvmMWowMfka8mMM= hyprland.cachix.org-1:a7pgxzMz7+chwVL3/pzj6jIITemDosxrE9/Kb+PfYvE="

# ...unless we are the offline image, which carries the whole closure.
#
# Not an optimisation. With a substituter configured and no network, nix waits
# out a connection timeout for EVERY path before falling back to the local
# store, so an install that is working perfectly sits there looking hung for
# several minutes. Saying there are no substituters makes the store the first
# answer rather than the last.
#
# It also means the image's completeness is tested by everyone who boots it. A
# path missing from storeContents would otherwise be quietly downloaded by
# anyone who happens to have a network, and found by the one person who does
# not.
#
# installer/cd.nix writes the marker.
if [ -f /etc/nixarchy-iso ]; then
  SUBSTITUTERS=""
  TRUSTED_KEYS=""
fi

# Copy the system rather than rebuild it.
#
# nixos-install builds into the target store (--store /mnt) and offers this
# machine's store as a substituter. Most of the system copies across fine, but
# NixOS marks its own assembly derivations -- the toplevel, etc, system-units,
# every X-Restart-Triggers-* -- preferLocalBuild with allowSubstitutes = false,
# on the reasoning that a two-line text file is cheaper to rebuild than to
# fetch. In a fresh store that reasoning inverts: rebuilding anything at all
# means having stdenv there to rebuild it with, and stdenv is not there, so nix
# works backwards to the source bootstrap and starts fetching bash's tarball.
# On a machine with no network that is where the install ends; with one, it is
# a needless multi-gigabyte download of a closure already sitting on the disk.
#
# always-allow-substitutes tells nix to ignore that attribute and take the copy
# when a copy is available. It still builds when it is not, so nothing is lost
# where the reasoning did hold.
SUBSTITUTE_FLAGS=(--option always-allow-substitutes true)

dry_run=false
answers_file=""

# --from <url> and --host <name>: install this machine from a configuration
# repository that already exists, instead of generating a fresh flake.
#
# They are two mechanisms with --answers, not one. --from says WHICH
# configuration; --answers supplies the per-machine secrets. Together they are
# an unattended enrolment. Merging them would mean inventing answers-file
# syntax for "everything in that repository", duplicating what the repository
# already says in Nix.
from_repo=""
from_host=""
from_host_exists=false

# set -u: every answer the two paths share is initialised here, so a key the
# answers file omits fails validation rather than aborting on an unbound
# variable three functions later.
device=""
encrypt=""
# "whole" (the disk is ours) or "free" (installed beside an existing OS, #47).
# Set by ask_disk_mode or the answers file; the free-space region it applies to
# lives in free_start/free_end, in sectors, and is measured twice -- once to
# decide whether to offer the mode, once immediately before cutting.
disk_mode="whole"
free_start=""
free_end=""
free_why=""
hostname=""
username=""
password_hash=""
recovery_hash=""
# auto (decide on the plan), live, or target. See run_install.
build_store_choice="auto"
luks_passphrase=""
timezone=""
keymap=""

# The generated flake, and this machine's directory inside it. Both are set by
# write_flake and read by every step after it; hostdir exists so the
# hosts/<name>/ path is spelled once. It was spelled three times when the
# layout changed, and the one occurrence that was missed silently disabled
# reuse_baked_initrd -- see the guard there.
work=""
hostdir=""

usage() {
  cat <<'USAGE'
nixarchy-install -- install nixarchy onto a disk.

  nixarchy-install              ask, then install
  nixarchy-install --dry-run    ask, write the flake to a temp directory,
                                touch no disk, print the directory and stop
  nixarchy-install --answers F  take every answer from F and ask nothing;
                                F may be an https:// URL
  nixarchy-install --from URL --host NAME
                                install from a configuration repository that
                                already exists, rather than generating a flake
  nixarchy-install --help       this

--from takes any git URL. --host is required with it and names the machine:
a directory under hosts/ in that repository. If it is already there, the
repository decides the disk, the username and the rest, and only the password
is asked for. If it is not, the questions are asked as usual and the machine is
written into the repository beside the others -- which is how somebody else's
configuration becomes a starting point for yours.

  IT RUNS THAT REPOSITORY'S NIX AS ROOT. Its disk-config.nix formats your
  disk. This is the same trust as `nix run github:...`, and worth saying out
  loud rather than leaving implied.

The answers file is one key=value per line, # for comments, no quoting:

  device=/dev/vda           whole disk, not a partition
  disk_mode=whole           whole or free; default whole. `free` installs into
                            the largest free region on the disk and leaves
                            every existing partition alone
  encrypt=yes               yes or no
  luks_passphrase=...       required when encrypt=yes
  hostname=nixarchy
  username=alice
  password_hash=$6$...      from `mkpasswd -m sha-512`; or
  password=hunter2          plaintext, hashed here -- for tests
  build_store=auto          auto, live or target: where the system is built.
                            auto builds here unless the live store is too
                            small, which is what a live ISO's RAM-backed
                            store usually is
  recovery_hash=$6$...      optional; unlocks stage-1 emergency mode, or
  recovery_passphrase=...   plaintext, hashed here. Omit for no emergency
                            access -- see ask_recovery for the trade
  timezone=Europe/London
  keymap=us

It holds a password in clear, which is inherent to installing without being
asked. Nothing copies it onto the installed machine.

Run as root from a NixOS live medium, on a UEFI machine. By default it formats
the disk you choose, completely.

The other mode installs into free space beside whatever is already on the disk
-- see disk_mode above. It is offered only on a GPT disk that already has
partitions and at least 32 GiB of contiguous free space, and never on a disk
BitLocker is holding: adding a boot entry to such a machine wakes BitLocker's
recovery prompt, and a Windows that asks for a key nobody has is worse than an
install that refused.
USAGE
}

# ---------------------------------------------------------------------------
# Substitution
#
# Not sed. The password hash is a crypt(3) string -- $6$rounds=...$... -- and
# both `$` and `&` are special on sed's replacement side, so a naive
# `sed "s/@password_hash@/$hash/"` mangles it into a hash that is not the one
# the user typed, and they discover this when they cannot log in.
#
# Bash's ${var//pattern/replacement} treats the replacement literally, which is
# exactly what is wanted and needs no escaping at all.
# ---------------------------------------------------------------------------
subst() {
  local file=$1 token=$2 value=$3 content
  content=$(<"$file")
  printf '%s' "${content//"$token"/"$value"}" >"$file"
}

require_root_and_uefi() {
  if [ "$EUID" -ne 0 ]; then
    echo "nixarchy-install: must run as root." >&2
    exit 1
  fi
  # The layout is an ESP with systemd-boot. There is no BIOS path, and saying
  # so now beats a bootloader that fails to install at the very end.
  if [ ! -d /sys/firmware/efi ]; then
    echo "nixarchy-install: this machine booted in BIOS/legacy mode." >&2
    echo "nixarchy installs UEFI-only. Enable UEFI in firmware and boot again." >&2
    exit 1
  fi
}

# ---------------------------------------------------------------------------
# Questions. Order follows upstream: keyboard, account, disk.
# ---------------------------------------------------------------------------

# A curated list, not everything under share/keymaps. That directory holds
# several hundred files including mod-dh-ansi-us-fatz-wide, which is not a
# thing to offer a person who has just booted a disk. Upstream shows about
# fifty human-readable layouts with English first; so does this.
# Getting online, on the image that needs to be.
#
# The offline image carries the whole desktop and skips all of this: asking
# someone to join a network so they can then not use it is a question with no
# purpose. The network image cannot do anything without one, and the machine it
# is installing onto may never have had a network configured -- the disk is
# empty, and the desktop that would normally ask is the thing being installed.
# So the installer has to ask, and this is the only place it can.
#
# Ethernet is not offered as a choice because it is not one. NetworkManager
# takes DHCP on a plugged cable by itself, so a wired machine never sees this
# screen, and a wired machine whose cable is not in yet wants "Try again"
# rather than a menu entry.
network_ready() {
  # The real requirement, tested directly: not "is an interface up" and not
  # NetworkManager's own connectivity check, which pings a URL that NixOS
  # leaves unset and so reports "unknown" on a perfectly good network. What
  # the install needs is the binary cache, so that is what is checked.
  curl -sfI --max-time 8 https://cache.nixos.org/nix-cache-info >/dev/null 2>&1
}

connect_wifi() {
  ui_screen "Let's get you on Wi-Fi..."
  nmcli radio wifi on >/dev/null 2>&1 || true

  # --rescan yes because the cached list is empty on a radio that came up
  # seconds ago, which is every boot of a live image. Deduplicated on SSID:
  # one network on three access points is three rows otherwise, and picking
  # the wrong row of an identical three is a confusing way to fail.
  local list ssid pw
  list=$(nmcli -t -f SSID,SIGNAL,SECURITY device wifi list --rescan yes 2>/dev/null |
    awk -F: 'NF && $1 != "" && !seen[$1]++ { printf "%s\t%s%%\t%s\n", $1, $2, ($3 == "" ? "open" : $3) }' |
    sort -t"$(printf '\t')" -k2 -rn)

  if [ -z "$list" ]; then
    ui_left "\e[31mNo networks found.\e[0m"
    ui_left "\e[90mA USB adapter may need a moment, or the driver may not be on this image.\e[0m"
    sleep 3
    return 1
  fi

  ssid=$(printf '%s\n' "$list" |
    gum choose --height "$(ui_widget_height)" --padding "$(ui_gum_pad)" --header "Select a network" |
    cut -f1)
  [ -n "$ssid" ] || return 1

  # Asked for every network, including open ones, where an empty answer is
  # correct and is passed as no password at all. One prompt that handles both
  # beats detecting the security column and being wrong about WEP.
  ui_left "\e[90mLeave blank if the network is open.\e[0m"
  pw=$(gum input --padding "$(ui_gum_pad)" --password --prompt "Password> ")

  if [ -z "$pw" ]; then
    nmcli device wifi connect "$ssid" || return 1
  else
    nmcli device wifi connect "$ssid" password "$pw" || return 1
  fi
}

ask_network() {
  # Only the network image asks. Keyed on that image's own marker rather than
  # on the absence of the offline one, and the difference is not cosmetic:
  # checks.install installs unattended, in a sandbox, with no network and no
  # marker of either kind. It works because its store is seeded, so "no offline
  # marker" would have made a passing check demand a network and fail. What
  # this screen is for is the one image that genuinely cannot proceed without
  # one, and that image says so itself.
  if [ ! -f /etc/nixarchy-iso-net ]; then
    return 0
  fi

  if network_ready; then
    return 0
  fi

  # Unattended. There is nobody to ask, so say what is wrong rather than
  # hanging on a prompt no one will answer.
  if [ -n "$answers_file" ]; then
    echo "nixarchy-install: this image installs over the network and there is none." >&2
    echo "nixarchy-install: connect a cable, or use the offline image, or configure" >&2
    echo "nixarchy-install: the network before running with --answers." >&2
    exit 1
  fi

  while true; do
    ui_screen "Let's get you online..."
    ui_left "This image downloads the desktop as it installs, so it needs a network."
    ui_left "\e[90mA wired connection is picked up on its own -- plug it in and try again.\e[0m"
    echo

    local choice
    choice=$(printf '%s\n' "Wi-Fi" "Try again" |
      gum choose --height "$(ui_widget_height)" --padding "$(ui_gum_pad)" --header "No network yet")

    case $choice in
      "Wi-Fi") connect_wifi || true ;;
      # Nothing to do but re-test: a cable plugged in during the last screen
      # has had DHCP running behind it the whole time.
      "Try again") ;;
      # gum returns nothing on an interrupt. Leave, rather than loop forever
      # on a screen someone is trying to escape.
      *) exit 1 ;;
    esac

    if network_ready; then
      return 0
    fi
  done
}

ask_keymap() {
  ui_screen "Let's set up your keyboard..."
  local choice
  choice=$(cut -f1 "$UI_KEYMAPS" | gum choose --height "$(ui_widget_height)" --padding "$(ui_gum_pad)" --header "Select keyboard layout")
  [ -n "$choice" ] || exit 1
  keymap=$(grep -F "$choice"$'\t' "$UI_KEYMAPS" | cut -f2)
  loadkeys "$keymap" 2>/dev/null || true
}

# Shared by both paths on purpose: two copies of "what is a valid username"
# diverge, and the divergence surfaces as an install that works interactively
# and fails unattended, or worse the reverse.
validate_username() {
  [[ $1 =~ ^[a-z_][a-z0-9_-]*$ ]] || {
    echo "not a usable Linux username"
    return 1
  }
  # root exists; nixbld* belong to the daemon. Creating either produces an
  # install that fails late and confusingly.
  case $1 in
    root | nixbld*)
      echo "that name is taken by the system"
      return 1
      ;;
  esac
}

validate_hostname() {
  [[ $1 =~ ^[a-z0-9]([a-z0-9-]*[a-z0-9])?$ ]] || {
    echo "letters, digits and hyphens; not starting or ending with one"
    return 1
  }
}

# The password, on its own.
#
# Split out of ask_identity because --from with a machine the repository
# already describes asks for nothing else: the username, the disk and the rest
# are decided there, and the only thing that cannot be written down in a
# repository is the secret.
ask_password() {
  while :; do
    local pw pw2
    pw=$(gum input --padding "$(ui_gum_pad)" --password --prompt "Password> ")
    pw2=$(gum input --padding "$(ui_gum_pad)" --password --prompt "Confirm> ")
    if [ "$pw" != "$pw2" ]; then
      ui_left "\e[31mThose do not match.\e[0m"
      continue
    fi
    if [ -z "$pw" ]; then
      ui_left "\e[31mAn empty password would lock you out of sudo.\e[0m"
      continue
    fi
    # One password for the user, root and the disk, as upstream does: the
    # passphrase you type at boot is the one that logs you in.
    password_hash=$(mkpasswd -m sha-512 "$pw")
    luks_passphrase=$pw
    unset pw pw2
    break
  done
}

# A way back in, if the machine ever fails to mount its root.
#
# When stage 1 cannot assemble /sysroot it drops to an emergency shell, and
# `boot.initrd.systemd.emergencyAccess` decides whether that shell is usable.
# Left unset the initrd's shadow is `root:*` and sulogin refuses -- which is
# how a machine whose subvolumes did not mount became a reinstall rather than
# a five-minute fix.
#
# Deliberately NOT the login password, and this is the whole reason the
# question is asked separately. The option takes a literal hash, which
# nixpkgs splices into the initrd's /etc/shadow (initrd.nix, `root:${passwd}`)
# -- and the initrd sits on the ESP, unformatted and unencrypted. Any password
# that can unlock a shell BEFORE the disk is unlocked has to be verifiable
# before the disk is unlocked, so there is no arrangement where this hash is
# protected by the encryption. Spending the login hash to buy recoverability
# would hand an attacker with the disk the credential that also opens the
# account and, upstream's way, the disk itself.
#
# A throwaway passphrase costs nothing if it leaks: it opens a rescue shell on
# one physical machine and nothing else.
#
# Empty is a real answer and the default. Someone who would rather reinstall
# than carry another passphrase presses enter, and the machine behaves exactly
# as it did before this existed.
ask_recovery() {
  ui_screen "A recovery passphrase, if you want one..."
  ui_left "If this machine ever fails to boot, this unlocks the emergency"
  ui_left "shell. It is stored unencrypted on the boot partition, so make it"
  ui_left "different from your password. Press enter to skip."
  while :; do
    local pw pw2
    pw=$(gum input --padding "$(ui_gum_pad)" --password --prompt "Recovery> ")
    if [ -z "$pw" ]; then
      recovery_hash=""
      break
    fi
    pw2=$(gum input --padding "$(ui_gum_pad)" --password --prompt "Confirm> ")
    if [ "$pw" != "$pw2" ]; then
      ui_left "\e[31mThose do not match.\e[0m"
      continue
    fi
    if [ "$pw" = "$luks_passphrase" ]; then
      ui_left "\e[31mThat is your login password. Use a different one.\e[0m"
      continue
    fi
    recovery_hash=$(mkpasswd -m sha-512 "$pw")
    unset pw pw2
    break
  done
}

ask_identity() {
  ui_screen "Let's set up your user account..."
  local why
  while :; do
    username=$(gum input --padding "$(ui_gum_pad)" --placeholder "Alphanumeric, no spaces (like dhh)" --prompt "Username> ")
    why=$(validate_username "$username") && break
    gum style --foreground 1 "$why"
  done

  ask_password
  ask_recovery

  while :; do
    hostname=$(gum input --padding "$(ui_gum_pad)" --placeholder "nixarchy" --prompt "Hostname> ")
    hostname=${hostname:-nixarchy}
    why=$(validate_hostname "$hostname") && break
    gum style --foreground 1 "$why"
  done

  timezone=$(
    find "$TZDIR" -type f -not -path '*/posix/*' -not -path '*/right/*' |
      sed "s#.*/zoneinfo/##" | grep '/' | sort |
      gum filter --height "$(ui_widget_height)" --padding "$(ui_gum_pad)" --placeholder "Type to search" --value "UTC"
  )
  timezone=${timezone:-UTC}
}

# The medium we booted from must never be in the list. An installer that offers
# to format itself is a bug, not an edge case.
boot_medium() {
  findmnt -no SOURCE /iso 2>/dev/null | sed 's/[0-9]*$//' || true
}

ask_device() {
  ui_screen "Let's choose where to install nixarchy..."
  local exclude list
  exclude=$(boot_medium)
  # TYPE=="disk" drops the ISO's loop devices; the exclusion drops the stick.
  #
  # The size floor drops what TYPE alone does not: lsblk calls /dev/fd0 a disk,
  # so a machine with a floppy controller -- which every qemu machine has by
  # default -- offered a 4K device as the install target, first in the list and
  # selected by default. Two presses of Return and the summary said
  # "Disk: /dev/fd0". Anything that cannot hold the closure is not a target.
  local min_bytes=$((8 * 1024 * 1024 * 1024))
  list=$(
    lsblk -dnpo NAME,TYPE 2>/dev/null | awk '$2=="disk"{print $1}' | while read -r dev; do
      # zram is compressed RAM and fd is a floppy controller every qemu machine
      # has. Both answer "disk" and neither is somewhere to put an operating
      # system.
      case $dev in
        /dev/zram* | /dev/fd*) continue ;;
      esac
      local_bytes=$(lsblk -bdno SIZE "$dev" 2>/dev/null) || continue
      [ "${local_bytes:-0}" -ge "$min_bytes" ] || continue
      printf '%s %s %s\n' "$dev" \
        "$(lsblk -dno SIZE "$dev" 2>/dev/null | tr -d ' ')" \
        "$(lsblk -dno MODEL "$dev" 2>/dev/null | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
    done | sed 's/[[:space:]]*$//'
  )
  if [ -n "$exclude" ]; then
    list=$(printf '%s\n' "$list" | grep -v "^$exclude ") || true
  fi
  if [ -z "$list" ]; then
    echo "nixarchy-install: no disk large enough to install onto." >&2
    echo "nixarchy needs at least 8 GiB; nothing attached qualifies." >&2
    exit 1
  fi
  device=$(printf '%s\n' "$list" | gum choose --height "$(ui_widget_height)" --padding "$(ui_gum_pad)" --header "Select install disk" | awk '{print $1}')
  [ -n "$device" ] || exit 1
}

# ---------------------------------------------------------------------------
# Free space, beside an existing OS (#47)
#
# The dangerous mode. Everything below runs next to somebody's Windows, so the
# rules it keeps are worth stating in one place:
#
#   Nothing here writes to a partition it did not create. The partitions are
#   cut with `sgdisk --new=0:`, where 0 is sgdisk's own "next free partition
#   number" -- a collision is impossible and there is no fallback that edits an
#   existing entry instead. The layout that formats them addresses only those
#   two partitions, by partlabel; see installer/disk-config.nix, mode = "free",
#   for why it describes no partition table at all and what disko would have
#   done if it did.
#
#   The disk is measured twice. Once to decide whether to offer the mode, and
#   once immediately before cutting, and the two must agree.
#
#   Every refusal is a refusal. There is no "install anyway".
# ---------------------------------------------------------------------------

# Upstream's floor, and it is the whole region rather than what is left after
# our ESP: 32 GiB is already tight for a desktop with a Nix store in it, and
# subtracting 2 GiB from a number somebody chose as a minimum makes it not the
# minimum any more.
FREE_MIN_GIB=32
# Same 2 GiB as the whole-disk ESP, for the same reason: a NixOS /boot holds
# every generation's kernel and initrd.
FREE_ESP_MIB=2048

# The largest free region on $1, as "start end" in sectors.
#
# NOT `sfdisk -F -J`, which #47 proposed and which does not exist: util-linux
# refuses the combination outright -- "options --list-free and --json cannot be
# combined" -- so the only machine-readable form left is sfdisk's human table,
# which is a parse waiting to rot. sgdisk answers the question directly and is
# the tool that then does the cutting, which is one fewer thing that can
# disagree: -F is the first ALIGNED sector of the largest free block, -E is its
# last sector.
free_region() {
  local dev=$1 start end
  start=$(sgdisk -F "$dev" 2>/dev/null) || return 1
  end=$(sgdisk -E "$dev" 2>/dev/null) || return 1
  case "$start$end" in
    "" | *[!0-9]*) return 1 ;;
  esac
  # Aligned up to the next 2048-sector boundary. sgdisk -F is documented as
  # the first ALIGNED sector of the largest free block, and usually is -- but
  # on a disk with no free block big enough to hold an aligned sector it
  # answers with the raw first free one (sector 34, on a full GPT disk). That
  # case is rejected by the size floor rather than by this, and the alignment
  # is done anyway so that the arithmetic in partition_free_space can state
  # that its start sectors are aligned and be right about it.
  start=$(((start + 2047) / 2048 * 2048))
  [ "$end" -gt "$start" ] || return 1
  printf '%s %s\n' "$start" "$end"
}

# Every partition on $1 that BitLocker owns.
#
# Two tests, and the second is not redundant. libblkid has recognised BitLocker
# since 2.31 and reports TYPE="BitLocker", but it wants a well-formed BDE
# header before it will say so -- a partition carrying the signature and
# nothing else libblkid recognises comes back with no TYPE at all, which was
# measured here rather than assumed. That is the right behaviour for
# identifying a volume and the wrong one for deciding whether to go near it.
#
# So the eight bytes at offset 3 are read directly as well. They are what
# BitLocker writes and what every other tool looks for, and a partition
# carrying them is not somewhere to install beside whatever libblkid makes of
# the rest of the header. A read of eight bytes; nothing here opens the device
# for writing.
bitlocker_partitions() {
  local dev=$1 part
  while read -r part; do
    [ -n "$part" ] || continue
    if [ "$(blkid -o value -s TYPE "/dev/$part" 2>/dev/null)" = "BitLocker" ] ||
      [ "$(dd if="/dev/$part" bs=1 skip=3 count=8 status=none 2>/dev/null)" = "-FVE-FS-" ]; then
      printf '%s\n' "/dev/$part"
    fi
  done < <(lsblk -lno NAME,TYPE "$dev" 2>/dev/null | awk '$2=="part"{print $1}')
}

# Can $1 take a free-space install? Sets free_start/free_end when it can and
# free_why when it cannot. Read-only: it opens nothing for writing and changes
# nothing, which is what makes it safe to call from the question screen.
free_space_possible() {
  local dev=$1 region sector_bytes region_bytes locked label

  free_start=""
  free_end=""
  free_why=""

  # An MBR disk is not refused because GPT is nicer. sgdisk CONVERTS an MBR
  # table to GPT the moment it writes one, and a Windows that was booting from
  # that MBR then does not boot. Nothing here is willing to do that on
  # somebody's behalf, so a disk without a GPT gets the whole-disk mode or
  # nothing.
  # blkid rather than `lsblk -dno PTTYPE`: lsblk reads that column from udev's
  # properties, which a loop device does not have, so the whole free-space path
  # was unreachable on exactly the kind of device this is safe to test against.
  # blkid probes the disk itself and answers the same question.
  if [ "$(blkid -o value -s PTTYPE "$dev" 2>/dev/null)" != "gpt" ]; then
    free_why="$dev has no GPT partition table"
    return 1
  fi

  # Nothing to install beside. Upstream skips the mode screen entirely here and
  # so does this: "alongside existing data" with no existing data is a question
  # with one honest answer, and asking it invites the other one.
  if [ "$(lsblk -rno TYPE "$dev" 2>/dev/null | grep -c '^part$')" -eq 0 ]; then
    free_why="$dev has no partitions -- there is nothing to install beside"
    return 1
  fi

  # BitLocker. Refused rather than worked around, which #47 asks for and which
  # is not conservatism: nothing here would touch the encrypted volume, but a
  # free-space install adds an EFI boot entry and changes the boot order, and
  # BitLocker measures the boot chain. The next boot of Windows asks for a
  # recovery key. If the person has it, they lost an afternoon; if they do not
  # -- and most people do not -- the data is gone as surely as if this had
  # formatted it.
  locked=$(bitlocker_partitions "$dev")
  if [ -n "$locked" ]; then
    free_why="BitLocker is holding $(echo "$locked" | tr '\n' ' ')on $dev"
    return 1
  fi

  # Our own labels, already taken. The layout addresses partitions by
  # /dev/disk/by-partlabel/nixarchy-{esp,root}, and a second partition with the
  # same label makes that symlink point at whichever one udev saw last -- which
  # is to say, at a coin toss. A second nixarchy on one disk needs a way to
  # name the two apart; until there is one, this refuses.
  for label in nixarchy-esp nixarchy-root; do
    if [ -e "/dev/disk/by-partlabel/$label" ]; then
      free_why="a partition called $label already exists on this machine"
      return 1
    fi
  done

  region=$(free_region "$dev") || {
    free_why="$dev has no free space outside its partitions"
    return 1
  }
  read -r free_start free_end <<<"$region"

  # Sectors are not always 512 bytes and a 4Kn disk is not exotic. Asking the
  # kernel costs nothing and getting it wrong is a factor of eight.
  sector_bytes=$(blockdev --getss "$dev" 2>/dev/null || echo 512)
  region_bytes=$(((free_end - free_start + 1) * sector_bytes))
  if [ "$region_bytes" -lt $((FREE_MIN_GIB * 1024 * 1024 * 1024)) ]; then
    free_why="the largest free region on $dev is under ${FREE_MIN_GIB} GiB"
    free_start=""
    free_end=""
    return 1
  fi

  return 0
}

# A region size a person can read, for the screens.
free_region_human() {
  local sector_bytes
  sector_bytes=$(blockdev --getss "$device" 2>/dev/null || echo 512)
  # iec-i, not iec: sectors are counted in powers of two and "60GB" for
  # 60 GiB is the kind of small lie that turns into a support question.
  numfmt --to=iec-i --suffix=B $(((free_end - free_start + 1) * sector_bytes))
}

# Full disk or free space. Skipped entirely -- not shown greyed out, not shown
# with one option -- when the disk cannot take a free-space install, which is
# upstream's shape and is also the only version of this screen that cannot be
# answered wrongly.
ask_disk_mode() {
  if ! free_space_possible "$device"; then
    disk_mode=whole
    return 0
  fi

  ui_screen "There is already something on this disk..."
  # Piped through ui_indent rather than handed to ui_left, which formats with
  # %b: a partition LABEL is somebody else's string and %b would interpret a
  # backslash escape in it.
  lsblk -no NAME,SIZE,FSTYPE,LABEL "$device" 2>/dev/null | head -12 | ui_indent
  echo

  local choice
  choice=$(printf '%s\n' \
    "Free space install -- keep what is on $device, use the $(free_region_human) free" \
    "Full disk install -- erase $device and everything on it" |
    gum choose --height "$(ui_widget_height)" --padding "$(ui_gum_pad)" --header "How should nixarchy use $device?")
  case $choice in
    "Free space install"*) disk_mode=free ;;
    "Full disk install"*) disk_mode=whole ;;
    # Escape, or a gum that could not draw. Neither is consent to format a
    # disk with an operating system on it.
    *) exit 1 ;;
  esac
}

# Encryption is on unless the user opts out, matching upstream: the hint is dim
# and Ctrl+C at the warning is the way out. That is upstream's shape, and it
# means the safe answer is the one you get by doing nothing.
ask_encrypt() {
  ui_screen "Ready to install"
  # The warning has to be true. "Everything on $device will be overwritten" is
  # the correct sentence for a whole-disk install and a lie for a free-space
  # one, and a person who reads a lie here learns to skip the next warning too.
  if [ "$disk_mode" = free ]; then
    ui_left "\e[33m$(free_region_human) of free space on $device will be overwritten.\e[0m"
    ui_left "\e[33mThe partitions already on $device are not touched.\e[0m"
  else
    ui_left "\e[33mEverything on $device will be overwritten. There is no recovery possible.\e[0m"
  fi
  ui_left "\e[90mPress Ctrl+C for an unencrypted install.\e[0m"
  echo

  # Three outcomes, not two. Yes encrypts; No aborts, because "no" to a
  # destructive question should never mean "do it anyway, differently"; and an
  # interrupt is upstream's hidden opt-out, which gum reports as 130.
  local rc=0
  local where=$device
  [ "$disk_mode" = free ] && where="the free space on $device"
  gum confirm --padding "$(ui_gum_pad)" "Encrypt and install to $where?" || rc=$?
  case $rc in
    0) encrypt=true ;;
    130) encrypt=false ;;
    *)
      # Refusing here is right -- "no" to a destructive question must not mean
      # "do it anyway, differently" -- but it used to refuse in silence, and on
      # the ISO a silent exit leaves a terminal with nothing on it. Say what
      # happened, and say the thing the person most needs to hear.
      ui_left ""
      ui_left "\e[1mStopped before anything was written.\e[0m"
      ui_left "\e[90mNo disk has been changed. Power off, or reboot to try again.\e[0m"
      ui_left ""
      exit 1
      ;;
  esac
}

confirm_summary() {
  ui_screen "Ready to install"
  {
    printf 'Hostname,%s\n' "$hostname"
    printf 'Username,%s\n' "$username"
    printf 'Password,********\n'
    printf 'Timezone,%s\n' "$timezone"
    printf 'Keyboard,%s\n' "$keymap"
    printf 'Disk,%s\n' "$device"
    if [ "$disk_mode" = free ]; then
      printf 'Disk use,free space only (%s)\n' "$(free_region_human)"
    else
      printf 'Disk use,the whole disk -- erased\n'
    fi
    printf 'Encrypted,%s\n' "$encrypt"
  } | gum table --separator ',' --print --columns "Setting,Value" | ui_indent
  echo
  gum confirm --padding "$(ui_gum_pad)" "Does this look right?"
}

# ---------------------------------------------------------------------------
# Unattended
#
# The answers file is parsed line by line and never sourced. It lives on
# removable media or inside a test derivation, and running it as shell so that
# a stray $ or backtick executes is a mistake waiting to happen.
#
# It also holds a plaintext password and a LUKS passphrase, unavoidably. The
# installer never copies it anywhere that persists.
# ---------------------------------------------------------------------------
# An answers file that is not on this machine yet.
#
# --answers takes a path, which means somebody had to put the file there --
# which is not unattended. A URL closes that: an image boots, fetches its
# answers and installs, with nothing typed.
#
# https only. The file carries a password in clear, which usage() already
# admits is inherent to installing without being asked; fetching it over
# plaintext http would make that worse for nothing. A URL that cannot be
# fetched is fatal here rather than later -- an unattended install that
# silently falls back to asking questions nobody is there to answer is an
# image that hangs at a prompt forever.
resolve_answers() {
  case $answers_file in
    https://*) ;;
    http://*)
      echo "nixarchy-install: --answers over plain http is refused." >&2
      echo "  The file carries a password. Use https." >&2
      exit 2
      ;;
    *) return 0 ;;
  esac

  local url=$answers_file tmp
  # umask, not chmod after the fact: between creation and the chmod the file
  # would be readable, and the whole point of it is that it is not.
  tmp=$(umask 077 && mktemp)
  echo "fetching answers from $url"
  curl --fail --silent --show-error --location --max-time 60 -o "$tmp" "$url" || {
    echo "nixarchy-install: could not fetch $url" >&2
    rm -f "$tmp"
    exit 1
  }
  answers_file=$tmp
}

read_answers() {
  local file=$1 line key value lineno=0 password=""
  [ -r "$file" ] || {
    echo "nixarchy-install: answers: cannot read $file" >&2
    exit 2
  }

  while IFS= read -r line || [ -n "$line" ]; do
    lineno=$((lineno + 1))
    line=${line%%#*}
    line=${line#"${line%%[![:space:]]*}"}
    line=${line%"${line##*[![:space:]]}"}
    [ -n "$line" ] || continue

    case $line in
      *=*) ;;
      *)
        echo "nixarchy-install: answers: line $lineno: not key=value: $line" >&2
        exit 2
        ;;
    esac
    key=${line%%=*}
    value=${line#*=}

    # A fixed case rather than a dynamic assignment, which is the whole reason
    # an unknown key can be caught at all. A silently ignored `hostnme=` is a
    # machine called nixarchy that nobody asked for.
    case $key in
      device) device=$value ;;
      disk_mode) disk_mode=$value ;;
      encrypt) encrypt=$value ;;
      luks_passphrase) luks_passphrase=$value ;;
      hostname) hostname=$value ;;
      username) username=$value ;;
      password) password=$value ;;
      password_hash) password_hash=$value ;;
      build_store) build_store_choice=$value ;;
      recovery_hash) recovery_hash=$value ;;
      recovery_passphrase) recovery_hash=$(mkpasswd -m sha-512 "$value") ;;
      timezone) timezone=$value ;;
      keymap) keymap=$value ;;
      *)
        echo "nixarchy-install: answers: line $lineno: unknown key: $key" >&2
        exit 2
        ;;
    esac
  done <"$file"

  # Hashing here rather than in validation keeps the plaintext's life short.
  if [ -n "$password" ]; then
    if [ -n "$password_hash" ]; then
      echo "nixarchy-install: answers: password: give password or password_hash, not both" >&2
      exit 2
    fi
    password_hash=$(mkpasswd -m sha-512 "$password")
    # One password for user, root and disk, as the interactive path does.
    [ -n "$luks_passphrase" ] || luks_passphrase=$password
    unset password
  fi
}

validate_answers() {
  # A machine the repository already describes has answered everything except
  # the secret. Requiring a device here would mean requiring one that is then
  # ignored, since format_disk evaluates the repository's own disko script.
  if [ "$from_host_exists" = true ]; then
    local problems=()
    [ -n "$password_hash" ] || problems+=("password: one of password or password_hash is required")
    # The repository's own disk-config.nix decides the layout, and format_disk
    # runs that rather than anything chosen here. A disk_mode in the answers
    # file would be read, ignored, and then acted on by partition_free_space --
    # cutting partitions the layout about to run knows nothing about. Refused
    # rather than silently dropped.
    [ "$disk_mode" = whole ] ||
      problems+=("disk_mode: --host names a machine the repository already describes; it decides the disk")
    if [ ${#problems[@]} -gt 0 ]; then
      printf 'nixarchy-install: answers: %s\n' "${problems[@]}" >&2
      exit 2
    fi
    return 0
  fi

  local problems=() why

  # Collected rather than reported one at a time: a test author should not have
  # to fix the same file eight times to learn what it is missing.
  [ -n "$device" ] || problems+=("device: required")
  [ -n "$encrypt" ] || problems+=("encrypt: required (yes or no)")
  [ -n "$hostname" ] || problems+=("hostname: required")
  [ -n "$username" ] || problems+=("username: required")
  [ -n "$password_hash" ] || problems+=("password: one of password or password_hash is required")
  [ -n "$timezone" ] || problems+=("timezone: required")
  [ -n "$keymap" ] || problems+=("keymap: required")

  if [ -n "$device" ]; then
    if [ ! -b "$device" ]; then
      problems+=("device: $device is not a block device")
    elif [ "$(lsblk -dno TYPE "$device" 2>/dev/null)" != "disk" ]; then
      # A partition here would be formatted as though it were the whole disk.
      problems+=("device: $device is not a whole disk")
    fi
  fi

  case $encrypt in
    "" | yes | no) ;;
    *) problems+=("encrypt: must be yes or no, got: $encrypt") ;;
  esac

  # The mode, and then -- for free -- the same test the question screen runs.
  # An answers file is the consent, not the judgement: `disk_mode=free` against
  # a disk that cannot take one has to fail here, loudly, rather than fall back
  # to the whole-disk mode. Falling back would silently erase the very disk the
  # file asked to preserve, which is the worst failure this script has.
  case $disk_mode in
    whole | free) ;;
    *) problems+=("disk_mode: must be whole or free, got: $disk_mode") ;;
  esac
  if [ "$disk_mode" = free ] && [ -n "$device" ] && [ -b "$device" ]; then
    free_space_possible "$device" || problems+=("disk_mode: free is not possible here: $free_why")
  fi
  if [ "$encrypt" = yes ] && [ -z "$luks_passphrase" ]; then
    problems+=("luks_passphrase: required when encrypt=yes")
  fi

  if [ -n "$hostname" ]; then
    why=$(validate_hostname "$hostname") || problems+=("hostname: $why")
  fi
  if [ -n "$username" ]; then
    why=$(validate_username "$username") || problems+=("username: $why")
  fi

  # Catches the person who pasted plaintext into password_hash.
  case $password_hash in
    "" | '$'*) ;;
    *) problems+=("password_hash: not a crypt(3) hash (should start with \$)") ;;
  esac

  case $build_store_choice in
    auto | live | target) ;;
    *) problems+=("build_store: must be auto, live or target, got: $build_store_choice") ;;
  esac

  case $recovery_hash in
    "" | '$'*) ;;
    *) problems+=("recovery_hash: not a crypt(3) hash (should start with \$)") ;;
  esac

  # The recovery passphrase exists to be spendable. Reusing the login hash
  # puts it in the initrd on the unencrypted ESP, which is the one thing
  # asking for it separately was meant to avoid.
  if [ -n "$recovery_hash" ] && [ "$recovery_hash" = "$password_hash" ]; then
    problems+=("recovery_hash: must differ from password_hash -- it is stored unencrypted on the ESP")
  fi

  [ -z "$timezone" ] || [ -e "$TZDIR/$timezone" ] || problems+=("timezone: no such zone: $timezone")
  if [ -n "$keymap" ] && ! find "$KEYMAPS" -name "$keymap.map.gz" -print -quit | grep -q .; then
    problems+=("keymap: no such keymap: $keymap")
  fi

  if [ ${#problems[@]} -gt 0 ]; then
    printf 'nixarchy-install: answers: %s\n' "${problems[@]}" >&2
    exit 2
  fi

  # The file is the consent; there is no confirmation prompt. The summary is
  # still printed so a test log shows what was about to happen.
  printf 'hostname=%s username=%s device=%s disk_mode=%s encrypt=%s timezone=%s keymap=%s\n' \
    "$hostname" "$username" "$device" "$disk_mode" "$encrypt" "$timezone" "$keymap"

  # The rest of the script speaks true/false; the file speaks yes/no because
  # that is what a person writing one expects.
  [ "$encrypt" = yes ] && encrypt=true || encrypt=false
}

# ---------------------------------------------------------------------------
# Doing it
# ---------------------------------------------------------------------------

# The answers, into the machine's own files.
#
# Shared by write_flake and clone_flake: a machine added to somebody else's
# repository is written exactly the same way as one in a fresh flake, because
# it is the same template. flake.nix is in the list only for the fresh case --
# a cloned repository already has one, and it carries no tokens.
substitute_host_files() {
  local f
  for f in "$work/flake.nix" "$hostdir/default.nix" "$hostdir/configuration.nix"; do
    [ -f "$f" ] || continue
    subst "$f" '@hostname@' "$hostname"
    subst "$f" '@username@' "$username"
    subst "$f" '@device@' "$device"
    subst "$f" '@diskmode@' "$disk_mode"
    subst "$f" '@timezone@' "$timezone"
    subst "$f" '@keymap@' "$keymap"
    # Quoted in the template because a bare token is not parseable Nix; the
    # quotes go with the token. An encrypted disk has already authenticated the
    # user by the time a greeter would ask, so autologin follows encryption.
    # null, or the hash WITH its quotes. Same idiom as @encrypt@: the token
    # is quoted in the template so the file parses as Nix before substitution.
    if [ -n "$recovery_hash" ]; then
      subst "$f" '"@recoverysecret@"' \
        '{ "/etc/shadow" = "/var/lib/nixarchy/initrd-shadow"; }'
    else
      subst "$f" '"@recoverysecret@"' '{ }'
    fi
    subst "$f" '"@encrypt@"' "$encrypt"
    subst "$f" '"@autologin@"' "$encrypt"
  done
}

# Install from a configuration repository that already exists.
#
# Replaces write_flake. The repository supplies the flake; what this decides is
# only whether the named machine is already in it.
#
# Nothing is pushed back. The installer has no git identity and no credentials,
# and inventing either is how an installer ends up committing as somebody it is
# not -- the same reasoning install_flake_dir already applies. The tree is left
# staged, and nixarchy-config-repo takes it from there.
clone_repo() {
  work=$(mktemp -d)

  echo "cloning $from_repo"
  # --depth 1: the history is not wanted and a fleet repository can be large.
  # The clone keeps its .git, which is not incidental -- a flake in a worktree
  # sees only tracked files, so a bare checkout would evaluate to nothing.
  git clone --depth 1 --quiet "$from_repo" "$work" || {
    echo "nixarchy-install: could not clone $from_repo" >&2
    exit 1
  }

  [ -d "$work/hosts" ] || {
    echo "nixarchy-install: $from_repo has no hosts/ directory." >&2
    echo "  This expects a repository the installer wrote, where each machine" >&2
    echo "  is a directory under hosts/. A configuration from before that" >&2
    echo "  layout has its files at the top level and is not usable here." >&2
    exit 1
  }

  hostname=$from_host
  hostdir="$work/hosts/$hostname"

  if [ -d "$hostdir" ]; then
    from_host_exists=true
  else
    from_host_exists=false
  fi
}

# The second half: run once the answers are in, if any were needed.
finish_clone() {
  if [ "$from_host_exists" = true ]; then
    # The repository already describes this machine: an administrator wrote it
    # ahead of time, or it is being rebuilt. Everything except the secrets is
    # already decided, and the device in particular comes from the repository
    # -- whoever wrote that host knew the disk. If they were wrong, disko fails
    # loudly, which is the correct failure.
    echo "$from_repo describes $hostname; using it"
  else
    # A machine the repository has never seen. The questions are asked as
    # usual and the answers are written into it beside the existing machines,
    # so everything else in there -- themes, extra modules, whatever its owner
    # wrote -- comes along untouched.
    #
    # This is the whole of "use somebody's configuration as a template". There
    # is no template mechanism beyond it, and there does not need to be.
    echo "$from_repo has no $hostname; adding it"
    cp -r "$TEMPLATE/host" "$hostdir"
    chmod -R u+w "$hostdir"
    substitute_host_files
  fi

  # Always regenerated, never taken from the repository: hardware is the one
  # thing a configuration written somewhere else cannot know.
  printf '{ ... }:\n{ }\n' >"$hostdir/hardware-configuration.nix"

  git -C "$work" add -A
}

write_flake() {
  work=$(mktemp -d)
  cp -r "$TEMPLATE"/. "$work"
  chmod -R u+w "$work"

  # The template ships one machine-shaped directory called host/; the name is
  # not known until now. Renaming it is what makes a machine, and it is why
  # the template derivation has no hostname baked into it.
  mkdir -p "$work/hosts"
  hostdir="$work/hosts/$hostname"
  mv "$work/host" "$hostdir"

  substitute_host_files

  # A placeholder, because of an ordering the flake creates: configuration.nix
  # imports ./hardware-configuration.nix, and the disko script that formats the
  # disk is evaluated *out of this flake* -- so the flake has to evaluate before
  # there is a mounted disk to generate a hardware config from. An empty module
  # is enough for that evaluation and is replaced by the real one at step 7.
  printf '{ ... }:\n{ }\n' >"$hostdir/hardware-configuration.nix"
}

# Cut our two partitions out of the free region, and nothing else.
#
# Imperative, and deliberately not disko: installer/disk-config.nix explains
# under mode = "free" what disko's gpt type does to a disk that already has a
# partition 1, and why no amount of care with its internals makes that the
# right foundation.
#
# The two properties that keep this from eating somebody's Windows:
#
#   --new=0:  0 is sgdisk's own "next free partition number". The number
#             cannot collide, and unlike disko there is no fallback path that
#             edits an existing entry when the one it wanted is taken.
#
#   explicit start and end sectors, from the region measured before anything
#   was written. `--new=0:0:0` looks tidier and is wrong: sgdisk's 0 start
#   means "the largest free block", and once the ESP has been cut the largest
#   free block on the disk may be a completely different hole. That is how a
#   root partition ends up somewhere nobody looked at.
partition_free_space() {
  local dev=$device sector_bytes esp_sectors esp_end root_start root_type
  local before after esp_dev=/dev/disk/by-partlabel/nixarchy-esp
  local root_dev=/dev/disk/by-partlabel/nixarchy-root waited

  # Measured a second time, immediately before writing, and it has to agree
  # with what the question screen saw. Between the two, a USB disk can be
  # unplugged and another one plugged into the same node -- and then the
  # sectors somebody consented to give up belong to a different machine.
  before="$free_start $free_end"
  free_space_possible "$dev" || {
    echo "nixarchy-install: $dev can no longer take a free-space install: $free_why" >&2
    exit 1
  }
  after="$free_start $free_end"
  if [ "$before" != "$after" ]; then
    echo "nixarchy-install: the free region on $dev moved between the question" >&2
    echo "  and now ($before -> $after). Nothing was written. Start again." >&2
    exit 1
  fi

  sector_bytes=$(blockdev --getss "$dev" 2>/dev/null || echo 512)
  esp_sectors=$((FREE_ESP_MIB * 1024 * 1024 / sector_bytes))
  esp_end=$((free_start + esp_sectors - 1))
  root_start=$((esp_end + 1))
  # free_start is already 2048-aligned (sgdisk -F says so) and esp_sectors is a
  # multiple of 2048 at both 512 and 4096 byte sectors, so root_start is
  # aligned too and sgdisk does not quietly move it somewhere else.
  if [ "$root_start" -ge "$free_end" ]; then
    echo "nixarchy-install: the free region is not big enough for an ESP and a root." >&2
    exit 1
  fi

  # 8309 is Linux LUKS, 8300 is a Linux filesystem. Cosmetic to the kernel and
  # not cosmetic to a person reading the disk later with somebody else's tool.
  root_type=8300
  [ "$encrypt" = true ] && root_type=8309

  sgdisk --new=0:"$free_start":"$esp_end" \
    --typecode=0:EF00 --change-name=0:nixarchy-esp "$dev"
  sgdisk --new=0:"$root_start":"$free_end" \
    --typecode=0:"$root_type" --change-name=0:nixarchy-root "$dev"

  # sgdisk asks the kernel to re-read the table itself; partx is the fallback
  # for when it cannot, which is any disk that has a partition mounted.
  partx -u "$dev" >/dev/null 2>&1 || partx -a "$dev" >/dev/null 2>&1 || true

  # udevadm settle, because the layout addresses these two by
  # /dev/disk/by-partlabel and those symlinks are udev's work, not the
  # kernel's. Without the wait the disko script runs against paths that do not
  # exist yet.
  waited=0
  until [ -b "$esp_dev" ] && [ -b "$root_dev" ]; do
    udevadm settle
    waited=$((waited + 1))
    if [ "$waited" -gt 30 ]; then
      echo "nixarchy-install: $esp_dev and $root_dev never appeared." >&2
      echo "  The partitions were created; nothing was formatted. Reboot and look." >&2
      exit 1
    fi
    sleep 0.5
  done

  # The region was free, not blank.
  #
  # Whatever used to live in those sectors is still sitting in them, and blkid
  # will happily report its old filesystem. That matters because disko's
  # luks._create and filesystem._create BOTH skip when blkid already recognises
  # the device -- so a stale signature means the format silently does not
  # happen, and the install proceeds to mount and write over whatever the
  # previous owner of those sectors left behind.
  #
  # Only these two paths, and only after the wait above proved they are the
  # partitions this function just created. wipefs takes a device, and the two
  # arguments it gets here are the only two devices in this script that are
  # ours by construction.
  wipefs -a "$esp_dev" "$root_dev"
}

format_disk() {
  # Leave /mnt clean, because disko will not.
  #
  # disko's mount phase asks `findmnt` whether each mountpoint is already
  # mounted and SKIPS the ones that are. After a first install that failed
  # partway -- the bootloader step is the one that has actually happened --
  # /mnt, /mnt/nix, /mnt/home and /mnt/var/log are all still mounted. The
  # second run then destroys and reformats the disk underneath them, and
  # every child mount is skipped as "already mounted" while `@` is the only
  # subvolume anything is written through.
  #
  # The result installs and boots as far as the LUKS prompt. Then fstab
  # mounts the real (empty) @nix over /nix, the store disappears, stage 2
  # cannot find its init, and the machine drops to emergency mode -- where
  # the initrd's root account is locked by design and there is nothing the
  # user can do. Reported from a real install; @nix, @home and @log were
  # empty and 21G sat in @/nix, @/home and @/var/log.
  if findmnt -rno TARGET /mnt >/dev/null 2>&1; then
    umount -R /mnt || {
      echo "nixarchy-install: something is mounted at /mnt and will not unmount." >&2
      echo "  Formatting now would install into the wrong subvolumes. Reboot and retry." >&2
      exit 1
    }
  fi

  # Before the passphrase file and before the disko script: in free-space mode
  # the layout the script evaluates addresses partitions that do not exist yet.
  if [ "$disk_mode" = free ]; then
    partition_free_space
  fi

  # The passphrase file disko's passwordFile points at. Written with umask 077,
  # removed as soon as the format is done; it never reaches the installed
  # system, whose initrd prompts instead.
  ( umask 077 && printf '%s' "$luks_passphrase" >/tmp/nixarchy-luks.key )

  # Evaluated from the USER'S flake, not ours: the same disk-config.nix the
  # installed machine imports is the one that formats the disk. That is the
  # whole reason the layout is a file rather than a parted script.
  # Built and then executed, rather than `nix run`: diskoScript's output IS the
  # script, and `nix run` looks for $out/bin/<name> inside it, which fails with
  # "Not a directory".
  local script
  script=$(nix "${NIX_FLAGS[@]}" build --no-link --print-out-paths \
    "$work#nixosConfigurations.$hostname.config.system.build.diskoScript")
  "$script"

  rm -f /tmp/nixarchy-luks.key
}

# Prove disko mounted what the layout asked for.
#
# The layout gives /nix, /home and /var/log their own subvolumes, and the
# installed system's fstab mounts them. If they are not mounted HERE, the
# install still succeeds -- it just writes all of it into `@`, and the
# machine bricks on first boot when the empty subvolumes mount over the
# top. Nothing downstream notices, which is why this is checked rather
# than assumed.
#
# `findmnt --mountpoint` matches only a real mountpoint, so a plain
# directory inside `@` does not satisfy it.
verify_subvolume_mounts() {
  local mp missing=""
  for mp in /mnt /mnt/nix /mnt/home /mnt/var/log; do
    findmnt -rno TARGET --mountpoint "$mp" >/dev/null 2>&1 || missing="$missing $mp"
  done
  if [ -n "$missing" ]; then
    echo "nixarchy-install: disko did not mount:$missing" >&2
    echo "  Installing now would put the store and home inside the root" >&2
    echo "  subvolume, and the machine would not boot. Nothing was installed." >&2
    findmnt -R /mnt >&2 || true
    return 1
  fi
}

generate_hardware_config() {
  # --no-filesystems because disko owns fileSystems; a second definition of /
  # fails the build. --show-hardware-config prints to stdout, where the plain
  # --root form would also write a configuration.nix over the template's.
  nixos-generate-config --root /mnt --no-filesystems --show-hardware-config \
    >"$hostdir/hardware-configuration.nix"

  reuse_baked_initrd "$hostdir/hardware-configuration.nix"
}

# Use the initrd we already have, when it fits.
#
# nixos-generate-config lists the storage modules it found on this machine.
# They are correct, and they are also the single most expensive line in the
# file: a different module list is a different initrd, a different module
# closure and a different toplevel, so a machine that states its own list
# cannot use the one already sitting on the medium. It has to build one --
# which needs a compiler, which on an image with no network means the source
# bootstrap, which means the install stops.
#
# The reference host carries a superset (see installer/host.nix). When what
# was detected fits inside it, the detected line is commented out and the
# superset applies: the initrd is then byte-identical to the baked one and is
# copied rather than built. When it does not fit -- some controller we do not
# carry -- the line stays exactly as generated, because a machine that boots
# slowly is better than one that does not boot.
#
# Only availableKernelModules is touched. boot.kernelModules is left alone:
# it is where the CPU's KVM module lands, suppressing it would cost the user
# virtualisation, and it perturbs seven text derivations rather than an
# initrd -- which the medium can build from what it carries.
reuse_baked_initrd() {
  local file=$1 detected m
  local baked avail_src forced_src

  # Loudly, because the silent version of this cost a day. When the hosts/
  # layout moved hardware-configuration.nix, this function kept being handed
  # the old flat path: sed printed nothing for a file that was not there, the
  # pipe below swallowed its exit status, `detected` came out empty, and the
  # early return read exactly like "nothing was detected, nothing to pin".
  # The install then went on with the modules nixos-generate-config found,
  # which is a different initrd, which is a build, which on an image with no
  # network is the source bootstrap -- 517 derivations from hex0-seed, and a
  # checks.install that failed a long way from the line that broke it.
  if [ ! -f "$file" ]; then
    echo "hardware: no $file to pin -- refusing to install a machine whose" >&2
    echo "hardware: initrd would have to be built. This is a bug in the installer." >&2
    exit 1
  fi

  # The list depends on the answer to the encryption question: LUKS pulls a
  # dozen crypto modules into the initrd, so the two baked initrds have
  # different module sets and pinning to the wrong one matches neither.
  if [ "$encrypt" = "yes" ]; then
    avail_src="@initrdmodules@"
    forced_src="@initrdforced@"
  else
    avail_src="@initrdmodulesplain@"
    forced_src="@initrdforcedplain@"
  fi
  baked=" $avail_src "

  detected=$(sed -n 's/.*boot\.initrd\.availableKernelModules = \[\(.*\)\];.*/\1/p' "$file" |
    tr -d '"')
  [ -n "$detected" ] || return 0

  # Every miss, not the first. One of these means a rebuild either way, and
  # naming them all means whoever widens the set in installer/host.nix does it
  # once rather than once per module.
  local missing=""
  for m in $detected; do
    case $baked in
      *" $m "*) ;;
      *) missing="$missing $m" ;;
    esac
  done

  if [ -n "$missing" ]; then
    echo "hardware: not on this medium:$missing" >&2
    echo "hardware: keeping the detected initrd, which the install must build." >&2
    return 0
  fi

  # Pinned with mkForce, not just commented out.
  #
  # Commenting the detected line is not enough, and the reason is easy to miss:
  # nixos-generate-config also writes an `imports` line, and
  # profiles/qemu-guest.nix sets availableKernelModules itself -- virtio_net,
  # 9p, virtiofs, and initrd.kernelModules of its own. A comment cannot undo an
  # import. So the detected line is commented for the reader, and both lists
  # are then forced to what the medium carries, which is what actually makes
  # the initrd identical to the baked one.
  #
  # Both lists: availableKernelModules is what may be loaded, kernelModules is
  # what is loaded unconditionally, and the profile adds to both.
  # The comment goes first. Run the other way round, the sed below also
  # matches the mkForce line just written and comments out the pin, which
  # is exactly as broken as doing nothing and much harder to see.
  # Commented as well, so the reader sees what was detected here rather than
  # only what replaced it.
  sed -i \
    -e 's|^\( *\)boot\.initrd\.availableKernelModules|\1# Detected on this machine, and already covered by the module set nixarchy\
\1# installs, so it is commented out: leaving it in would mean building an\
\1# initrd instead of copying the one that came with the installer.\
\1#\
\1# Uncomment it to use exactly what was detected here. That is a rebuild,\
\1# and it needs a network the first time.\
\1# boot.initrd.availableKernelModules|' \
    -e 's|^\( *\)boot\.initrd\.kernelModules|\1# Commented for the same reason, and also because it has to be: the pin\
\1# below sets this too, and Nix rejects an attribute defined twice in one\
\1# attrset -- the flake would not parse.\
\1# boot.initrd.kernelModules|' \
    "$file"

  # The file ends with its closing brace, and the pin has to go inside it.
  # Guarded rather than assumed: if nixos-generate-config ever stops ending
  # that way, this leaves the file alone rather than producing a flake that
  # does not parse, three minutes before the disk is written to.
  if [ "$(tail -n 1 "$file")" != "}" ]; then
    echo "hardware: unexpected shape; keeping the detected initrd" >&2
    return 0
  fi

  # The Nix lines are printf, not part of the heredoc: writeShellApplication
  # runs shellcheck over this file, an unquoted heredoc is shell as far as it
  # is concerned, and `boot.initrd.x = lib.mkForce [...]` reads to it as a
  # command called `boot.initrd.x` with a stray `=`. A quoted heredoc for the
  # prose and printf for the two generated lines keeps both readers happy.
  local avail forced
  # shellcheck disable=SC2086  # deliberate word splitting: a module per word
  avail=$(printf '"%s" ' $avail_src)
  # shellcheck disable=SC2086
  forced=$(printf '"%s" ' $forced_src)

  {
    head -n -1 "$file"
    cat <<'PIN'

  # ---- added by the nixarchy installer -------------------------------------
  # The initrd this machine boots is the one that came on the installer, which
  # is why the install copied it rather than spending minutes building a
  # near-identical one.
  #
  # Both lists are forced because a comment cannot undo an import: the line
  # above sets availableKernelModules, but so does the profile this file
  # imports (qemu-guest.nix, on a VM), and that contribution would survive.
  #
  # Delete this block to use exactly what was detected on this machine. That
  # is a rebuild, and it needs a network the first time.
PIN
    printf '  boot.initrd.availableKernelModules = lib.mkForce [ %s];\n' "$avail"
    printf '  boot.initrd.kernelModules = lib.mkForce [ %s];\n' "$forced"
    tail -n 1 "$file"
  } >"$file.pinned" && mv "$file.pinned" "$file"
}

# The login hash, written outside the flake directory.
#
# It used to be substituted into configuration.nix, which put it in a git
# repository the user is then encouraged to push. Same umask discipline as the
# LUKS passphrase file above, but this one stays: the installed machine needs
# it at every activation, because users.users.<name>.hashedPasswordFile is read
# then and not baked into the store.
#
# Root-owned and 0600. It is not a password, but a crypt hash is worth exactly
# as much as the time somebody is willing to spend on it offline.
write_password_hash() {
  ( umask 077
    mkdir -p /mnt/var/lib/nixarchy
    printf '%s\n' "$password_hash" >/mnt/var/lib/nixarchy/password.hash )
  chmod 0600 /mnt/var/lib/nixarchy/password.hash
  chown 0:0 /mnt/var/lib/nixarchy/password.hash

  # The recovery passphrase, as a whole shadow line, because that is what
  # boot.initrd.secrets appends over the initrd's /etc/shadow.
  #
  # Here rather than in the flake, and this is the point of the whole
  # arrangement: /etc/nixos is a git repository that nixarchy-config-repo
  # pushes to GitHub, and checks.install asserts no crypt hash ever appears
  # inside it. boot.initrd.secrets names a path on the live filesystem, read
  # at bootloader-install time by systemd-boot -- which sets
  # supportsInitrdSecrets, so the value is never copied into the store either.
  if [ -n "$recovery_hash" ]; then
    ( umask 077
      printf 'root:%s:::::::\n' "$recovery_hash" >/mnt/var/lib/nixarchy/initrd-shadow )
    chmod 0600 /mnt/var/lib/nixarchy/initrd-shadow
    chown 0:0 /mnt/var/lib/nixarchy/initrd-shadow
  fi
}

install_flake_dir() {
  mkdir -p /mnt/etc
  mv "$work" /mnt/etc/nixos

  # A flake inside a git worktree sees only tracked or staged files, so without
  # the add, nixos-install fails on the first import. No commit: git needs an
  # identity and choosing the user's is not the installer's business.
  #
  # Not chowned to the user. /etc/nixos is root-owned on a real machine and
  # nixarchy-apply runs its copy under sudo; vm/configuration.nix chowns it
  # only because `nix flake update` runs unprivileged there.
  git -C /mnt/etc/nixos init -q
  git -C /mnt/etc/nixos add -A
}

# Refuse a build the live store has no room for, and say which number is the
# problem.
#
# The store on a live ISO is a RAM-backed overlay -- half the machine's memory,
# so 7.8G on a 16 GiB laptop -- over the read-only squashfs. `du` reports the
# squashfs too, which is why it can say 18G while there is nothing left to
# write. Every path nix has to fetch or build lands in that overlay before
# anything reaches the disk.
#
# When it fills, the install does not stop: it dies partway with "No space left
# on device", several levels under a "1 dependency failed" that names none of
# it. installer/vm.nix says exactly this about the test VM, which escapes with
# writableStoreUseTmpfs = false and a real disk. The ISO has no such escape, so
# a user meets it as a machine that installed and has no bootloader. One did.
#
# A fixed threshold would not catch it. The machine that failed had 7.8G free
# when it started, which passes any figure worth setting; it filled during the
# build. The only number that decides it is the one the dry-run already prints
# -- "(8.1 GiB download, 21.0 GiB unpacked)" -- against what df says is left.
#
# Tolerant on purpose: an unparseable plan proceeds. This exists to name a
# failure that already happens, not to invent a new way to refuse.
check_store_space() {
  local plan=$1 size unit want free store
  store=$(df -P /nix/store 2>/dev/null | awk 'NR==2 {print $1}')

  read -r size unit <<<"$(printf '%s\n' "$plan" |
    sed -n 's/.*[(,] *\([0-9.]*\) \([KMG]iB\) unpacked.*/\1 \2/p' | head -1)"
  [ -n "$size" ] && [ -n "$unit" ] || return 0

  case $unit in
    KiB) want=$(awk "BEGIN{printf \"%.0f\", $size*1024}") ;;
    MiB) want=$(awk "BEGIN{printf \"%.0f\", $size*1048576}") ;;
    GiB) want=$(awk "BEGIN{printf \"%.0f\", $size*1073741824}") ;;
    *) return 0 ;;
  esac

  free=$(df -B1 -P /nix/store 2>/dev/null | awk 'NR==2 {print $4}')
  case $free in ''|*[!0-9]*) return 0 ;; esac

  # A margin, because the figure is what the paths occupy and not what nix
  # needs in flight to put them there.
  [ "$want" -lt "$((free - free / 10))" ] && return 0

  echo "nixarchy-install: the live store cannot hold what this install must fetch." >&2
  echo >&2
  echo "  needs : $(numfmt --to=iec "$want" 2>/dev/null || echo "$want bytes") unpacked" >&2
  echo "  free  : $(numfmt --to=iec "$free" 2>/dev/null || echo "$free bytes") on ${store:-/nix/store}" >&2
  echo >&2
  echo "  On a live ISO this is a RAM-backed overlay, sized at half the" >&2
  echo "  machine's memory. It is not the disk you are installing to, which" >&2
  echo "  has room -- so more RAM, or a machine with more, is what changes it." >&2
  echo >&2
  echo "  Building into the target store instead, which has the room. This is" >&2
  echo "  slower -- every path is written to the disk as it is produced rather" >&2
  echo "  than copied there at the end -- and it is not a failure." >&2
  echo >&2
  echo "  This normally fetches nothing at all: the image carries the closure" >&2
  echo "  already. Having anything to fetch means what the image baked is not" >&2
  echo "  what this flake asks for, which is a bug worth reporting with the" >&2
  echo "  two numbers above." >&2
  return 1
}

run_install() {
  # What would have to be built, printed before doing it. On a machine with no
  # network an unseeded build input is the difference between an install and a
  # confusing cascade of source downloads, and this names it once rather than
  # leaving it to be inferred from whatever failed first.
  #
  # Captured rather than piped straight to the log, because check_store_space
  # reads the same plan: the sizes it decides on are the ones printed here.
  local plan
  plan=$(nix "${NIX_FLAGS[@]}" build --dry-run "${SUBSTITUTE_FLAGS[@]}" \
    "/mnt/etc/nixos#nixosConfigurations.$hostname.config.system.build.toplevel" 2>&1) || true
  printf '%s\n' "$plan" | head -40

  # Where to build. The live store by default, because that is the path every
  # install has taken and the one the comment below argues for; the target
  # store when the live one cannot hold the job, which is the only case where
  # the argument stops applying -- a path that will not fit is not faster to
  # produce locally, it is impossible.
  #
  # --eval-store auto is what makes this safe, and it is the thing that was not
  # available when the comment below was written. `--store /mnt` alone sets the
  # EVALUATION store too, which is the failure that comment describes: locked
  # inputs resolved against an empty store, and nix going to the network for
  # sources sitting one directory up. Splitting them keeps evaluation here,
  # where the sources are, and sends only build outputs to the disk.
  #
  # --extra-substituters auto?trusted=1 offers this machine's store to the
  # target one, which is exactly what nixos-install does for the same reason
  # (its own `sub="auto?trusted=1"`). Combined with always-allow-substitutes in
  # SUBSTITUTE_FLAGS -- see the comment on it, which is about precisely this
  # arrangement -- the closure is copied rather than rebuilt.
  local build_store=()
  case ${build_store_choice:-auto} in
    target) build_store=(--store /mnt --eval-store auto --extra-substituters "auto?trusted=1") ;;
    live) ;;
    *) check_store_space "$plan" ||
      build_store=(--store /mnt --eval-store auto --extra-substituters "auto?trusted=1") ;;
  esac

  # Build here, then install what was built. NOT `nixos-install --flake`.
  #
  # --flake makes nixos-install run `nix build --store /mnt`, and --store sets
  # the EVALUATION store as well as the build one. Evaluating the generated
  # flake against /mnt means resolving every locked input against a store that
  # has just been created and contains nothing, so nix goes to the network for
  # sources that are sitting in the store one directory up:
  #
  #   error: unable to download
  #   'https://github.com/olafkfreund/nixarchy/archive/<rev>.tar.gz'
  #
  # -- on an image built precisely so that it would not have to. Building the
  # toplevel here first evaluates against THIS store, where the sources are,
  # and hands nixos-install a path with --system, which only copies.
  #
  # It is also the faster order. The build is the same either way, but this
  # way it happens once, in the store that already holds every dependency,
  # instead of inside a target store that has to have each one copied to it
  # before it can be used.
  local system
  system=$(nix "${NIX_FLAGS[@]}" build --no-link --print-out-paths "${SUBSTITUTE_FLAGS[@]}" \
    "${build_store[@]}" \
    "/mnt/etc/nixos#nixosConfigurations.$hostname.config.system.build.toplevel") || true

  # Checked, because set -e will not check it here. The whole install runs as
  # `{ ...; } || rc=$?` so the dashboard can report a failure, and inside a
  # compound command whose status is tested, errexit does not fire. A failed
  # build therefore returned an empty string, and nixos-install was called with
  # `--system ""` -- which it reads as no system at all, falls back to looking
  # for a flake in the current directory, and reports
  #
  #   error: could not find a flake.nix file
  #
  # naming nothing that has anything to do with what actually went wrong.
  if [ -z "$system" ]; then
    echo "nixarchy-install: the system did not build; nothing was installed." >&2
    echo "The build output is above, in /var/log/nixarchy-install.log." >&2
    return 1
  fi

  # nixos-install takes --option, not --extra-experimental-features: it is not
  # a nix subcommand and rejects the flag outright.
  nixos-install --root /mnt --system "$system" --no-root-password \
    --option extra-experimental-features "nix-command flakes" \
    --option extra-substituters "$SUBSTITUTERS" \
    --option extra-trusted-public-keys "$TRUSTED_KEYS" \
    "${SUBSTITUTE_FLAGS[@]}"
}

# The baseline a factory reset returns to (#172).
#
# Read-only snapshots of `@` and `@home` exactly as nixos-install left them,
# before anyone has logged in. They cost close to nothing: a btrfs snapshot
# shares every extent with the subvolume it came from, so this is a metadata
# write now and no ongoing cost at all until the live subvolumes diverge from
# it -- which is the whole reason a baseline is affordable here and a copy
# would not be.
#
# Taken at the btrfs TOP LEVEL, which is mounted nowhere during an install:
# /mnt is `@`, and a snapshot made under /mnt would be a subvolume nested
# inside the thing it is a snapshot of, and would then appear inside itself
# on every later snapshot. So the top level is mounted for the length of this
# function and unmounted again. installer/disk-config.nix deliberately gains
# no entry -- the baseline is never mounted by the running system, it is
# reached by mounting the top level at the moment it is used, which is what
# installer/host.nix's restore unit does.
#
# What is NOT here: any change to the bootloader. Upstream offers @factory as
# a boot entry; PR #114 settled why that is meaningless on this layout --
# `@` holds almost no operating system, the kernels are on the ESP and the
# system is in `@nix`, so booting a factory root boots the same system with
# an older /etc. Generations are the bootable rung.
#
# Deliberately NOT fatal. It runs after nixos-install has succeeded, and
# failing a thirty-minute install over a snapshot the user may never reach
# for is disproportionate. The degradation is honest rather than silent --
# the inverse of the #171 shape: with no baseline on disk,
# omarchy-system-factory-reset finds none and says so, which is exactly the
# behaviour every machine had before this existed. What stops the absence
# going unnoticed is checks.install, which asserts both subvolumes exist and
# are read-only after a real install.
take_factory_snapshot() {
  local device top rc=0

  # findmnt reports a btrfs source as DEVICE[/subvol]; the bracket is the
  # subvolume, not part of the device path.
  device=$(findmnt -no SOURCE /mnt 2>/dev/null | sed 's/\[.*\]//') || true
  if [ -z "$device" ]; then
    echo "nixarchy-install: nothing is mounted at /mnt; no factory baseline taken." >&2
    return 0
  fi

  top=$(mktemp -d)
  if ! mount -o subvol=/ "$device" "$top" 2>&1; then
    echo "nixarchy-install: could not mount the btrfs top level of $device." >&2
    echo "  No factory baseline was taken. The install is unaffected; a factory" >&2
    echo "  reset on this machine will report that there is no baseline." >&2
    rmdir "$top"
    return 0
  fi

  # -r, read-only. A writable baseline is one that can drift, and a baseline
  # that has drifted is not a baseline -- it is a second copy of the machine
  # wearing the name of the first.
  btrfs subvolume snapshot -r "$top/@" "$top/@factory" || rc=1
  btrfs subvolume snapshot -r "$top/@home" "$top/@factory-home" || rc=1

  # Half a baseline is the #171 shape: something that looks present in every
  # check a person can think to make, and restores nothing when it is needed.
  # If either snapshot failed, remove whichever one was made.
  if [ "$rc" -ne 0 ]; then
    btrfs subvolume delete "$top/@factory" >/dev/null 2>&1 || true
    btrfs subvolume delete "$top/@factory-home" >/dev/null 2>&1 || true
  fi

  umount "$top"
  rmdir "$top"

  if [ "$rc" -ne 0 ]; then
    echo "nixarchy-install: the factory baseline could not be taken." >&2
    echo "  The install is complete and unaffected; a factory reset on this" >&2
    echo "  machine will report that there is no baseline to return to." >&2
  else
    echo "nixarchy-install: factory baseline taken (@factory, @factory-home)."
  fi
  return 0
}

main() {
  while [ $# -gt 0 ]; do
    case $1 in
      --dry-run) dry_run=true ;;
      --answers)
        shift
        [ $# -gt 0 ] || {
          echo "nixarchy-install: --answers needs a file" >&2
          exit 2
        }
        answers_file=$1
        ;;
      --from)
        shift
        [ $# -gt 0 ] || {
          echo "nixarchy-install: --from needs a git URL" >&2
          exit 2
        }
        from_repo=$1
        ;;
      --host)
        shift
        [ $# -gt 0 ] || {
          echo "nixarchy-install: --host needs a machine name" >&2
          exit 2
        }
        from_host=$1
        ;;
      -h | --help)
        usage
        exit 0
        ;;
      *)
        echo "nixarchy-install: unknown argument: $1" >&2
        usage >&2
        exit 2
        ;;
    esac
    shift
  done

  # --host is required with --from and meaningless without it. Refusing to
  # guess a machine name is cheaper than inventing a way to choose one, and a
  # repository with four machines in it has no obvious default.
  if [ -n "$from_repo" ] && [ -z "$from_host" ]; then
    echo "nixarchy-install: --from needs --host to say which machine this is" >&2
    exit 2
  fi
  if [ -n "$from_host" ] && [ -z "$from_repo" ]; then
    echo "nixarchy-install: --host only means something with --from" >&2
    exit 2
  fi

  if [ "$dry_run" = false ]; then
    require_root_and_uefi
  fi

  # Building somebody else's Nix as root is the cost of --from, and it is said
  # out loud before anything is cloned. In answers-file mode the file is the
  # consent, which is the doctrine --answers already runs on: a person who
  # wrote a repository URL into a file meant it.
  if [ -n "$from_repo" ] && ui_interactive; then
    echo
    echo "  $from_repo will be cloned, and its Nix will run as root on this"
    echo "  machine -- its disk-config.nix is what formats your disk."
    echo
    gum confirm --padding "$(ui_gum_pad)" "Install from $from_repo?" || exit 1
  fi

  # Cloned before anything is asked, because whether the repository already
  # describes this machine decides which questions there are.
  if [ -n "$from_repo" ]; then
    clone_repo
  fi

  if [ -n "$answers_file" ]; then
    resolve_answers
    read_answers "$answers_file"
    # --host names the machine, and clone_repo has already chosen $hostdir from
    # it. A hostname in the answers file cannot also name it: leaving both to
    # fight would give a machine whose directory and hostName disagree, which
    # evaluates and boots and is wrong.
    [ -n "$from_repo" ] && hostname=$from_host
    validate_answers
    ask_network
  elif [ "$from_host_exists" = true ]; then
    # The repository decided the username, the disk, the layout and the
    # timezone. What it cannot carry is the secret, so that is all there is to
    # ask -- and asking the rest again would invite an answer that the
    # repository then overrules, which is worse than not asking.
    ui_greeter
    ask_network
    ask_password
    ask_recovery
  else
    ui_greeter
    ask_network

    # "No" at the summary goes back to the questions, and that is the whole
    # reason the summary exists: somebody reads it, sees the hostname is wrong,
    # and says no. Exiting was the one response that made the screen useless --
    # and worse than useless on the ISO, where `Restart = "no"` means nothing
    # respawns and `conflicts = getty@tty1` means the login prompt does not come
    # back either. The installer left the user looking at a terminal with
    # nothing running on it, which reads exactly like a crash and can only be
    # escaped by a power cycle (#240).
    #
    # The network question stays outside the loop: it is the one step that
    # changes something outside this script, and asking somebody to reconnect
    # to wifi because they mistyped a hostname would be its own small insult.
    while :; do
      ask_keymap
      ask_identity
      ask_device
      ask_disk_mode
      ask_encrypt
      confirm_summary && break
    done
  fi

  if [ -n "$from_repo" ]; then
    finish_clone
  else
    write_flake
  fi

  if [ "$dry_run" = true ]; then
    # The placeholder write_flake left is exactly what a dry run wants: it
    # stands in for `nixos-generate-config --no-filesystems`, which defines no
    # fileSystems at all. A stub that defined `/` would conflict with disko's
    # definition of the same mountpoint and the flake would stop evaluating --
    # which is the whole reason step 7 passes --no-filesystems.
    git -C "$work" init -q
    git -C "$work" add -A
    echo "dry run: no disk touched. Flake written to:"
    echo "$work"
    exit 0
  fi

  # From here the screen belongs to the dashboard and every phase writes to the
  # log instead. A wall of store paths tells nobody anything they can act on,
  # and it makes an ordinary install look like something going wrong.
  local log=/var/log/nixarchy-install.log
  # Set once the log has been copied somewhere that outlives this session, so
  # the failure screen can name a path that will still exist after a reboot.
  local target_log=""
  local started rc=0 elapsed
  started=$(date +%s)

  # How long this took, written down where something other than a person
  # watching the screen can read it.
  #
  # "As fast as Omarchy, or faster" is a requirement, and a requirement nobody
  # measures is a wish. checks.install reads this and fails above a budget, so
  # the install getting slower is a red test rather than a thing somebody
  # eventually notices.
  #
  # In /run: it describes this boot of the installer, not the machine being
  # built, and it must not survive into the installed system.
  mkdir -p /run/nixarchy-install
  printf '{"started":%s,"phase":"installing"}\n' "$started" \
    >/run/nixarchy-install/state.json

  # An interrupt during the install has to land somewhere.
  #
  # Without this, Ctrl-C or a kill leaves the dashboard's redraw loop running,
  # the cursor hidden and the screen owned by a program that is no longer
  # there -- and the log, which is the only thing worth having at that point,
  # unmentioned. The EXIT trap ui_dashboard_start sets restores the cursor;
  # this adds the part that says what happened and where to read about it.
  trap 'ui_dashboard_stop; ui_failed "$log" 130; exit 130' INT TERM

  ui_dashboard_start
  # `&&` between the phases, not newlines, and it is load-bearing.
  #
  # This group's status is tested by `|| rc=$?`, and the comment on run_install
  # already says what that means: inside a compound command whose status is
  # tested, errexit does not fire. So with plain newlines a phase that returns
  # non-zero does not stop the ones after it, and the group reports the status
  # of the LAST command. run_install could fail, take_factory_snapshot could
  # succeed, and rc stayed 0.
  #
  # What that looked like: "the system did not build; nothing was installed",
  # then a factory baseline snapshotted off a disk with nothing on it, then the
  # finish screen, then exit 0. An install that did nothing reported success --
  # to the person watching, and to every check that trusts the exit status.
  # checks.install only caught it because it goes on to look for an ESP, and
  # the assertion it fails on is five frames from the cause.
  #
  # Chaining stops at the first failure and hands its status out, which is what
  # `|| rc=$?` was always meant to receive.
  {
    format_disk &&
      verify_subvolume_mounts &&
      generate_hardware_config &&
      install_flake_dir &&
      write_password_hash &&
      run_install &&
      take_factory_snapshot
  } >>"$log" 2>&1 || rc=$?
  ui_dashboard_stop
  # A frame already in flight when the drawer was killed can land AFTER the
  # finish screen is drawn, painting a stale 99% dashboard back over it -- and
  # a complete-looking dashboard that never changes again is indistinguishable
  # from a hang. Let any such frame finish before taking the screen back.
  sleep 1.2
  elapsed=$(($(date +%s) - started))

  # Written before the failure branch below, so a failed install is timed too:
  # "it died after forty minutes" and "it died after forty seconds" are
  # different bugs.
  printf '{"started":%s,"finished":%s,"seconds":%s,"exit":%s}\n' \
    "$started" "$(date +%s)" "$elapsed" "$rc" \
    >/run/nixarchy-install/state.json

  # The log, on the serial line, whatever happened. The dashboard deliberately
  # hides it on screen, which is right for someone watching an install and
  # useless for someone diagnosing one -- and a screen that stops updating
  # looks identical to a screen that has finished.
  if [ -w /dev/ttyS0 ]; then
    {
      echo "=============== nixarchy install log (exit $rc) ==============="
      cat "$log" 2>/dev/null
      echo "=============== end ==============================="
    } >/dev/ttyS0 2>&1 || true
  fi

  # And onto the disk, where it survives the reboot the next screen offers.
  #
  # The log lives on the live ISO. That is fine while somebody is looking at
  # it and useless the moment they do the thing the installer just told them
  # to do: a user whose install failed rebooted, found no bootloader entry,
  # went looking for a log and found two empty directories -- the target's
  # /var/log, which is a freshly created btrfs subvolume with nothing in it,
  # and nothing at all where the real log had been (#239). The serial dump
  # above is how checks.install reads this, and a laptop has no serial port.
  #
  # /mnt is still mounted here; nothing unmounts it before the finish screen.
  #
  # Mode 0600 and root-owned, and NOT copied to the ESP. The ESP was the
  # tempting place -- FAT32, readable from a live USB or another OS, exactly
  # where you want a diagnostic when the root filesystem will not mount. But
  # FAT32 has no permissions, so anything written there is readable by anyone
  # who picks up the disk, and this installer handles a crypt hash that
  # installer/template/host/configuration.nix already describes as
  # "offline-crackable at leisure by anyone who reads it". Nothing is known to
  # put a secret in this log -- write_password_hash writes to a file under
  # umask 077 and disko takes the passphrase from a key file, so its trace
  # shows a path rather than the secret -- but "nothing is known to" is not
  # the standard for putting a file somewhere unreadable permissions cannot
  # protect it.
  if [ -d /mnt/var/log ]; then
    ( umask 077 && cat "$log" >/mnt/var/log/nixarchy-install.log ) 2>/dev/null \
      && chown 0:0 /mnt/var/log/nixarchy-install.log 2>/dev/null \
      && target_log=/var/log/nixarchy-install.log
  fi

  if [ "$rc" -ne 0 ]; then
    ui_failed "$log" "$rc" "${target_log:-}"
    exit "$rc"
  fi

  ui_finished "$elapsed" "$username"
}

# Guarded so the functions above can be sourced and exercised without running
# an install. The substitution's original stress case -- a crypt hash full of
# $ and & -- no longer passes through it, because the hash is written to a file
# now rather than into the template. subst stays as it is anyway: it is proven,
# and being literal on the replacement side is the correct behaviour for a
# device path or a timezone too.
if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  main "$@"
fi
