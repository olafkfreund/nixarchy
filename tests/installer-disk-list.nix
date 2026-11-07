{ pkgs, installScript }:
pkgs.runCommand "nixarchy-installer-disk-list" { } ''
  for fn in disk_rows disk_under_floor ask_device; do
    sed -n "/^$fn()/,/^}/p" ${installScript} >> functions.sh
    grep -q "^$fn()" functions.sh || { echo "missing installer function: $fn" >&2; exit 1; }
  done
  . ./functions.sh

  lsblk() {
    case "$1 $2" in
      '-dnpo NAME,TYPE') cat disks ;;
      '-dnro RM,TRAN') awk -v dev="$3" '$1 == dev { print $2, $3; found=1 } END { if (!found) exit 1 }' probes ;;
      '-dno SIZE') printf '64G\n' ;;
      '-dno MODEL') printf 'TEST\n' ;;
      '-bdno SIZE') if [ "$3" = /dev/tiny ]; then printf '4096\n'; else printf '68719476736\n'; fi ;;
      *) echo "unexpected lsblk call: $*" >&2; return 1 ;;
    esac
  }
  boot_medium() { printf '%s\n' "$BOOT"; }
  MIN_DISK_GIB=32
  BOOT=
  check() {
    disk_rows > actual
    diff -u expected actual || { echo "disk rows: $1" >&2; exit 1; }
    echo "ok $1"
  }

  printf '%s\n' '/dev/usb disk' '/dev/nvme disk' > disks
  printf '%s\n' '/dev/usb 1 usb' '/dev/nvme 0 nvme' > probes
  printf '%s\n' '/dev/nvme 64G TEST' '/dev/usb 64G TEST' > expected
  check usb-before-nvme

  printf '%s\n' '/dev/usb 0 usb' '/dev/nvme 0 nvme' > probes
  check usb-enclosure-rm-zero

  printf '%s\n' '/dev/usb 1 ' '/dev/nvme 0 nvme' > probes
  check removable-empty-transport

  printf '%s\n' '/dev/usb disk' '/dev/mmc disk' > disks
  printf '%s\n' '/dev/usb 1 usb' '/dev/mmc 0 mmc' > probes
  printf '%s\n' '/dev/mmc 64G TEST' '/dev/usb 64G TEST' > expected
  check emmc-before-usb

  printf '%s\n' '/dev/nvme disk' '/dev/sdreader disk' > disks
  printf '%s\n' '/dev/nvme 0 nvme' '/dev/sdreader 1 mmc' > probes
  printf '%s\n' '/dev/nvme 64G TEST' '/dev/sdreader 64G TEST' > expected
  check sd-reader-after-nvme

  printf '%s\n' '/dev/a disk' '/dev/b disk' > disks
  printf '%s\n' '/dev/a 0 sata' '/dev/b 0 nvme' > probes
  printf '%s\n' '/dev/a 64G TEST' '/dev/b 64G TEST' > expected
  check two-internal

  printf '%s\n' '/dev/a 1 usb' '/dev/b 1 ' > probes
  check only-removable

  printf '%s\n' '/dev/a disk' > disks
  printf '%s\n' '/dev/a 0 sata' > probes
  printf '%s\n' '/dev/a 64G TEST' > expected
  check one-disk

  printf '%s\n' '/dev/a disk' '/dev/b disk' '/dev/c disk' > disks
  printf '%s\n' '/dev/a 1 usb' '/dev/c 1 usb' > probes
  printf '%s\n' '/dev/b 64G TEST' '/dev/a 64G TEST' '/dev/c 64G TEST' > expected
  check failed-probe-is-internal

  printf '%s\n' '/dev/fd0 disk' '/dev/zram0 disk' '/dev/boot disk' '/dev/a disk' '/dev/tiny disk' > disks
  printf '%s\n' '/dev/boot 1 usb' '/dev/a 0 sata' '/dev/tiny 0 sata' > probes
  BOOT=/dev/boot
  printf '%s\n' '/dev/a 64G TEST' > expected
  check boot-floppy-zram-small-dropped

  BOOT=
  printf '%s\n' '/dev/usb disk' '/dev/nvme disk' > disks
  printf '%s\n' '/dev/usb 1 usb' '/dev/nvme 0 nvme' > probes
  printf '%s\n' '/dev/nvme 64G TEST' '/dev/usb 64G TEST' > expected
  ui_screen() { :; }
  ui_widget_height() { printf '10\n'; }
  ui_gum_pad() { printf '0\n'; }
  ui_abort() { exit 1; }
  remember_disk() { [ "$1" = /dev/nvme ]; }
  gum() { cat > gum-stdin; printf '/dev/nvme\n'; }
  ask_device
  diff -u expected gum-stdin
  echo 'ok ask_device passes ordered rows to gum'
  touch "$out"
''
