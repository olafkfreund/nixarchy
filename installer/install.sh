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

# The path is spliced in at build time, so shellcheck cannot follow it here.
# shellcheck source=./gum-env.sh disable=SC1091
source @gumenv@

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

dry_run=false

usage() {
  cat <<'USAGE'
nixarchy-install -- install nixarchy onto a disk.

  nixarchy-install              ask, then install
  nixarchy-install --dry-run    ask, write the flake to a temp directory,
                                touch no disk, print the directory and stop
  nixarchy-install --help       this

Run as root from a NixOS live medium, on a UEFI machine. It formats the disk
you choose, completely. There is no dual-boot path yet.
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

ask_keymap() {
  local list
  list=$(find "$KEYMAPS" -name '*.map.gz' -printf '%f\n' | sed 's/\.map\.gz$//' | sort -u)
  keymap=$(printf '%s\n' "$list" | gum filter --placeholder "us" --value "us")
  keymap=${keymap:-us}
  loadkeys "$keymap" 2>/dev/null || true
}

ask_identity() {
  while :; do
    username=$(gum input --placeholder "Alphanumeric, no spaces (like dhh)" --prompt "Username> ")
    if ! [[ $username =~ ^[a-z_][a-z0-9_-]*$ ]]; then
      gum style --foreground 1 "Not a usable Linux username."
      continue
    fi
    # root exists; nixbld* belong to the daemon. Creating either here produces
    # an install that fails late and confusingly.
    case $username in
      root | nixbld*)
        gum style --foreground 1 "That name is taken by the system."
        continue
        ;;
    esac
    break
  done

  while :; do
    local pw pw2
    pw=$(gum input --password --prompt "Password> ")
    pw2=$(gum input --password --prompt "Confirm> ")
    if [ "$pw" != "$pw2" ]; then
      gum style --foreground 1 "Those do not match."
      continue
    fi
    if [ -z "$pw" ]; then
      gum style --foreground 1 "An empty password would lock you out of sudo."
      continue
    fi
    # One password for the user, root and the disk, as upstream does: the
    # passphrase you type at boot is the one that logs you in.
    password_hash=$(mkpasswd -m sha-512 "$pw")
    luks_passphrase=$pw
    unset pw pw2
    break
  done

  while :; do
    hostname=$(gum input --placeholder "nixarchy" --prompt "Hostname> ")
    hostname=${hostname:-nixarchy}
    [[ $hostname =~ ^[a-z0-9]([a-z0-9-]*[a-z0-9])?$ ]] && break
    gum style --foreground 1 "Letters, digits and hyphens; not starting or ending with one."
  done

  timezone=$(
    find "$TZDIR" -type f -not -path '*/posix/*' -not -path '*/right/*' |
      sed "s#.*/zoneinfo/##" | grep '/' | sort |
      gum filter --placeholder "UTC" --value "UTC"
  )
  timezone=${timezone:-UTC}
}

# The medium we booted from must never be in the list. An installer that offers
# to format itself is a bug, not an edge case.
boot_medium() {
  findmnt -no SOURCE /iso 2>/dev/null | sed 's/[0-9]*$//' || true
}

ask_device() {
  local exclude list
  exclude=$(boot_medium)
  # TYPE=="disk" drops the ISO's loop devices; the exclusion drops the stick.
  list=$(lsblk -dnpo NAME,SIZE,MODEL,TYPE | awk '$NF=="disk"' | sed 's/ disk$//')
  if [ -n "$exclude" ]; then
    list=$(printf '%s\n' "$list" | grep -v "^$exclude ") || true
  fi
  if [ -z "$list" ]; then
    echo "nixarchy-install: no disk to install onto." >&2
    exit 1
  fi
  device=$(printf '%s\n' "$list" | gum choose | awk '{print $1}')
  [ -n "$device" ] || exit 1
}

# Encryption is on unless the user opts out, matching upstream: the hint is dim
# and Ctrl+C at the warning is the way out. That is upstream's shape, and it
# means the safe answer is the one you get by doing nothing.
ask_encrypt() {
  gum style --foreground 3 "Everything on $device will be overwritten. There is no recovery possible."
  gum style --faint "Press Ctrl+C for an unencrypted install."

  # Three outcomes, not two. Yes encrypts; No aborts, because "no" to a
  # destructive question should never mean "do it anyway, differently"; and an
  # interrupt is upstream's hidden opt-out, which gum reports as 130.
  local rc=0
  gum confirm "Encrypt and install to $device?" || rc=$?
  case $rc in
    0) encrypt=true ;;
    130) encrypt=false ;;
    *) exit 1 ;;
  esac
}

