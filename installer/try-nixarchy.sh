#!/usr/bin/env bash
# Try nixarchy in a virtual machine, from any Linux, with no Nix installed.
#
# Why: installer/AGENTS.md#try-nixarchy-sh
#
#   ./try-nixarchy.sh            download the net image and install into a VM
#   ./try-nixarchy.sh --full     the offline image instead (6 GB, no network)
#   ./try-nixarchy.sh --boot     boot what you already installed
#   ./try-nixarchy.sh --fresh    wipe the disk and install again
#   ./try-nixarchy.sh --help     the rest
#
# Needs qemu and curl from your distribution, and nothing else. `nix run
# github:olafkfreund/nixarchy#try` is the better front door if you HAVE nix --
# it resolves the image from the commit you asked for rather than from the
# latest release, and this script cannot.
set -uo pipefail

REPO=${NIXARCHY_REPO:-olafkfreund/nixarchy}
API=${NIXARCHY_API:-https://api.github.com/repos/$REPO/releases/latest}
WORK=${NIXARCHY_TRY_DIR:-$PWD}
DISK="$WORK/nixarchy-try.qcow2"
DISK_GB=${NIXARCHY_TRY_DISK:-24}
MEM_MB=${NIXARCHY_TRY_MEM:-8192}
CPUS=${NIXARCHY_TRY_CPUS:-4}

bold=$(printf '\033[1m'); dim=$(printf '\033[2m')
red=$(printf '\033[31m'); off=$(printf '\033[0m')
say() { printf '%s\n' "$*"; }
die() { printf '%s%s%s\n' "$red" "$*" "$off" >&2; exit 1; }

full=false boot_only=false fresh=false
while (($#)); do
  case "$1" in
    --full) full=true; shift ;;
    --boot) boot_only=true; shift ;;
    --fresh) fresh=true; shift ;;
    --memory) MEM_MB=${2:?--memory needs a number in MB}; shift 2 ;;
    -h | --help)
      sed -n '2,16p' "$0" | sed 's/^# \{0,1\}//'
      say ""
      say "Environment: NIXARCHY_TRY_DIR (where the disk and image live),"
      say "  NIXARCHY_TRY_MEM (MB, default $MEM_MB), NIXARCHY_TRY_DISK (GB,"
      say "  default $DISK_GB), NIXARCHY_TRY_CPUS (default $CPUS)."
      exit 0
      ;;
    *) die "Unknown option: $1 -- try --help" ;;
  esac
done

# ---------------------------------------------------------------------------
# Refuse early, in sentences, naming the number and the way out.
# ---------------------------------------------------------------------------

# Named per distribution because "install qemu" is not one command anywhere,
# and a person who has to search for it is a person who stops here.
need() {
  command -v "$1" >/dev/null 2>&1 && return 0
  say "${red}$1 is not installed.${off}"
  say ""
  say "  Debian/Ubuntu   sudo apt install $2"
  say "  Fedora          sudo dnf install $3"
  say "  Arch            sudo pacman -S $4"
  say "  openSUSE        sudo zypper install $3"
  exit 1
}
need qemu-system-x86_64 qemu-system-x86 qemu-system-x86 qemu-full
need qemu-img qemu-utils qemu-img qemu-full
need curl curl curl curl
need sha256sum coreutils coreutils coreutils

