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

ask_identity() {
  ui_screen "Let's set up your user account..."
  local why
  while :; do
    username=$(gum input --padding "$(ui_gum_pad)" --placeholder "Alphanumeric, no spaces (like dhh)" --prompt "Username> ")
    why=$(validate_username "$username") && break
    gum style --foreground 1 "$why"
  done

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

# Encryption is on unless the user opts out, matching upstream: the hint is dim
# and Ctrl+C at the warning is the way out. That is upstream's shape, and it
# means the safe answer is the one you get by doing nothing.
ask_encrypt() {
  ui_screen "Ready to install"
  ui_left "\e[33mEverything on $device will be overwritten. There is no recovery possible.\e[0m"
  ui_left "\e[90mPress Ctrl+C for an unencrypted install.\e[0m"
  echo

  # Three outcomes, not two. Yes encrypts; No aborts, because "no" to a
  # destructive question should never mean "do it anyway, differently"; and an
  # interrupt is upstream's hidden opt-out, which gum reports as 130.
  local rc=0
  gum confirm --padding "$(ui_gum_pad)" "Encrypt and install to $device?" || rc=$?
  case $rc in
    0) encrypt=true ;;
    130) encrypt=false ;;
    *) exit 1 ;;
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

  reuse_baked_initrd "$work/hardware-configuration.nix"
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
  nix "${NIX_FLAGS[@]}" build --dry-run "${SUBSTITUTE_FLAGS[@]}" \
    "/mnt/etc/nixos#nixosConfigurations.$hostname.config.system.build.toplevel" 2>&1 |
    head -40 || true

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
    ask_network
  else
    ui_greeter
    ask_network
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

  # From here the screen belongs to the dashboard and every phase writes to the
  # log instead. A wall of store paths tells nobody anything they can act on,
  # and it makes an ordinary install look like something going wrong.
  local log=/var/log/nixarchy-install.log
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
  {
    format_disk
    generate_hardware_config
    install_flake_dir
    run_install
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

  if [ "$rc" -ne 0 ]; then
    ui_failed "$log" "$rc"
    exit "$rc"
  fi

  ui_finished "$elapsed" "$username"
}

# Guarded so the functions above can be sourced and exercised without running
# an install: that is how write_flake's substitution is tested (a crypt hash
# full of $ and & is exactly the input a naive implementation ruins).
if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  main "$@"
fi
