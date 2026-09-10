{ pkgs, previewScript }:
# nixarchy-preview's preflights and its disk lifecycle (#486, #489), driven
# with an environment that lies -- the manner of tests/reinstall-iso.nix,
# because they are the same refusals: ENOSPC and OOM deaths surface levels
# from the cause, and the stale-qcow2 trap has a receipt in this repo
# (vm/configuration.nix:98-109, stale notification history replayed from a
# reused disk).
#
# Three probe truth tables, extracted and driven on their own; then the
# assertions that keep the extraction honest -- that main still calls each
# probe, and calls it BEFORE `nix build`, because a probe tested here and
# wired nowhere would be #133 again -- and the honesty strings #485 makes
# non-negotiable: a green preview is evidence, not proof.
pkgs.runCommand "nixarchy-preview" { } ''
  set -o pipefail

  # ------------------------------------------------------------------------
  # disk_verdict: the whole #489 truth table. `stale` is the row the
  # feature exists for -- a disk and no flag must be a refusal, never a
  # guess in either direction.
  # ------------------------------------------------------------------------
  sed -n '/^disk_verdict()/,/^}/p' ${previewScript} > dv.sh
  test -s dv.sh || { echo "disk_verdict is not in nixarchy-preview any more" >&2; exit 1; }

  cat > dvt.sh <<'EOF'
  . ./dv.sh
  fails=0
  t() {
    want=$1 name=$2 exists=$3 fresh=$4 keep=$5
    g=$(disk_verdict "$exists" "$fresh" "$keep")
    if [ "$g" = "$want" ]; then
      echo "  ok      $name -> $g"
    else
      echo "  FAILED  $name: wanted $want, got '$g'"
      fails=$((fails + 1))
    fi
  }
  t none        "first preview, no flags"        0 0 0
  t stale       "old disk, no flags: refuse"     1 0 0
  t fresh       "old disk, --fresh"              1 1 0
  t fresh       "no disk, --fresh (harmless)"    0 1 0
  t keep        "old disk, --keep"               1 0 1
  t keep-missing "--keep with nothing to keep"   0 0 1
  t contradict  "--fresh --keep together"        1 1 1
  t contradict  "--fresh --keep, even diskless"  0 1 1
  exit $fails
  EOF
  bash dvt.sh

  # ------------------------------------------------------------------------
  # check_ram: refuse what will not fit, and never refuse on a meminfo it
  # could not read.
  # ------------------------------------------------------------------------
  sed -n '/^check_ram()/,/^}/p' ${previewScript} > cr.sh
  test -s cr.sh || { echo "check_ram is not in nixarchy-preview any more" >&2; exit 1; }

  cat > crt.sh <<'EOF'
  red() { echo "$1"; }
  MEM_MIN=4096
  . ./cr.sh
  fails=0
  t() {
    want=$1 name=$2 avail_kb=$3
    m=$(mktemp)
    [ -z "$avail_kb" ] || printf 'MemAvailable: %s kB\n' "$avail_kb" > "$m"
    if PREVIEW_MEMINFO=$m check_ram 8192 >got 2>&1; then g=proceed; else g=refuse; fi
    if [ "$g" = "$want" ]; then
      echo "  ok      $name ($g)"
    else
      echo "  FAILED  $name: wanted $want, got $g"; sed 's/^/            /' got
      fails=$((fails + 1))
    fi
  }
  t refuse  "4 GB available, 8 GB wanted"   4194304
  t proceed "32 GB available, 8 GB wanted"  33554432
  # Tolerance: a probe that cannot read must not invent a refusal.
  t proceed "meminfo answers nothing"       ""
  exit $fails
  EOF
  bash crt.sh

  # ------------------------------------------------------------------------
  # check_disk: refuse what will not fit, refuse a tmpfs whatever its
  # number says (df's figure there is RAM), and tolerate a silent df.
  # ------------------------------------------------------------------------
  sed -n '/^check_disk()/,/^}/p' ${previewScript} > cd.sh
  test -s cd.sh || { echo "check_disk is not in nixarchy-preview any more" >&2; exit 1; }

  cat > cdt.sh <<'EOF'
  red() { echo "$1"; }
  . ./cd.sh
  df() {
    [ -n "$DF_LINE" ] || return 1
    printf 'Type 1M-blocks\n%s\n' "$DF_LINE"
  }
  fails=0
  t() {
    want=$1 name=$2 line=$3
    if DF_LINE=$line check_disk /somewhere 8192 "the preview" >got 2>&1; then g=proceed; else g=refuse; fi
    if [ "$g" = "$want" ]; then
      echo "  ok      $name ($g)"
    else
      echo "  FAILED  $name: wanted $want, got $g"; sed 's/^/            /' got
      fails=$((fails + 1))
    fi
  }
  t refuse  "4 GB free, 8 GB needed"    "btrfs 4000M"
  t proceed "40 GB free, 8 GB needed"   "btrfs 40000M"
  t refuse  "tmpfs with a big number"   "tmpfs 64000M"
  t proceed "df answers nothing"        ""
  exit $fails
  EOF
  bash cdt.sh

  # ------------------------------------------------------------------------
  # detect_kvm: the three-way answer, because existence alone is not it --
  # a /dev/kvm the user cannot open falls back to TCG just as silently.
  # ------------------------------------------------------------------------
  sed -n '/^detect_kvm()/,/^}/p' ${previewScript} > dk.sh
  test -s dk.sh || { echo "detect_kvm is not in nixarchy-preview any more" >&2; exit 1; }

  cat > dkt.sh <<'EOF'
  . ./dk.sh
  fails=0
  t() {
    want=$1 name=$2 dev=$3
    g=$(PREVIEW_KVM_DEV=$dev detect_kvm)
    if [ "$g" = "$want" ]; then
      echo "  ok      $name -> $g"
    else
      echo "  FAILED  $name: wanted $want, got '$g'"
      fails=$((fails + 1))
    fi
  }
  touch openable; chmod 600 openable
  touch locked;   chmod 000 locked
  t kvm     "an openable device"       ./openable
  t nogroup "a device with no access"  ./locked
  t none    "no device at all"         ./absent
  exit $fails
  EOF
  bash dkt.sh

  echo "the probes refuse what they must and only that"

  # ------------------------------------------------------------------------
  # The call sites. Function tests stay green with every call deleted,
  # which is the #133 shape: each probe must run, and run BEFORE the
  # `nix build` -- a preflight after the build starts refuses nothing,
  # and a disk verdict after it wastes the build it refuses.
  # `|| true` because stdenv sets pipefail and a no-match grep must reach
  # the named refusal below.
  # ------------------------------------------------------------------------
  build_line=$(grep -n 'nix build "$PREVIEW_ATTR"' ${previewScript} | cut -d: -f1 | head -1 || true)
  [ -n "$build_line" ] || { echo "the script no longer builds via PREVIEW_ATTR; retarget this check" >&2; exit 1; }
  for probe in 'disk_verdict "$exists"' 'explain_kvm "$(detect_kvm)"' 'check_ram "''${mem:-$MEM_MB}"' 'check_disk /nix/store' 'check_disk "$STATE_DIR"'; do
    line=$(grep -n "$probe" ${previewScript} | cut -d: -f1 | head -1 || true)
    [ -n "$line" ] || { echo "main() never calls: $probe" >&2; exit 1; }
    [ "$line" -lt "$build_line" ] || {
      echo "$probe runs after the build starts; a preflight there refuses nothing" >&2
      exit 1
    }
  done

  # The runner must be pinned to the managed disk name, or qemu-vm.nix's
  # cwd default quietly comes back and #489 reopens.
  grep -q 'export NIX_DISK_IMAGE="$disk"' ${previewScript} || {
    echo "the runner is no longer pinned via NIX_DISK_IMAGE; the qcow2" >&2
    echo "falls back to the cwd default, which is the #489 trap itself" >&2
    exit 1
  }

  # ------------------------------------------------------------------------
  # The honesty strings. #485: a preview that reads as proof is a trap.
  # Each pattern includes the printing call and its opening quote -- match
  # the call, not the string (tests/AGENTS.md), because the script's own
  # comments say all of this too and a bare grep stays green with the
  # printed line deleted. Found by breaking it, per §1.
  # ------------------------------------------------------------------------
  for claim in \
    'red "A green preview is strong evidence, not proof."' \
    'echo "  bootloader, so it does not verify your bootloader, your real GPU,"' \
    'red "$disk already exists -- a previous preview made it, and booting the"'; do
    grep -qF "$claim" ${previewScript} || {
      echo "the script no longer says: $claim" >&2
      echo "#485 makes that honesty non-negotiable -- the vmVariant boots VM" >&2
      echo "filesystems and a VM bootloader, and a stale disk replays the" >&2
      echo "previous preview's state" >&2
      exit 1
    }
  done

  echo "the preflights are wired ahead of the build, and the words are honest"
  touch $out
''
