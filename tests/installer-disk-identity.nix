{ pkgs, installScript }:
pkgs.runCommand "nixarchy-installer-disk-identity" { } ''
  for fn in ask_device remember_disk check_disks confirm_repo_disks check_free_partitions partition_free_space format_disk main; do
    sed -n "/^$fn()/,/^}/p" ${installScript} > "$fn.sh"
    test -s "$fn.sh" || { echo "missing installer function: $fn" >&2; exit 1; }
  done

  cat > test.sh <<'EOF'
  disk_paths=() disk_reals=() disk_wwns=() disk_serials=()
  . ./remember_disk.sh
  . ./check_disks.sh
  . ./confirm_repo_disks.sh
  . ./format_disk.sh
  . ./check_free_partitions.sh
  fails=0
  failed() { echo "FAILED $1"; fails=$((fails + 1)); }
  grep -Fq 'remember_disk "$device" || ui_abort' ask_device.sh || failed "wizard selection does not record disk identity"
  grep -Fq 'remember_disk "$device" || exit 1' main.sh || failed "answers selection does not record disk identity"
  echo "ok wizard and answers paths record disk identity"
  readlink() { printf '%s\n' "$2"; }
  boot_medium() { :; }
  ui_interactive() { return 1; }
  printf 'alpha\n' > a-id
  printf 'bravo\n' > b-id
  lsblk() {
    case "$2" in
      TYPE) echo disk ;;
      WWN) case "$3" in /dev/a) cat a-id ;; /dev/b) cat b-id ;; esac ;;
      SERIAL) echo serial-"$3" ;;
      NAME,SIZE,MODEL,SERIAL) echo "disk 64G test serial-$3" ;;
    esac
  }

  # Missing identifiers refuse before any formatting.
  lsblk_missing() { case "$2" in TYPE) echo disk ;; esac; }
  old_lsblk=$(declare -f lsblk)
  eval "$(declare -f lsblk_missing | sed '1s/lsblk_missing/lsblk/')"
  if remember_disk /dev/a >msg 2>&1; then failed "a disk with no WWN or serial was accepted"; fi
  grep -q 'Choose a disk whose identity can be checked' msg || failed "missing-ID refusal has no remedy"
  eval "$old_lsblk"
  test ''${#disk_paths[@]} -eq 0 || failed "unidentified disk was recorded"
  echo "ok missing WWN and serial refused"

  remember_disk /dev/a || failed "valid disk could not be recorded"
  printf 'replacement\n' > a-id
  if check_disks >msg 2>&1; then failed "same-path replacement was accepted"; fi
  grep -q 'different WWN or serial' msg || failed "replacement refusal was silent"
  if check_disks >msg 2>&1; then failed "retry re-baselined the replacement"; fi
  test "''${disk_wwns[0]}" = alpha || failed "retry changed the original fingerprint"
  echo "ok replacement and retry refused against original identity"

  disk_paths=() disk_reals=() disk_wwns=() disk_serials=()
  printf 'alpha\n' > a-id
  printf 'bravo\n' > b-id
  NIX_FLAGS=() work=/fixture hostname=host from_host_exists=true from_repo=fixture
  nix() { printf '/dev/a\n/dev/b\n'; }
  confirm_repo_disks >msg 2>&1 || failed "repo disks were not recorded"
  test ''${#disk_paths[@]} -eq 2 || failed "not every repo disk was recorded"
  printf 'replacement\n' > b-id
  if check_disks >msg 2>&1; then failed "second repo disk was not checked"; fi
  echo "ok every repo disk is checked"

  disk_paths=() disk_reals=() disk_wwns=() disk_serials=()
  printf 'alpha\n' > a-id
  printf 'bravo\n' > b-id
  remember_disk /dev/a || failed "format target was not recorded"
  disk_mode=whole luks_passphrase=secret NIX_FLAGS=() work=/fixture hostname=host
  findmnt() { touch touched-before-build; return 1; }
  printf '#!/bin/sh\ntouch disko-ran\n' > disko; chmod +x disko
  nix() { printf 'replacement\n' > a-id; echo "$PWD/disko"; }
  if format_disk >msg 2>&1; then failed "disk swapped during build was formatted"; fi
  test ! -e disko-ran || failed "disko ran on the replacement"
  echo "ok build-time disk swap refused before disko"

  rm -f touched-before-build
  if format_disk >msg 2>&1; then failed "pre-write disk swap was accepted"; fi
  test ! -e touched-before-build || failed "format phase began before identity check"
  echo "ok pre-write disk swap refused"

  disk_paths=() disk_reals=() disk_wwns=() disk_serials=()
  printf 'alpha\n' > a-id
  remember_disk /dev/a || failed "free-space target was not recorded"
  device=/dev/a
  readlink() {
    case "$2" in
      /dev/disk/by-partlabel/nixarchy-esp) echo /dev/esp ;;
      /dev/disk/by-partlabel/nixarchy-root) echo /dev/root ;;
      *) echo "$2" ;;
    esac
  }
  old_lsblk=$(declare -f lsblk)
  lsblk() {
    if [ "$2" = PKNAME ]; then
      case "$3" in /dev/esp) echo a ;; /dev/root) cat root-parent ;; esac
    else
      (eval "$old_lsblk"; lsblk "$@")
    fi
  }
  printf 'b\n' > root-parent
  if check_free_partitions >msg 2>&1; then failed "foreign root partition was accepted"; fi
  grep -q 'does not belong to the selected disk' msg || failed "foreign-partition refusal has no explanation"
  printf 'a\n' > root-parent
  check_free_partitions >msg 2>&1 || failed "selected disk partitions were refused"
  grep -Fq 'check_free_partitions || return 1' partition_free_space.sh || failed "partition ownership is not checked before wipefs"
  grep -Fq 'check_free_partitions || { rm -f /tmp/nixarchy-luks.key; return 1; }' format_disk.sh || failed "partition ownership is not rechecked after build"
  echo "ok both free-space partitions belong to selected disk at both boundaries"

  test "$fails" -eq 0 || exit 1
  EOF
  bash test.sh
  touch "$out"
''