# UEFI firmware, which every distribution puts somewhere different and none of
# them puts on PATH. The machine boots UEFI-only -- systemd-boot, an ESP -- so
# without this there is nothing to find the bootloader the installer writes.
#
# Overridable, because a distribution this list has not met -- or firmware
# built by hand -- is a worse reason to stop than a missing package.
OVMF_CODE=${NIXARCHY_TRY_OVMF_CODE:-} OVMF_VARS=${NIXARCHY_TRY_OVMF_VARS:-}
[ -n "$OVMF_CODE" ] && [ -n "$OVMF_VARS" ] || for pair in \
  "/usr/share/OVMF/OVMF_CODE_4M.fd:/usr/share/OVMF/OVMF_VARS_4M.fd" \
  "/usr/share/OVMF/OVMF_CODE.fd:/usr/share/OVMF/OVMF_VARS.fd" \
  "/usr/share/edk2/ovmf/OVMF_CODE.fd:/usr/share/edk2/ovmf/OVMF_VARS.fd" \
  "/usr/share/edk2/x64/OVMF_CODE.4m.fd:/usr/share/edk2/x64/OVMF_VARS.4m.fd" \
  "/usr/share/edk2-ovmf/x64/OVMF_CODE.fd:/usr/share/edk2-ovmf/x64/OVMF_VARS.fd" \
  "/usr/share/qemu/ovmf-x86_64-code.bin:/usr/share/qemu/ovmf-x86_64-vars.bin"; do
  c=${pair%%:*}; v=${pair##*:}
  if [ -r "$c" ] && [ -r "$v" ]; then OVMF_CODE=$c; OVMF_VARS=$v; break; fi
done
if [ -z "$OVMF_CODE" ]; then
  say "${red}No UEFI firmware (OVMF) found.${off}"
  say ""
  say "nixarchy installs UEFI-only, so a BIOS VM has nothing to boot."
  say ""
  # NixOS keeps OVMF in the store, not /usr/share, so the search above finds
  # nothing on the one distribution that has a better answer anyway. Sending a
  # NixOS user to `apt install ovmf` is the least useful thing this could say.
  if [ -e /etc/NIXOS ] || command -v nix >/dev/null 2>&1; then
    say "${bold}You have nix. Use the front door instead -- it needs none of this:${off}"
    say ""
    say "  nix run github:$REPO#try"
    say ""
    say "It resolves the image from the commit you ask for, brings its own"
    say "qemu and firmware, and refuses in sentences the way this does."
  else
    say "  Debian/Ubuntu   sudo apt install ovmf"
    say "  Fedora          sudo dnf install edk2-ovmf"
    say "  Arch            sudo pacman -S edk2-ovmf"
    say "  openSUSE        sudo zypper install qemu-ovmf-x86_64"
  fi
  exit 1
fi

# KVM is a warning, not a refusal: it still runs without it, several times
# slower. Saying nothing would leave somebody wondering why an install that
# takes minutes here is taking an hour for them.
ACCEL="tcg" CPUOPT="max"
if [ -w /dev/kvm ]; then
  ACCEL="kvm" CPUOPT="host"
elif [ -e /dev/kvm ]; then
  say "${bold}/dev/kvm exists but is not writable by you.${off}"
  say "  Usually: sudo usermod -aG kvm $USER   (then log out and back in)"
  say "  Continuing without it -- expect this to be several times slower."
  say ""
else
  say "${bold}No /dev/kvm on this machine.${off}"
  say "  A VM inside a VM often has none. Continuing without it, slowly."
  say ""
fi

# Memory. The installer builds a system; 4 GB is where it starts to struggle
# and 2 GB is where it fails in ways that look like something else.
total_mb=$(awk '/MemTotal/ {print int($2/1024)}' /proc/meminfo 2>/dev/null || echo 0)
if [ "$total_mb" -gt 0 ] && [ "$MEM_MB" -gt $((total_mb - 1024)) ]; then
  die "Asked for ${MEM_MB}MB of guest memory; this machine has ${total_mb}MB.
Leave at least 1GB for the host: --memory $((total_mb - 2048))"
fi
[ "$MEM_MB" -lt 3072 ] && say "${bold}${MEM_MB}MB is below the 4GB the install wants. Expect trouble.${off}"

mkdir -p "$WORK" || die "Cannot write to $WORK"
avail_gb=$(df -BG --output=avail "$WORK" 2>/dev/null | tail -1 | tr -dc '0-9')
avail_gb=${avail_gb:-0}
if $full; then image_gb=7; else image_gb=2; fi
want_gb=$((DISK_GB + image_gb))
if [ "$avail_gb" -gt 0 ] && [ "$avail_gb" -lt "$want_gb" ]; then
  die "$WORK has ${avail_gb}GB free; this needs about ${want_gb}GB (a ${DISK_GB}GB
disk plus the image). Set NIXARCHY_TRY_DIR to somewhere with room."
fi

# ---------------------------------------------------------------------------
# The image
# ---------------------------------------------------------------------------

