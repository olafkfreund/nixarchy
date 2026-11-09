{ pkgs, installScript }:
pkgs.runCommand "nixarchy-installer-disk-identity" { } ''
  for fn in disk_rows ask_device remember_disk check_disks replace_missing_disk confirm_repo_disks check_free_partitions partition_free_space format_disk read_answers install_attempts main; do
    sed -n "/^$fn()/,/^}/p" ${installScript} > "$fn.sh"
    test -s "$fn.sh" || { echo "missing installer function: $fn" >&2; exit 1; }
  done

  cat > test.sh <<'EOF'
  disk_paths=() disk_reals=() disk_wwns=() disk_serials=() disk_sizes=() disk_models=() disk_by_paths=()
  disk_by_path_dir=$PWD/by-path
  mkdir -p "$disk_by_path_dir"
  allow_unidentified_disk=false
  . ./remember_disk.sh
  . ./check_disks.sh
  . ./confirm_repo_disks.sh
  . ./format_disk.sh
  . ./check_free_partitions.sh
  fails=0
  failed() { echo "FAILED $1"; fails=$((fails + 1)); }
  readlink() { printf '%s\n' "$2"; }
  boot_medium() { :; }
  ui_interactive() { return 1; }
  late=0 due=0 udev_fail=0 rl_fail=
  udevadm() {
    [ "$1" = settle ] || return 0
    echo settle >> events
    if [ "$due" -gt 0 ]; then due=$((due - 1)); [ "$due" -gt 0 ] || touch esp root; fi
    [ "$udev_fail" != 1 ] || ! grep -Fxq build events || return 1
  }
  sleep() { if [ "$late" = 1 ]; then rm -f esp root; late=0; due=2; fi; }
  L2='  Partition entries may exist and signatures may have been cleared. Inspect before retrying.'
  msg_case() {
    local name=$1 line=$2 l2=$3 rc
    shift 3
    "$@" >out 2>err
    rc=$?
    [ "$rc" = 1 ] || failed "$name: exit status $rc, not 1"
    grep -Fxq -- "$line" err || failed "$name: stderr lacks: $line"
    [ -z "$l2" ] || grep -Fxq -- "$L2" err || failed "$name: stderr lacks the inspect line"
  }
  printf 'alpha\n' > a-id
  printf 'bravo\n' > b-id
  lsblk() {
    case "$2" in
      TYPE) echo disk ;;
      WWN) case "$3" in /dev/a | /dev/replaced) cat a-id ;; /dev/b) cat b-id ;; esac ;;
      SERIAL) [ "''${NO_ID_A:-false}" = true ] && [ "$3" = /dev/a -o "$3" = /dev/replaced ] || echo serial-"$3" ;;
      SIZE) echo "''${SIZE_A:-64000000000}" ;;
      MODEL) echo "''${MODEL_A-QEMU}" ;;
      NAME,TYPE) printf '/dev/a disk\n/dev/b disk\n' ;;
      NAME,SIZE,MODEL,SERIAL) echo "disk 64G test serial-$3" ;;
    esac
  }

  # Missing identifiers refuse before any formatting.
  lsblk_missing() { case "$2" in TYPE) echo disk ;; esac; }
  old_lsblk=$(declare -f lsblk)
  eval "$(declare -f lsblk_missing | sed '1s/lsblk_missing/lsblk/')"
  if remember_disk /dev/a >msg 2>&1; then failed "a disk with no WWN or serial was accepted"; fi
  grep -q 'Choose a disk whose identity can be checked' msg || failed "missing-ID refusal has no remedy"
  grep -Fq -- '--allow-unidentified-disk' msg || failed "missing-ID refusal omits override"
  grep -Fq 'virt-manager' msg || failed "missing-ID refusal omits virtual-disk guidance"
  eval "$old_lsblk"
  test ''${#disk_paths[@]} -eq 0 || failed "unidentified disk was recorded"
  echo "ok missing WWN and serial refused"

  # The explicit override pins a weaker but observable fallback identity.
  : > a-id
  NO_ID_A=true
  allow_unidentified_disk=true
  remember_disk /dev/a >msg 2>&1 || failed "override did not accept a no-serial disk"
  grep -q WARNING msg || failed "fallback acceptance was not warned"
  SIZE_A=65000000000
  if check_disks >msg 2>&1; then failed "fallback size swap was accepted"; fi
  SIZE_A=64000000000 MODEL_A=other
  if check_disks >msg 2>&1; then failed "fallback model swap was accepted"; fi
  MODEL_A=QEMU
  readlink() { [ "$2" != /dev/a ] || { echo /dev/replaced; return; }; echo "$2"; }
  if check_disks >msg 2>&1; then failed "fallback path swap was accepted"; fi
  readlink() { echo "$2"; }
  check_disks >msg 2>&1 || failed "unchanged fallback identity was refused"
  echo "ok override accepts no-serial disk and pins path size model"
  disk_paths=() disk_reals=() disk_wwns=() disk_serials=() disk_sizes=() disk_models=() disk_by_paths=()
  MODEL_A=
  remember_disk /dev/a >msg 2>&1 || failed "empty virtio model blocked explicit override"
  check_disks >msg 2>&1 || failed "empty-model fallback was refused"
  MODEL_A=QEMU
  check_disks >msg 2>&1 || failed "model appeared after empty-model baseline"
  echo "ok explicit override accepts empty virtio model with path and size"

  disk_paths=() disk_reals=() disk_wwns=() disk_serials=() disk_sizes=() disk_models=() disk_by_paths=()
  ln -s /dev/a "$disk_by_path_dir/pci-port-a"
  printf '/dev/a\n' > port-owner
  readlink() {
    [ "$2" != "$disk_by_path_dir/pci-port-a" ] || { cat port-owner; return; }
    echo "$2"
  }
  remember_disk /dev/a >msg 2>&1 || failed "by-path disk was not recorded"
  [ "''${disk_by_paths[0]}" = "$disk_by_path_dir/pci-port-a" ] || failed "available by-path link was not pinned"
  printf '/dev/b\n' > port-owner
  if check_disks >msg 2>&1; then failed "same-size same-model moved port was accepted"; fi
  printf '/dev/a\n' > port-owner
  check_disks >msg 2>&1 || failed "unchanged by-path link was refused"
  readlink() { echo "$2"; }
  echo "ok available by-path link catches same-size same-model port move"
  disk_paths=() disk_reals=() disk_wwns=() disk_serials=() disk_sizes=() disk_models=() disk_by_paths=()
  allow_unidentified_disk=false
  NO_ID_A=false
  printf 'alpha\n' > a-id

  # Exercise the real chooser and the real answers branch, not source greps.
  . ./disk_rows.sh
  . ./ask_device.sh
  ui_screen() { :; }
  ui_widget_height() { echo 1; }
  ui_gum_pad() { echo 0; }
  ui_abort() { failed "wizard aborted instead of re-asking"; return 1; }
  disk_under_floor() { return 1; }
  gum() {
    count=$(cat picks 2>/dev/null || echo 0)
    count=$((count + 1)); echo "$count" > picks
    if [ "$count" -eq 1 ]; then echo /dev/a; else echo /dev/b; fi
  }
  : > a-id
  NO_ID_A=true
  ask_device >msg 2>&1 || failed "wizard could not re-ask after no-ID refusal"
  [ "$(cat picks)" = 2 ] && [ "''${disk_paths[0]}" = /dev/b ] || failed "wizard did not record the second disk"
  grep -Fq 'nixarchy-install --allow-unidentified-disk' msg || failed "wizard omitted exact ISO relaunch command"
  NO_ID_A=false
  printf 'alpha\n' > a-id
  echo "ok wizard re-asks and records accepted disk"

  . ./read_answers.sh
  printf 'device=/dev/b\nallow_unidentified_disk=yes\n' > answers
  allow_unidentified_disk=false
  read_answers answers || failed "answers override did not parse"
  [ "$allow_unidentified_disk" = true ] || failed "answers override was ignored"
  echo "ok answers key enables explicit no-ID fallback"
  (
    . ./main.sh
    from_repo= from_host_exists=false answers_fetched= dry_run=false
    resolve_answers() { :; }
    validate_answers() { :; }
    ask_network() { :; }
    write_flake() { work=$PWD/dry-flake; mkdir -p "$work"; }
    git() { [ "$3" != add ] || printf '%s\n' "''${disk_paths[0]:-missing}" > answers-recorded; }
    main --dry-run --answers "$PWD/answers"
  ) >msg 2>&1 || failed "answers dry-run branch did not complete"
  [ "$(cat answers-recorded 2>/dev/null)" = /dev/b ] || failed "answers branch did not record disk identity"
  echo "ok answers branch records disk identity"

  printf 'device=/dev/a\n' > answers-no-id
  : > a-id
  NO_ID_A=true allow_unidentified_disk=false
  (
    . ./main.sh
    from_repo= from_host_exists=false answers_fetched= dry_run=false
    resolve_answers() { :; }
    validate_answers() { :; }
    ask_network() { :; }
    write_flake() { work=$PWD/dry-flake; mkdir -p "$work"; }
    git() { [ "$3" != add ] || printf '%s\n' "''${disk_paths[0]:-missing}" > cli-recorded; }
    main --dry-run --answers "$PWD/answers-no-id" --allow-unidentified-disk
  ) >msg 2>&1 || failed "CLI no-ID override did not complete"
  [ "$(cat cli-recorded 2>/dev/null)" = /dev/a ] || failed "CLI override did not record no-ID disk"
  printf 'alpha\n' > a-id
  NO_ID_A=false
  echo "ok command-line override accepts no-ID disk"

  disk_paths=() disk_reals=() disk_wwns=() disk_serials=() disk_sizes=() disk_models=() disk_by_paths=()
  allow_unidentified_disk=false

  remember_disk /dev/a || failed "valid disk could not be recorded"
  printf 'replacement\n' > a-id
  if check_disks >msg 2>&1; then failed "same-path replacement was accepted"; fi
  grep -q 'different WWN or serial' msg || failed "replacement refusal was silent"
  if check_disks >msg 2>&1; then failed "retry re-baselined the replacement"; fi
  test "''${disk_wwns[0]}" = alpha || failed "retry changed the original fingerprint"
  (
    . ./install_attempts.sh
    log=$PWD/retry.log target_log= rc=0
    install_once() { check_disks > /dev/null 2>&1; rc=$?; echo "$rc" >> attempt-results; }
    ui_failed() {
      n=$(wc -l < attempt-results)
      [ "$n" -ne 1 ] || return 3
      return 1
    }
    install_attempts
  ) >msg 2>&1 && failed "retry accepted a replacement disk"
  [ "$(wc -l < attempt-results)" -eq 2 ] && [ "$(tr -d '\n' < attempt-results)" = 11 ] || failed "retry did not preserve both refusals"
  echo "ok replacement and retry refused against original identity"

  disk_paths=() disk_reals=() disk_wwns=() disk_serials=() disk_sizes=() disk_models=() disk_by_paths=()
  printf 'alpha\n' > a-id
  printf 'bravo\n' > b-id
  NIX_FLAGS=() work=/fixture hostname=host from_host_exists=true from_repo=fixture
  nix() { printf '/dev/a\n/dev/b\n'; }
  confirm_repo_disks >msg 2>&1 || failed "repo disks were not recorded"
  test ''${#disk_paths[@]} -eq 2 || failed "not every repo disk was recorded"
  printf 'replacement\n' > b-id
  if check_disks >msg 2>&1; then failed "second repo disk was not checked"; fi
  echo "ok every repo disk is checked"

  disk_paths=() disk_reals=() disk_wwns=() disk_serials=() disk_sizes=() disk_models=() disk_by_paths=()
  printf 'alpha\n' > a-id
  printf 'bravo\n' > b-id
  remember_disk /dev/a || failed "format target was not recorded"
  disk_mode=whole luks_passphrase=secret NIX_FLAGS=() work=/fixture hostname=host
  findmnt() { touch touched-before-build; return 1; }
  printf '#!/bin/sh\ntouch disko-ran\n' > disko; chmod +x disko
  nix() {
    if [ "$1" = eval ]; then echo false
    else printf 'replacement\n' > a-id; echo "$PWD/disko"
    fi
  }
  if format_disk >msg 2>&1; then failed "disk swapped during build was formatted"; fi
  test ! -e disko-ran || failed "disko ran on the replacement"
  echo "ok build-time disk swap refused before disko"

  rm -f touched-before-build
  if format_disk >msg 2>&1; then failed "pre-write disk swap was accepted"; fi
  test ! -e touched-before-build || failed "format phase began before identity check"
  echo "ok pre-write disk swap refused"

  disk_paths=() disk_reals=() disk_wwns=() disk_serials=() disk_sizes=() disk_models=() disk_by_paths=()
  printf 'alpha\n' > a-id
  remember_disk /dev/a || failed "free-space target was not recorded"
  device=/dev/a
  # The links resolve to nodes of their own, and only while the link exists.
  readlink() {
    [ "$2" != "$rl_fail" ] || return 1
    case "$2" in
      /dev/disk/by-partlabel/nixarchy-esp) if [ -e esp ]; then echo "$PWD/node-esp"; else echo "$2"; fi ;;
      /dev/disk/by-partlabel/nixarchy-root) if [ -e root ]; then echo "$PWD/node-root"; else echo "$2"; fi ;;
      *) echo "$2" ;;
    esac
  }
  old_lsblk=$(declare -f lsblk)
  lsblk() {
    if [ "$2" = PKNAME ]; then
      [ ! -e pkname-fail ] || return 1
      case "$3" in "$PWD/node-esp") echo a ;; "$PWD/node-root") cat root-parent ;; esac
    elif [ "$2" = MODEL ] && [ -e model-fail ]; then
      return 1
    else
      (eval "$old_lsblk"; lsblk "$@")
    fi
  }
  touch esp root node-esp node-root
  sed 's|\[ -b |[ -e |g' check_free_partitions.sh > cfp-fixture.sh
  . ./cfp-fixture.sh
  printf 'b\n' > root-parent
  if check_free_partitions >msg 2>&1; then failed "foreign root partition was accepted"; fi
  grep -q 'does not belong to the selected disk' msg || failed "foreign-partition refusal has no explanation"
  printf 'a\n' > root-parent
  check_free_partitions >msg 2>&1 || failed "selected disk partitions were refused"
  sed "s|/dev/disk/by-partlabel/nixarchy-esp|$PWD/esp|g; s|/dev/disk/by-partlabel/nixarchy-root|$PWD/root|g; s|\[ -b |[ -e |g" partition_free_space.sh > pfs-fixture.sh
  . ./pfs-fixture.sh
  eval "$(declare -f check_free_partitions | sed '1s/check_free_partitions/real_check_free_partitions/')"
  check_free_partitions() {
    if [ "$late" != 0 ] || [ "$due" != 0 ] || [ ! -e esp ] || [ ! -e root ]; then
      failed "check_free_partitions ran before the late re-read settled"
    fi
    late=0 due=0
    touch esp root
    real_check_free_partitions "$@"
  }
  free_start=2048 free_end=500000 FREE_ESP_MIB=1 encrypt=false
  free_space_possible() { free_start=2048; free_end=500000; return 0; }
  blockdev() { echo 512; }
  sgdisk() { touch first-sgdisk; late=1; return 0; }
  partx() { :; }
  wipefs() { echo "$*" > wipefs-args; touch wipefs-called; return 0; }
  printf 'b\n' > root-parent
  if partition_free_space >msg 2>&1; then failed "foreign partition reached wipefs"; fi
  [ ! -e wipefs-called ] || failed "wipefs touched a foreign partition"
  printf 'a\n' > root-parent
  partition_free_space >msg 2>&1 || failed "owned partitions could not reach wipefs"
  [ -e wipefs-called ] || failed "owned partitions never reached wipefs"
  echo "ok free-space waits out the late partition re-read"
  [ "$(cat wipefs-args)" = "-a $PWD/node-esp $PWD/node-root" ] || failed "wipefs was not given the checked device nodes"
  echo "ok wipefs clears the nodes that were checked"
  wipefs() { return 1; }
  if partition_free_space >msg 2>&1; then failed "wipefs failure was swallowed"; fi
  wipefs() { echo "$*" > wipefs-args; touch wipefs-called; return 0; }
  rm -f first-sgdisk wipefs-called
  printf 'replacement\n' > a-id
  if partition_free_space >msg 2>&1; then failed "swapped disk reached sgdisk"; fi
  [ ! -e first-sgdisk ] || failed "sgdisk ran on swapped disk"
  printf 'alpha\n' > a-id
  echo "ok free-space rechecks identity before sgdisk and parentage before wipefs"

  # Every refusal says which call refused, on stderr.
  rl_fail=/dev/a
  msg_case "case a" "nixarchy-install: could not resolve /dev/a. Nothing further was formatted; start again." "" check_disks
  rl_fail=
  touch model-fail
  msg_case "case b" "nixarchy-install: lsblk could not read the WWN, serial, size or model of /dev/a. Nothing further was formatted; start again." "" check_disks
  rm -f model-fail
  device=/dev/by-id-a rl_fail=/dev/by-id-a
  msg_case "case c" "nixarchy-install: could not resolve /dev/by-id-a." l2 check_free_partitions
  device=/dev/a rl_fail=/dev/disk/by-partlabel/nixarchy-root
  msg_case "case d" "nixarchy-install: could not resolve /dev/disk/by-partlabel/nixarchy-root." l2 check_free_partitions
  rl_fail=
  rm -f node-root
  msg_case "case e" "nixarchy-install: /dev/disk/by-partlabel/nixarchy-root does not point at a block device ($PWD/node-root)." l2 check_free_partitions
  touch node-root
  touch pkname-fail
  msg_case "case f" "nixarchy-install: lsblk could not read the parent disk of $PWD/node-esp." l2 check_free_partitions
  rm -f pkname-fail
  wipefs() { return 3; }
  msg_case "case g" "nixarchy-install: wipefs could not clear $PWD/node-esp and $PWD/node-root (exit 3)." l2 partition_free_space
  wipefs() { echo "$*" > wipefs-args; touch wipefs-called; return 0; }
  disk_mode=whole luks_passphrase=secret
  nix() { if [ "$1" = eval ]; then echo true; else echo "$PWD/disko"; fi; }
  rm -f disko-ran
  mkdir -p /tmp/nixarchy-luks.key
  msg_case "case h" "nixarchy-install: could not write the LUKS key file. Nothing was formatted." "" format_disk
  rmdir /tmp/nixarchy-luks.key
  [ ! -e disko-ran ] || failed "case h: disko ran without its key"
  : > events
  nix() { if [ "$1" = eval ]; then echo false; else echo build >> events; echo "$PWD/disko"; fi; }
  udev_fail=1
  msg_case "case i" "nixarchy-install: udevadm settle did not finish after the disko build. Nothing was formatted; start again." "" format_disk
  udev_fail=0
  [ ! -e disko-ran ] || failed "case i: disko ran after a failed settle"
  echo "ok every refusal names its call"

  # The post-build identity check must see settled links.
  : > events
  eval "$(declare -f check_disks | sed '1s/check_disks/real_check_disks/')"
  check_disks() { echo check >> events; real_check_disks "$@"; }
  format_disk >msg 2>&1 || failed "settled post-build format did not complete"
  [ "$(sed -n '/^build$/,$p' events | tr '\n' ' ')" = "build settle check " ] || failed "post-build check_disks did not follow a settle"
  eval "$(declare -f real_check_disks | sed '1s/real_check_disks/check_disks/')"
  rm -f disko-ran
  echo "ok post-build identity check follows a settle"

  printf 'alpha\n' > a-id
  rm -f disko-ran
  disk_mode=free
  partition_free_space() { :; }
  check_free_partitions() { return 1; }
  nix() { [ "$1" = eval ] && echo false || echo "$PWD/disko"; }
  if format_disk >msg 2>&1; then failed "post-build foreign partition was accepted"; fi
  [ ! -e disko-ran ] || failed "disko ran on post-build foreign partition"
  echo "ok post-build parent refusal prevents disko"

  test "$fails" -eq 0 || exit 1
  EOF
  bash test.sh
  touch "$out"
''
