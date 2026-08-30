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
answers_file=""

# set -u: every answer the two paths share is initialised here, so a key the
# answers file omits fails validation rather than aborting on an unbound
# variable three functions later.
device=""
encrypt=""
hostname=""
username=""
password_hash=""
luks_passphrase=""
timezone=""
keymap=""

usage() {
  cat <<'USAGE'
nixarchy-install -- install nixarchy onto a disk.

  nixarchy-install              ask, then install
  nixarchy-install --dry-run    ask, write the flake to a temp directory,
                                touch no disk, print the directory and stop
  nixarchy-install --answers F  take every answer from F and ask nothing
  nixarchy-install --help       this

The answers file is one key=value per line, # for comments, no quoting:

  device=/dev/vda           whole disk, not a partition
  encrypt=yes               yes or no
  luks_passphrase=...       required when encrypt=yes
  hostname=nixarchy
  username=alice
  password_hash=$6$...      from `mkpasswd -m sha-512`; or
  password=hunter2          plaintext, hashed here -- for tests
  timezone=Europe/London
  keymap=us

It holds a password in clear, which is inherent to installing without being
asked. Nothing copies it onto the installed machine.

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

ask_identity() {
  local why
  while :; do
    username=$(gum input --placeholder "Alphanumeric, no spaces (like dhh)" --prompt "Username> ")
    why=$(validate_username "$username") && break
    gum style --foreground 1 "$why"
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
    why=$(validate_hostname "$hostname") && break
    gum style --foreground 1 "$why"
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
# Unattended
#
# The answers file is parsed line by line and never sourced. It lives on
# removable media or inside a test derivation, and running it as shell so that
# a stray $ or backtick executes is a mistake waiting to happen.
#
# It also holds a plaintext password and a LUKS passphrase, unavoidably. The
# installer never copies it anywhere that persists.
# ---------------------------------------------------------------------------
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
      encrypt) encrypt=$value ;;
      luks_passphrase) luks_passphrase=$value ;;
      hostname) hostname=$value ;;
      username) username=$value ;;
      password) password=$value ;;
      password_hash) password_hash=$value ;;
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
  printf 'hostname=%s username=%s device=%s encrypt=%s timezone=%s keymap=%s\n' \
    "$hostname" "$username" "$device" "$encrypt" "$timezone" "$keymap"

  # The rest of the script speaks true/false; the file speaks yes/no because
  # that is what a person writing one expects.
  [ "$encrypt" = yes ] && encrypt=true || encrypt=false
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

  # A placeholder, because of an ordering the flake creates: configuration.nix
  # imports ./hardware-configuration.nix, and the disko script that formats the
  # disk is evaluated *out of this flake* -- so the flake has to evaluate before
  # there is a mounted disk to generate a hardware config from. An empty module
  # is enough for that evaluation and is replaced by the real one at step 7.
  printf '{ ... }:\n{ }\n' >"$work/hardware-configuration.nix"
}

format_disk() {
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
  # What would have to be built, printed before doing it. On a machine with no
  # network an unseeded build input is the difference between an install and a
  # confusing cascade of source downloads, and this names it once rather than
  # leaving it to be inferred from whatever failed first.
  nix "${NIX_FLAGS[@]}" build --dry-run \
    "/mnt/etc/nixos#nixosConfigurations.$hostname.config.system.build.toplevel" 2>&1 |
    head -40 || true

  # nixos-install takes --option, not --extra-experimental-features: it is not
  # a nix subcommand and rejects the flag outright.
  nixos-install --root /mnt --flake "/mnt/etc/nixos#$hostname" --no-root-password \
    --option extra-experimental-features "nix-command flakes" \
    --option extra-substituters "$SUBSTITUTERS" \
    --option extra-trusted-public-keys "$TRUSTED_KEYS"
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

  if [ -n "$answers_file" ]; then
    read_answers "$answers_file"
    validate_answers
  else
    ask_keymap
    ask_identity
    ask_device
    ask_encrypt
    confirm_summary || exit 1
  fi

  write_flake

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