confirm_summary() {
  gum style --bold "Ready to install:"
  {
    printf 'Hostname,%s\n' "$hostname"
    printf 'Username,%s\n' "$username"
    printf 'Password,********\n'
    printf 'Timezone,%s\n' "$timezone"
    printf 'Keyboard,%s\n' "$keymap"
    printf 'Disk,%s\n' "$device"
    printf 'Encrypted,%s\n' "$encrypt"
  } | gum table --separator ',' --print --columns "Setting,Value"
  gum confirm "Does this look right?"
}

# ---------------------------------------------------------------------------
# Doing it
# ---------------------------------------------------------------------------

write_flake() {
  work=$(mktemp -d)
  cp -r "$TEMPLATE"/. "$work"
  chmod -R u+w "$work"

  local f
  for f in "$work/flake.nix" "$work/configuration.nix"; do
    subst "$f" '@hostname@' "$hostname"
    subst "$f" '@username@' "$username"
    subst "$f" '@device@' "$device"
    subst "$f" '@timezone@' "$timezone"
    subst "$f" '@keymap@' "$keymap"
    subst "$f" '@password_hash@' "$password_hash"
    # Quoted in the template because a bare token is not parseable Nix; the
    # quotes go with the token. An encrypted disk has already authenticated the
    # user by the time a greeter would ask, so autologin follows encryption.
    subst "$f" '"@encrypt@"' "$encrypt"
    subst "$f" '"@autologin@"' "$encrypt"
  done
}

format_disk() {
  # The passphrase file disko's passwordFile points at. Written with umask 077,
  # removed as soon as the format is done; it never reaches the installed
  # system, whose initrd prompts instead.
  ( umask 077 && printf '%s' "$luks_passphrase" >/tmp/nixarchy-luks.key )

  # Evaluated from the USER'S flake, not ours: the same disk-config.nix the
  # installed machine imports is the one that formats the disk. That is the
  # whole reason the layout is a file rather than a parted script.
  nix "${NIX_FLAGS[@]}" run \
    "$work#nixosConfigurations.$hostname.config.system.build.diskoScript"

  rm -f /tmp/nixarchy-luks.key
}

generate_hardware_config() {
  # --no-filesystems because disko owns fileSystems; a second definition of /
  # fails the build. --show-hardware-config prints to stdout, where the plain
  # --root form would also write a configuration.nix over the template's.
  nixos-generate-config --root /mnt --no-filesystems --show-hardware-config \
    >"$work/hardware-configuration.nix"
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

run_install() {
  nixos-install --root /mnt --flake "/mnt/etc/nixos#$hostname" --no-root-password \
    "${NIX_FLAGS[@]}" \
    --option extra-substituters "$SUBSTITUTERS" \
    --option extra-trusted-public-keys "$TRUSTED_KEYS"
}

main() {
  while [ $# -gt 0 ]; do
    case $1 in
      --dry-run) dry_run=true ;;
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

  if [ "$dry_run" = false ]; then
    require_root_and_uefi
  fi

  ask_keymap
  ask_identity
  ask_device
  ask_encrypt
  confirm_summary || exit 1

  write_flake

  if [ "$dry_run" = true ]; then
    # Empty, and deliberately so: this stands in for what
    # `nixos-generate-config --no-filesystems` produces, which defines no
    # fileSystems at all. A stub that defines `/` conflicts with disko's
    # definition of the same mountpoint and the flake stops evaluating -- which
    # is the whole reason step 7 passes --no-filesystems.
    printf '{ ... }:\n{ }\n' >"$work/hardware-configuration.nix"
    git -C "$work" init -q
    git -C "$work" add -A
    echo "dry run: no disk touched. Flake written to:"
    echo "$work"
    exit 0
  fi

  format_disk
  generate_hardware_config
  install_flake_dir
  run_install

  gum style --bold "Done."
  echo "Reboot, then log in as $username."
  echo "This machine's configuration is /etc/nixos -- a git repository with"
  echo "nothing committed yet. Edit it and run 'nh os switch'."
}

# Guarded so the functions above can be sourced and exercised without running
# an install: that is how write_flake's substitution is tested (a crypt hash
# full of $ and & is exactly the input a naive implementation ruins).
if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  main "$@"
fi
