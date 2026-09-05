{ pkgs, installScript }:
# check_store_space, driven with plans nix really prints and a df that lies.
#
# Its answer selects a build store rather than refusing an install: non-zero
# means "the live store cannot hold this, build into the target instead".
#
# A live ISO's store is a RAM-backed overlay over the squashfs -- half the
# machine's memory. Everything nix fetches or builds lands there before any of
# it reaches the disk, and when it fills the install does not stop: it dies
# partway with "No space left on device", several levels under a "1 dependency
# failed" that names none of it. installer/vm.nix says as much about the test
# VM, which escapes with writableStoreUseTmpfs = false. The ISO cannot.
#
# One user met it as a machine that installed and had no bootloader, and only
# found it by running df himself: 7.8G, 100% used, nothing left.
#
# A fixed threshold would not have caught that. He had 7.8G free when the
# install started, which passes any figure worth setting -- it filled during
# the build. The decision has to come from the size nix itself prints, so this
# checks the parse and the comparison rather than a constant.
#
# A runCommand and not a VM: the function is shell, the inputs are strings, and
# the 25-minute install check cannot see this case at all -- it installs onto a
# machine whose store fits, which is the only shape that does not fail.
pkgs.runCommand "nixarchy-installer-store-space" { } ''
    # The function on its own. Extracting it rather than sourcing install.sh,
    # which runs a wizard when sourced.
    sed -n '/^check_store_space()/,/^}/p' ${installScript} > f.sh
    test -s f.sh || { echo "check_store_space is not in install.sh any more" >&2; exit 1; }

    cat > t.sh <<'EOF'
    . ./f.sh
    # $FREE bytes available, so the comparison is what is under test and not
    # whatever the builder happens to be sitting on.
    df() {
      case "$*" in
        *-B1*) printf 'F 1B-blocks Used Available Cap Mounted\noverlay 8000000000 0 %s 100%% /nix/store\n' "$FREE" ;;
        *)     printf 'F Size Used Avail Cap Mounted\noverlay 7.8G 7.8G 0 100%% /nix/store\n' ;;
      esac
    }
    fails=0
    t() {
      want=$1 name=$2 free=$3 plan=$4
      if FREE=$free check_store_space "$plan" >out 2>&1; then got=proceed; else got=refuse; fi
      if [ "$got" = "$want" ]; then
        echo "  ok      $name ($got)"
      else
        echo "  FAILED  $name: wanted $want, got $got"; sed 's/^/            /' out
        fails=$((fails + 1))
      fi
    }

    GB=1073741824
    FETCH21='these 489 paths will be fetched (8.1 GiB download, 21.0 GiB unpacked):'

    # The reported case: 21 GiB of paths, 7.8G of RAM-backed store.
    t refuse  "21 GiB needed, 7.8G free -> target"      8371830784        "$FETCH21"
    # The same install on a machine with room.
    t proceed "21 GiB needed, 900G free -> live"      $((900 * GB))     "$FETCH21"
    # Units below GiB are parsed too, or a small overflow reads as no overflow.
    t refuse  "120 MiB needed, 100 MiB free"  $((100 * 1048576)) \
      'these 12 paths will be fetched (40.2 MiB download, 120.5 MiB unpacked):'
    # The normal install: the image carries the closure, nothing is fetched.
    t proceed "nothing to fetch"              8371830784        'these 0 derivations will be built'
    # Tolerance. This exists to name a failure that already happens; a plan it
    # cannot read must not become a new way to refuse an install that would work.
    t proceed "unparseable plan"              1                 'some other nix message entirely'
    t proceed "builds, no sizes printed"      1                 'these 4 derivations will be built:'
    exit $fails
  EOF
    bash t.sh

    # And that the target-store fallback asks for a store that will ACCEPT what
  # it is handed.
  #
  # A path built on the installing machine has no signature, and a fresh store
  # refuses unsigned paths -- "cannot add path ... because it lacks a signature
  # by a trusted key". NixOS' own assembly derivations are allowSubstitutes =
  # false, so they are always built and always unsigned; the fallback therefore
  # fails on every real machine without this.
  #
  # Asserted here because nothing else can. tests/install.nix and
  # tests/free-space.nix both set require-sigs = false INSIDE the test VM -- and
  # say why -- so an install check passes whether or not the installer asks for
  # it. The ISO does not set it. That gap is exactly how #251 shipped broken and
  # went green.
  # The URI form, not the bare setting -- the comment above it in install.sh
  # says "require-sigs=false" too, so a looser pattern matches the explanation
  # and stays green with the flag deleted. Found by breaking it.
  grep -q '/mnt?require-sigs=false' ${installScript} || {
    echo "" >&2
    echo "the target-store build does not pass require-sigs=false." >&2
    echo "" >&2
    echo "Paths built on the installing machine are unsigned, and a fresh" >&2
    echo "store rejects them:" >&2
    echo "" >&2
    echo "  cannot add path '...' because it lacks a signature by a trusted key" >&2
    echo "" >&2
    echo "No install check can catch this: they set require-sigs = false in" >&2
    echo "the test VM, so /mnt accepts unsigned paths there regardless." >&2
    exit 1
  }
  grep -q 'eval-store auto' ${installScript} || {
    echo "the target-store build no longer splits the evaluation store; see #249" >&2
    exit 1
  }

  echo "check_store_space refuses what will not fit and nothing else"

  # ------------------------------------------------------------------------
  # preflight_build (#300): the disk must not be wiped before anything proves
  # the build could start. Same doctrine as above -- the function on its own,
  # driven with stubs that lie.
  # ------------------------------------------------------------------------
  sed -n '/^preflight_build()/,/^}/p' ${installScript} > pf.sh
  test -s pf.sh || { echo "preflight_build is not in install.sh any more" >&2; exit 1; }
  grep '^on_net_image()' ${installScript} >> pf.sh

  cat > pt.sh <<'EOF'
  NIX_FLAGS=() SUBSTITUTE_FLAGS=()
  SUBSTITUTERS="https://nixarchy.cachix.org"
  work=/nonexistent hostname=h
  . ./pf.sh
  # The one thing that must never happen before the probes pass.
  wipefs() { touch wipefs-called; }
  git() { :; }
  curl() { [ "$CURL_OK" = 1 ]; }
  nix() {
    if [ "$NIX_OK" = 1 ]; then echo 'these 0 derivations will be built'; else
      # Long on purpose: a real dry-run of a desktop closure is thousands of
      # lines, which is what makes an early-exiting reader (`grep -m1`, `grep
      # -q`) kill its producer with EPIPE -- the #273 shape. A short plan
      # cannot reproduce that race; this one does.
      echo "error: unable to download 'https://github.com/x/archive/r.tar.gz'"
      seq 1 200000 | sed 's/^/error: cascade line /'
      return 1
    fi
  }
  fails=0
  t() {
    want=$1 name=$2 img=$3 curlok=$4 nixok=$5
    if [ "$img" = net ]; then on_net_image() { return 0; }; else on_net_image() { return 1; }; fi
    if CURL_OK=$curlok NIX_OK=$nixok preflight_build >out 2>&1; then got=proceed; else got=refuse; fi
    if [ "$got" = "$want" ]; then
      echo "  ok      $name ($got)"
    else
      echo "  FAILED  $name: wanted $want, got $got"; sed 's/^/            /' out
      fails=$((fails + 1))
    fi
  }

  # No marker: checks.install's shape -- no network, seeded store. Probing
  # here would fail a passing check, so nothing may be probed at all.
  t proceed "no image marker, network dead"      none 0 0
  # The filed case: net image, cache dark. Refused, and the message names
  # the network rather than emitting a dependency cascade.
  t refuse  "net image, substituter unreachable" net  0 1
  grep -qi 'network' out || { echo "  FAILED  refusal does not name the network"; fails=$((fails+1)); }
  # The network died after ask_network let it through: evaluation fails.
  t refuse  "net image, flake input unreachable" net  1 0
  grep -qi 'network' out || { echo "  FAILED  eval refusal does not name the network"; fails=$((fails+1)); }
  # The #273 regression, which reached a user: an early-exiting grep killing
  # its producer puts "printf: Broken pipe" immediately above the refusal, on
  # the one screen where noise costs the most.
  ! grep -qi 'broken pipe' out || { echo "  FAILED  refusal is preceded by Broken pipe noise"; fails=$((fails+1)); }
  # And a network that works installs as before.
  t proceed "net image, everything answers"      net  1 1

  # (c) of #300: across every scenario, including the refusals, the disk was
  # never touched.
  [ ! -e wipefs-called ] || { echo "  FAILED  preflight called wipefs"; fails=$((fails+1)); }
  exit $fails
  EOF
  bash pt.sh

  # And that main() actually runs it ahead of the wipe. The function tests
  # above stay green with the call site deleted, which would be #133 again:
  # written, extracted, asserted, and run by nothing.
  # `|| true` because stdenv sets pipefail, and a grep with no match must
  # reach the named refusal below rather than kill the script mid-pipe.
  pf_line=$(grep -n 'preflight_build || exit 1' ${installScript} | cut -d: -f1 | head -1 || true)
  fmt_line=$(grep -n '^    format_disk &&' ${installScript} | cut -d: -f1 | head -1 || true)
  [ -n "$pf_line" ] || { echo "main() no longer calls preflight_build" >&2; exit 1; }
  [ -n "$fmt_line" ] && [ "$pf_line" -lt "$fmt_line" ] || {
    echo "preflight_build does not run before format_disk; #300 is back" >&2; exit 1;
  }

  echo "preflight_build refuses before the wipe, and main runs it there"

  # ------------------------------------------------------------------------
  # format_disk must hand out the diskoScript's status, not the rm's.
  #
  # It runs inside main()'s `|| rc=$?` chain, where bash suppresses errexit,
  # so nothing implicit checks the build or the run. Unchecked, a failed
  # build executed "" (127, ignored), a partial disko run was ignored too,
  # and the function returned the status of `rm -f` -- always 0. The failure
  # then surfaced ~30 minutes later at bootctl, on a disk erased at minute
  # one, with an error naming the bootloader instead of disko.
  # ------------------------------------------------------------------------
  sed -n '/^format_disk()/,/^}/p' ${installScript} > fd.sh
  test -s fd.sh || { echo "format_disk is not in install.sh any more" >&2; exit 1; }

  cat > fdt.sh <<'EOF'
  NIX_FLAGS=() work=/nonexistent hostname=h
  disk_mode=whole luks_passphrase=pw
  . ./fd.sh
  findmnt() { return 1; }   # nothing mounted at /mnt
  fails=0
  t() {
    want=$1 name=$2
    if format_disk >out 2>&1; then got=proceed; else got=refuse; fi
    if [ "$got" = "$want" ]; then
      echo "  ok      $name ($got)"
    else
      echo "  FAILED  $name: wanted $want, got $got"; sed 's/^/            /' out
      fails=$((fails + 1))
    fi
  }

  # The build fails: nothing to execute, and the status must say so.
  nix() { echo "error: builder failed" >&2; return 1; }
  t refuse "diskoScript build fails -> format_disk fails"
  grep -qi disko out || { echo "  FAILED  build refusal does not name disko"; fails=$((fails+1)); }

  # The build succeeds and disko itself dies partway.
  printf '#!/bin/sh\nexit 3\n' > fake-disko-bad; chmod +x fake-disko-bad
  nix() { echo "$PWD/fake-disko-bad"; }
  t refuse "diskoScript exits 3 -> format_disk fails"
  grep -qi disko out || { echo "  FAILED  disko refusal does not name disko"; fails=$((fails+1)); }

  # And a run that works still works.
  printf '#!/bin/sh\nexit 0\n' > fake-disko-ok; chmod +x fake-disko-ok
  nix() { echo "$PWD/fake-disko-ok"; }
  t proceed "diskoScript succeeds -> format_disk succeeds"
  exit $fails
  EOF
  bash fdt.sh

  # verify_subvolume_mounts is format_disk's backstop, and /mnt/boot has to
  # be in it: a disko run that mounted the four btrfs subvolumes and left the
  # ESP alone used to sail through, and the failure surfaced at bootctl.
  sed -n '/^verify_subvolume_mounts()/,/^}/p' ${installScript} > vs.sh
  test -s vs.sh || { echo "verify_subvolume_mounts is not in install.sh any more" >&2; exit 1; }
  cat > vst.sh <<'EOF'
  . ./vs.sh
  findmnt() {
    case "$*" in
      *--mountpoint\ /mnt/boot*) return 1 ;;  # everything mounted but the ESP
      *) return 0 ;;
    esac
  }
  if verify_subvolume_mounts >out 2>&1; then
    echo "  FAILED  an unmounted /mnt/boot was let through"
    exit 1
  fi
  grep -q '/mnt/boot' out || { echo "  FAILED  refusal does not name /mnt/boot"; exit 1; }
  echo "  ok      unmounted /mnt/boot is refused by name"
  findmnt() { return 0; }
  verify_subvolume_mounts >out 2>&1 || { echo "  FAILED  a fully mounted target was refused"; exit 1; }
  echo "  ok      fully mounted target proceeds"
  EOF
  bash vst.sh

  echo "format_disk fails when disko does, and the backstop checks the ESP"

  # ------------------------------------------------------------------------
  # boot_medium must resolve the parent disk for every naming convention.
  #
  # The old sed 's/[0-9]*$//' turned /dev/nvme0n1p1 into "/dev/nvme0n1p",
  # which matches no disk, so the exclusion excluded nothing and the
  # installer offered to format the medium it booted from. The file's own
  # comment calls that a bug, not an edge case.
  # ------------------------------------------------------------------------
  sed -n '/^boot_medium()/,/^}/p' ${installScript} > bm.sh
  test -s bm.sh || { echo "boot_medium is not in install.sh any more" >&2; exit 1; }
  cat > bmt.sh <<'EOF'
  . ./bm.sh
  findmnt() { printf '%s\n' "$SRC"; }
  lsblk() { printf '%s\n' "$PARENT"; }
  fails=0
  t() {
    src=$1 parent=$2 want=$3
    got=$(SRC=$src PARENT=$parent boot_medium)
    if [ "$got" = "$want" ]; then
      echo "  ok      $src -> $got"
    else
      echo "  FAILED  $src: wanted $want, got '$got'"
      fails=$((fails + 1))
    fi
  }
  t /dev/sdb1      sdb      /dev/sdb
  t /dev/nvme0n1p1 nvme0n1  /dev/nvme0n1
  t /dev/mmcblk0p1 mmcblk0  /dev/mmcblk0
  # An image dd'd to the whole device: no parent, the device is the medium.
  t /dev/sdb       ""       /dev/sdb
  exit $fails
  EOF
  bash bmt.sh
  echo "boot_medium excludes the right disk for sd, nvme and mmcblk names"

  # ------------------------------------------------------------------------
  # partition_free_space: a failed sgdisk must be named, not narrated over.
  #
  # errexit is dead here too (same chain), so an unchecked sgdisk failure
  # fell through to the settle loop, which timed out and printed "The
  # partitions were created" -- asserting a creation that never happened, in
  # free-space mode, on the one disk with somebody else's OS on it.
  # ------------------------------------------------------------------------
  sed -n '/^partition_free_space()/,/^}/p' ${installScript} > pfs.sh
  test -s pfs.sh || { echo "partition_free_space is not in install.sh any more" >&2; exit 1; }
  cat > pfst.sh <<'EOF'
  device=/dev/vdz free_start=2048 free_end=20000000 free_why=""
  encrypt=false FREE_ESP_MIB=2048
  . ./pfs.sh
  free_space_possible() { return 0; }
  blockdev() { echo 512; }
  partx() { :; }
  udevadm() { :; }
  sleep() { :; }               # the settle loop must not cost 15 real seconds
  wipefs() { touch wipefs-called; }
  sgdisk() { return 1; }
  fails=0
  if ( partition_free_space ) >out 2>&1; then
    echo "  FAILED  a failed sgdisk was treated as success"; fails=$((fails+1))
  fi
  grep -q sgdisk out || { echo "  FAILED  the refusal does not name sgdisk"; sed 's/^/            /' out | head -4; fails=$((fails+1)); }
  ! grep -q 'were created' out || { echo "  FAILED  the message claims partitions were created"; fails=$((fails+1)); }
  [ ! -e wipefs-called ] || { echo "  FAILED  wipefs ran after sgdisk failed"; fails=$((fails+1)); }
  [ "$fails" = 0 ] && echo "  ok      failed sgdisk is refused by name, nothing wiped"
  exit $fails
  EOF
  bash pfst.sh
  echo "partition_free_space names sgdisk when sgdisk is what failed"

  # ------------------------------------------------------------------------
  # Escape at a prompt must say what happened, not black-screen (#240).
  #
  # The question flow runs at top level where errexit and pipefail are LIVE:
  # gum exits non-zero on Escape, the `var=$(... gum ...)` assignment carries
  # that status, and errexit killed the script before any guard on the next
  # line could run. Run the real functions in a fresh `set -euo pipefail`
  # process -- the same regime install.sh runs under -- and demand words on
  # the way out. Driven as a process, not a function, because errexit
  # suppression does not cross the process boundary.
  # ------------------------------------------------------------------------
  {
    echo 'set -euo pipefail'
    echo 'ui_screen() { :; }'
    echo 'ui_left() { printf "%b\n" "$1"; }'
    echo 'ui_indent() { cat; }'
    echo 'ui_widget_height() { echo 10; }'
    echo 'ui_gum_pad() { echo 0; }'
    echo 'gum() { return 130; }   # Escape, at every prompt'
    echo 'loadkeys() { :; }'
    sed -n '/^ui_abort()/,/^}/p' ${installScript}
    sed -n '/^validate_username()/,/^}/p' ${installScript}
    sed -n '/^ask_keymap()/,/^}/p' ${installScript}
    sed -n '/^ask_identity()/,/^}/p' ${installScript}
    sed -n '/^ask_disk_mode()/,/^}/p' ${installScript}
  } > esc-common.sh
  cat > esct.sh <<'EOF'
  fails=0
  t() {
    name=$1; shift
    { cat esc-common.sh; printf '%s\n' "$@"; } > esc-run.sh
    if bash esc-run.sh >out 2>&1; then
      echo "  FAILED  $name: escape was treated as an answer"; fails=$((fails+1)); return
    fi
    if grep -q 'Stopped before anything was written' out; then
      echo "  ok      $name says it stopped"
    else
      echo "  FAILED  $name: died with no word of what happened"
      sed 's/^/            /' out | head -3
      fails=$((fails + 1))
    fi
  }
  printf 'us\tus\n' > keymaps
  t "escape at the keymap"    'UI_KEYMAPS=keymaps' 'ask_keymap'
  t "escape at the username"  'ask_identity'
  t "escape at the disk mode" 'device=/dev/vda' \
    'free_space_possible() { return 0; }' \
    'free_region_human() { echo 10G; }' \
    'lsblk() { echo part; }' \
    'ask_disk_mode'
  exit $fails
  EOF
  bash esct.sh
  echo "escape at a prompt stops with words on the screen, not a black one"
    touch $out
''