run_vm() {
  local -a args=(
    -machine "q35,accel=$ACCEL" -cpu "$CPUOPT"
    -m "$MEM_MB" -smp "$CPUS"
    -drive "if=pflash,format=raw,readonly=on,file=$OVMF_CODE"
    -drive "if=pflash,format=raw,file=$WORK/OVMF_VARS.fd"
    -drive "file=$DISK,if=virtio,format=qcow2"
    -netdev "user,id=n0" -device "virtio-net-pci,netdev=n0"
    -device virtio-vga -device qemu-xhci -device usb-tablet
    -name "nixarchy"
  )
  [ -n "${1:-}" ] && args+=(-cdrom "$1" -boot order=d)
  # No display is not a failure: serve the screen over VNC rather than dying,
  # which is what a headless host or an ssh session needs.
  if [ -n "${DISPLAY:-}${WAYLAND_DISPLAY:-}" ]; then
    args+=(-display "gtk" )
  else
    say "${bold}No display. Serving the VM over VNC on 127.0.0.1:5900.${off}"
    say "  Connect with any VNC client, e.g.  vncviewer 127.0.0.1:5900"
    say ""
    args+=(-display "vnc=127.0.0.1:0")
  fi
  say "${dim}qemu-system-x86_64 ${args[*]}${off}"
  say ""
  qemu-system-x86_64 "${args[@]}"
}

# A fresh copy of the firmware variables per disk: they hold the boot entries
# the installer writes, and a read-only or shared VARS file loses them.
[ -f "$WORK/OVMF_VARS.fd" ] || cp "$OVMF_VARS" "$WORK/OVMF_VARS.fd"

if $boot_only; then
  [ -f "$DISK" ] || die "No $DISK to boot. Run without --boot to install first."
  say "${bold}Booting the machine you installed.${off}"
  run_vm ""
  exit $?
fi

if $fresh && [ -f "$DISK" ]; then
  rm -f "$DISK" "$WORK/OVMF_VARS.fd"
  cp "$OVMF_VARS" "$WORK/OVMF_VARS.fd"
  say "Wiped $DISK."
fi

if [ -f "$DISK" ]; then
  die "$DISK already exists.
  --boot   start the machine you installed into it
  --fresh  wipe it and install again"
fi

say "${bold}Finding the latest nixarchy release...${off}"
json=$(curl -fsSL "$API") || die "Could not reach $API. Are you online?"
tag=$(printf '%s' "$json" | sed -n 's/.*"tag_name": *"\([^"]*\)".*/\1/p' | head -1)
[ -n "$tag" ] || die "Could not read a release tag from $API."
say "  $tag"

base="https://github.com/$REPO/releases/download/$tag"
fetch() {
  local name=$1
  [ -f "$WORK/$name" ] && { say "  have $name"; return 0; }
  say "  downloading $name"
  curl -fL --progress-bar -o "$WORK/$name.part" "$base/$name" ||
    die "Download failed: $base/$name"
  mv "$WORK/$name.part" "$WORK/$name"
}

fetch SHA256SUMS
if $full; then
  iso="nixarchy-$tag.iso"
  for p in aa ab ac ad; do fetch "$iso.part-$p"; done
  if [ ! -f "$WORK/$iso" ]; then
    say "  joining the parts"
    cat "$WORK/$iso".part-* > "$WORK/$iso.tmp" && mv "$WORK/$iso.tmp" "$WORK/$iso"
  fi
else
  iso="nixarchy-$tag-net.iso"
  fetch "$iso"
fi

# Verified against the release's own checksums. A truncated download does not
# announce itself -- it boots halfway and fails as something else entirely.
say "${bold}Checking the image against the release's checksums...${off}"
# Asserted as an explicit ": OK" for this exact file, rather than by the exit
# status of a pipeline. `sha256sum -c ... | grep "$iso"` matches the FAILED
# line just as happily as the OK one, and only refuses at all because pipefail
# happens to carry sha256sum's status out of the pipe -- which is one `set`
# away from silently accepting a corrupt image.
verdict=$(cd "$WORK" && sha256sum -c --ignore-missing SHA256SUMS 2>/dev/null |
  grep -F "$iso:" || true)
case "$verdict" in
  *": OK") say "  $verdict" ;;
  *)
    die "$iso does not match the published checksum.

  ${verdict:-it is not listed in SHA256SUMS at all}

Delete $WORK/$iso and run this again. If it fails a second time, say so on
the issue tracker rather than booting it -- a mismatch is either a truncated
download or an image that is not the one the release published."
    ;;
esac
say ""

qemu-img create -f qcow2 "$DISK" "${DISK_GB}G" >/dev/null ||
  die "Could not create $DISK"

say "${bold}Starting the installer.${off}"
$full || say "  The net image downloads the desktop as it installs, so this VM needs"
$full || say "  the network it already has through qemu's user networking."
say "  When the install finishes, close the window and run:  $0 --boot"
say ""
run_vm "$WORK/$iso"
