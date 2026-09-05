# shellcheck shell=bash
# Boot the nixarchy installer in a local virtual machine, for someone who
# knows nothing about this repository:
#
#   nix run github:olafkfreund/nixarchy#try            the offline image
#   nix run github:olafkfreund/nixarchy#try -- --net   the network image
#
# The qemu line is the small part of this file. The large part is refusing
# early, in sentences, on the machines this will actually meet: no /dev/kvm,
# /dev/kvm without the group, too little RAM, too little disk, an image that
# would be a three-hour source build rather than a download, and a disk left
# behind by a previous or interrupted run. Every refusal names the number it
# measured and the way out. checks.try-preflight drives each of these paths
# with a stubbed environment, so the messages below are asserted text, not
# hope -- change one and the check will tell you.
#
# Deliberately NOT a wrapper around `.#installer-vm`: that VM answers the
# wizard itself from a baked-in answers file, which is exactly what a person
# trying nixarchy must not get. This boots the same ISO a release ships and
# leaves the questions to the human.
#
# The script does not depend on the ISO derivation. If it did, `nix run #try`
# would download (or worse, build) 5.6 GB before one line of this file ran,
# and the whole point of the preflight -- say what is about to happen BEFORE
# it happens -- would be lost. Instead the ISO is resolved at runtime with a
# dry-run first, from the very source this script was built from.
#
# @-placeholders are substituted by flake.nix; everything above `main` is
# sourced verbatim by tests/try-preflight.nix (NIXARCHY_TRY_SOURCED=1), which
# is why the probes read their paths from TRY_* variables: the check lies to
# them the same way tests/installer-store-space.nix lies to install.sh.

REV="@rev@"
GH_API="${TRY_GH_API:-https://api.github.com/repos/olafkfreund/nixarchy/releases/latest}"
CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/nixarchy-try"
QEMU="@qemu@"
QEMU_IMG="@qemu_img@"
OVMF_CODE="@ovmf_code@"
OVMF_VARS="@ovmf_vars@"

DISK=nixarchy-try.qcow2
VARS=nixarchy-try-efivars.fd
# Matches installer/vm.nix's emptyDiskImages, for the same measured reason:
# a 2G ESP plus ~14 GiB of closure, with room for a rebuild on top.
DISK_MB=24576
MEM_MB=8192
MEM_MIN=4096

say() { echo "try: $*" >&2; }

# ---------------------------------------------------------------------------
# Probes. Each returns a word or a verdict and is tested with a stubbed
# environment; none of them touches qemu or nix.

# kvm | nogroup | none. Existence alone is not the answer: on most distros
# /dev/kvm exists and the user is simply not in the `kvm` group, and qemu's
# accel=kvm:tcg fallback would then run 10x slower without a word.
detect_kvm() {
  local dev="${TRY_KVM_DEV:-/dev/kvm}"
  if [ ! -e "$dev" ]; then
    echo none
  elif [ ! -r "$dev" ] || [ ! -w "$dev" ]; then
    echo nogroup
  else
    echo kvm
  fi
}

explain_kvm() {
  case "$1" in
    kvm)
      say "hardware virtualisation: yes (/dev/kvm)"
      ;;
    none)
      say "WARNING: no /dev/kvm -- this machine offers no hardware virtualisation."
      say "  Falling back to software emulation, which is SEVERAL TIMES SLOWER."
      say "  The VM will feel sluggish; nixarchy on real hardware is not."
      say "  If the CPU has VT-x/AMD-V, enable it in the firmware setup."
      ;;
    nogroup)
      say "WARNING: /dev/kvm exists but you may not open it -- you are probably"
      say "  not in the 'kvm' group. Falling back to software emulation, which"
      say "  is SEVERAL TIMES SLOWER. The VM will feel sluggish; nixarchy on"
      say "  real hardware is not. To fix it:"
      # shellcheck disable=SC2016  # $USER is theirs to expand, not ours
      say '    sudo usermod -aG kvm $USER    # then log out and back in'
      ;;
  esac
}

# Refuse rather than OOM: a guest that outgrows the host dies mid-install
# under errors that name neither RAM nor the guest. A meminfo with no
# MemAvailable line proceeds -- a probe that cannot read must not invent a
# refusal (the tolerance rule tests/installer-store-space.nix already states).
check_ram() {
  local need=$1 meminfo="${TRY_MEMINFO:-/proc/meminfo}" avail_kb avail
  avail_kb=$(awk '/^MemAvailable:/ { print $2 }' "$meminfo" 2>/dev/null || :)
  [ -n "$avail_kb" ] || return 0
  avail=$((avail_kb / 1024))
  if [ "$avail" -lt $((need + 512)) ]; then
    say "not enough free memory: the VM wants ${need} MB and this machine has"
    say "  ${avail} MB available. Close something, or run a smaller VM:"
    say "    nix run github:olafkfreund/nixarchy#try -- --memory ${MEM_MIN}"
    say "  (${MEM_MIN} MB is the floor: below it the install dies partway through"
    say "  with errors that name none of this.)"
    return 1
  fi
}

# The same probe installer/vm-preflight.sh runs, for the same reason: sparse
# images fail LATE, from inside the guest, under an error naming nothing. And
# on a tmpfs the number df prints is RAM, not disk.
check_disk() {
  local dir=$1 need=$2 what=$3 fstype avail
  read -r fstype avail < <(df --output=fstype,avail -BM "$dir" | tail -n1)
  avail=${avail%M}
  case "$fstype" in
    tmpfs | ramfs)
      say "$dir is on $fstype -- RAM, not disk. $what would be written there,"
      say "  competing with the memory the VM itself needs. df calls it free"
      say "  space; it is not. Run this from a directory on a real filesystem."
      return 1
      ;;
  esac
  if [ "$avail" -lt "$need" ]; then
    say "not enough disk space: $what needs up to ${need} MB and $dir has"
    say "  ${avail} MB free. Free some space, or run this somewhere larger."
    return 1
  fi
}

# The flakeref the image is built from: the commit this script was built
# from, by rev. NOT the source store path, though it would be local and
# cheaper: a path flakeref has no git metadata, so `self.rev` is missing
# under it, and installer/mkFlake.nix rightly refuses to generate a flake
# that cannot pin nixarchy by commit -- measured, not theorised: the store
# path route died with "flake-template: build from a committed tree" on a
# fully committed tree. The rev costs nothing a stranger has not already
# paid: `nix run github:...#try` resolved and cached this exact rev to run
# the script at all.
resolve_ref() {
  local rev=$1
  if [ -z "$rev" ]; then
    say "this was built from a tree with uncommitted changes, and the installer"
    say "  image embeds the commit it is built from, so it cannot be built from"
    say "  a dirty checkout. Commit your changes and run it again -- or run the"
    say "  published one: nix run github:olafkfreund/nixarchy#try"
    return 1
  fi
  echo "github:olafkfreund/nixarchy/$rev"
}

# What `nix build --dry-run` is about to do, in one word:
#   build        the image itself would be compiled from source -- hours
#   fetch (...)  a download, with nix's own size figures attached
#   ready        already in the local store
# Anything unparseable is `ready`: a plan we cannot read must not become a
# new way to refuse a run that would work.
classify_plan() {
  local f=$1 built_section built fetched
  built_section=$(sed -n '/will be built/,/^[^ ]/p' "$f")
  built=$(grep -cE '^ */nix/store/.*\.drv' <<<"$built_section" || :)
  if [ "${built:-0}" -gt 0 ] && grep -qE 'iso|squashfs' <<<"$built_section"; then
    echo build
    return 0
  fi
  fetched=$(grep -oE 'will be fetched \([^)]*\)' "$f" | head -n1 || :)
  if [ -n "$fetched" ]; then
    echo "fetch ${fetched#will be fetched }"
  elif [ "${built:-0}" -gt 50 ]; then
    # No single telltale name, but nobody's cache miss builds this many
    # derivations for an image that exists in a cache.
    echo build
  else
    echo ready
  fi
}

# "(1.87 GiB download, 5.61 GiB unpacked)" -> unpacked size in MB, rounded
# up, or nothing when the text carries no such figure.
plan_unpacked_mb() {
  # shellcheck disable=SC2312  # a plan with no size figure prints nothing
  grep -oE '[0-9.]+ [KMGT]iB unpacked' <<<"$1" | awk '
    { n = $1; u = $2 }
    END {
      if (u == "KiB") n /= 1024
      else if (u == "GiB") n *= 1024
      else if (u == "TiB") n *= 1024 * 1024
      if (n > 0) printf "%d\n", n + 1
    }' || :
}

# From a GitHub release JSON in file $1, the download URLs for $2 -- `iso`
# (the offline parts, in order), `iso-net`, or `sums`. Prints nothing when
# the release does not carry the asset, which is a real state: recent
# releases name a -net.iso in SHA256SUMS and do not attach one.
release_urls() {
  local f=$1 what=$2 urls
  urls=$(grep -oE '"browser_download_url": *"[^"]*"' "$f" | grep -oE 'https://[^"]*' || :)
  case "$what" in
    iso-net) grep -E -- '-net\.iso$' <<<"$urls" || : ;;
    iso) grep -E '\.iso(\.part-[a-z]+)?$' <<<"$urls" | grep -vE -- '-net\.iso$' | sort || : ;;
    sums) grep -E '/SHA256SUMS$' <<<"$urls" | head -n1 || : ;;
  esac
}

release_tag() {
  grep -oE '"tag_name": *"[^"]*"' "$1" | head -n1 | cut -d'"' -f4 || :
}

# Download the latest release image for $1 (iso | iso-net) into CACHE_DIR,
# verify it against the release's SHA256SUMS, and print its path. A file
# that already verified on a previous run is reused; an interrupted or
# corrupt download is deleted, never reused -- the qcow2 rule again, one
# layer down. All progress goes to stderr; stdout is the path alone.
fetch_release() {
  local attr=$1 json tag urls sums_url base iso_name tmp want got u len total_mb
  json=$(mktemp)
  if ! curl -fsSL "$GH_API" -o "$json"; then
    rm -f "$json"
    say "could not reach the GitHub releases API to look for a prebuilt image."
    return 1
  fi
  tag=$(release_tag "$json")
  urls=$(release_urls "$json" "$attr")
  sums_url=$(release_urls "$json" sums)
  if [ -z "$tag" ] || [ -z "$urls" ] || [ -z "$sums_url" ]; then
    rm -f "$json"
    say "the latest release carries no downloadable '$attr' image."
    return 1
  fi
  rm -f "$json"

  base=$(basename "$(head -n1 <<<"$urls")")
  iso_name=${base%.part-*}
  mkdir -p "$CACHE_DIR"
  if [ -e "$CACHE_DIR/$iso_name" ]; then
    say "reusing the release image already downloaded and verified:"
    say "  $CACHE_DIR/$iso_name"
    echo "$CACHE_DIR/$iso_name"
    return 0
  fi

  total_mb=0
  while IFS= read -r u; do
    len=$(curl -fsIL "$u" | grep -i '^content-length:' | tail -n1 | grep -oE '[0-9]+' || :)
    if [ -n "$len" ]; then total_mb=$((total_mb + len / 1048576)); fi
  done <<<"$urls"
  say "downloading release $tag image $iso_name (about ${total_mb} MB)"
  say "  into $CACHE_DIR -- kept there, so a second run skips this."
  if [ "$total_mb" -gt 0 ]; then
    check_disk "$CACHE_DIR" $((total_mb + 512)) "the downloaded image" || return 1
  fi

  curl -fsSL "$sums_url" -o "$CACHE_DIR/SHA256SUMS" || {
    say "could not download the release's SHA256SUMS; not fetching an image"
    say "  that cannot be verified."
    return 1
  }
  tmp="$CACHE_DIR/$iso_name.part"
  rm -f "$tmp"
  while IFS= read -r u; do
    say "  fetching $(basename "$u") ..."
    if ! curl -fL --progress-bar "$u" >>"$tmp"; then
      rm -f "$tmp"
      say "download failed partway; the partial file was deleted. Check the"
      say "  connection and run it again."
      return 1
    fi
  done <<<"$urls"
  want=$(grep " ${iso_name}\$" "$CACHE_DIR/SHA256SUMS" | awk '{ print $1 }' || :)
  got=$(sha256sum "$tmp" | awk '{ print $1 }')
  if [ -z "$want" ] || [ "$got" != "$want" ]; then
    rm -f "$tmp"
    say "the downloaded image did not match the release's checksum, so it was"
    say "  deleted. Run it again; if this repeats, report it:"
    say "  https://github.com/olafkfreund/nixarchy/issues"
    return 1
  fi
  mv "$tmp" "$CACHE_DIR/$iso_name"
  say "checksum verified."
  echo "$CACHE_DIR/$iso_name"
}

# ---------------------------------------------------------------------------

usage() {
  cat <<EOF
Try nixarchy in a virtual machine. No repository knowledge required.

  nix run github:olafkfreund/nixarchy#try            offline image (~5.6 GB download,
                                                     installs with no network at all)
  nix run github:olafkfreund/nixarchy#try -- --net   network image (~1.9 GB download;
                                                     the install then fetches the rest
                                                     from binary caches)

What happens: the installer ISO boots in a window (UEFI), you answer its
questions, and it installs onto a virtual disk -- $DISK, up to
${DISK_MB} MB, created in the current directory. When the install finishes
and the machine powers off:

  nix run github:olafkfreund/nixarchy#try -- --boot    boot the installed system
  nix run github:olafkfreund/nixarchy#try -- --fresh   wipe the disk, install again

Options:
  --net          install from the small network image instead of the offline one
  --boot         boot the already-installed disk instead of the installer
  --fresh        delete the disk a previous run left, then install
  --memory MB    RAM for the VM (default ${MEM_MB}, minimum ${MEM_MIN})
  --cpus N       virtual CPUs (default: what the host has, up to 4)
  --vnc          no window: serve the VM's screen on VNC at 127.0.0.1:5900
  --build        compile this exact commit's image from source (hours) rather
                 than falling back to the latest release's prebuilt image
  --help         this text

Needs: x86_64 Linux with nix, about $((MEM_MB + 512)) MB of free RAM,
${DISK_MB} MB of free disk in the current directory, and /dev/kvm for full
speed (without it you get a loud warning and slow emulation, not a failure).
EOF
}

main() {
  local attr=iso mem=$MEM_MB cpus="" vnc=0 fresh=0 boot=0 srcbuild=0
  while [ $# -gt 0 ]; do
    case "$1" in
      --net) attr="iso-net" ;;
      --build) srcbuild=1 ;;
      --boot) boot=1 ;;
      --fresh) fresh=1 ;;
      --vnc) vnc=1 ;;
      --memory)
        if [ $# -lt 2 ]; then
          say "--memory needs a number of megabytes after it."
          exit 1
        fi
        mem=$2
        shift
        ;;
      --cpus)
        if [ $# -lt 2 ]; then
          say "--cpus needs a number after it."
          exit 1
        fi
        cpus=$2
        shift
        ;;
      -h | --help)
        usage
        exit 0
        ;;
      *)
        say "unknown option: $1"
        say "  --help lists what this understands."
        exit 1
        ;;
    esac
    shift
  done

  case "$mem" in
    '' | *[!0-9]*)
      say "--memory wants a number of megabytes, not '${mem}'."
      exit 1
      ;;
  esac
  if [ "$mem" -lt "$MEM_MIN" ]; then
    say "--memory ${mem} is below the ${MEM_MIN} MB floor. The installer runs"
    say "  out of memory below that and fails with errors that name none of"
    say "  this, so refusing up front instead."
    exit 1
  fi
  if [ -z "$cpus" ]; then
    cpus=$(nproc)
    [ "$cpus" -le 4 ] || cpus=4
  fi
  case "$cpus" in
    *[!0-9]* | 0 | '')
      say "--cpus wants a positive number, not '${cpus}'."
      exit 1
      ;;
  esac

  # The disk decision comes before everything else: it needs no probe, and an
  # interrupted install must never be silently reused as if it were fresh,
  # nor silently destroyed as if it were disposable.
  if [ "$fresh" = 1 ] && [ "$boot" = 1 ]; then
    say "--fresh wipes the disk and --boot boots it; they contradict. Pick one."
    exit 1
  fi
  if [ "$boot" = 1 ] && [ ! -e "$DISK" ]; then
    say "--boot: there is no $DISK in this directory to boot."
    say "  Run without --boot first to install one."
    exit 1
  fi
  if [ "$boot" = 0 ] && [ -e "$DISK" ]; then
    if [ "$fresh" = 1 ]; then
      rm -f "$DISK" "$VARS"
    else
      say "$DISK already exists here -- a previous run made it, and it may"
      say "  hold a finished install or an interrupted one. Refusing to guess:"
      say "    --boot     boot whatever is installed on it"
      say "    --fresh    delete it and start a clean install"
      exit 1
    fi
  fi

  local kvm
  kvm=$(detect_kvm)
  explain_kvm "$kvm"
  check_ram "$mem" || exit 1
  check_disk "$PWD" "$DISK_MB" "the VM's target disk ($DISK)" || exit 1

  local iso=""
  if [ "$boot" = 0 ]; then
    if ! command -v nix >/dev/null; then
      say "nix is not on PATH, and the installer image is fetched with nix."
      exit 1
    fi
    local ref
    ref=$(resolve_ref "$REV") || exit 1

    # Dry-run first, so "download" and "three-hour source build" are told
    # apart BEFORE either starts. The evaluation itself is the slow part of
    # this step, so say that too.
    say "checking whether the installer image is a download or a build"
    say "  (evaluating -- takes a minute or two the first time) ..."
    local dry plan
    dry=$(mktemp)
    trap 'rm -f "$dry"' EXIT
    if ! nix build --dry-run \
      --extra-experimental-features 'nix-command flakes' \
      "$ref#$attr" >"$dry" 2>&1; then
      say "evaluating the installer image failed. nix said:"
      sed 's/^/  | /' "$dry" >&2
      exit 1
    fi
    plan=$(classify_plan "$dry")
    case "$plan" in
      build*)
        say "the image for this exact commit is not in a binary cache -- images"
        say "  are cached for releases and nightly-tested commits, not every"
        say "  push -- so nix would COMPILE it from source: hours of building"
        say "  and tens of gigabytes."
        if [ "$srcbuild" = 0 ]; then
          say "falling back to the latest RELEASE image instead: the same"
          say "  installer, built and install-tested by CI. (--build compiles"
          say "  this exact commit from source instead.)"
          iso=$(fetch_release "$attr") || iso=""
        fi
        if [ -z "$iso" ]; then
          if [ "$srcbuild" = 0 ]; then
            say "no release image could be fetched, so a source build is the"
            say "  only path left."
          fi
          if [ -t 0 ]; then
            local answer
            read -r -p "try: build it from source (hours)? [y/N] " answer
            case "$answer" in
              y* | Y*) ;;
              *)
                say "not building. Nothing was changed."
                exit 1
                ;;
            esac
          else
            say "stdin is not a terminal, so not asking. Refusing."
            exit 1
          fi
        fi
        ;;
      fetch*)
        say "downloading the installer image: ${plan#fetch }"
        local need
        need=$(plan_unpacked_mb "${plan#fetch }")
        if [ -n "$need" ]; then
          check_disk /nix/store $((need + 1024)) "the installer image" || exit 1
        fi
        ;;
      ready)
        say "installer image already in the local store -- nothing to fetch."
        ;;
    esac

    if [ -z "$iso" ]; then
      local out
      out=$(nix build --no-link --print-out-paths \
        --extra-experimental-features 'nix-command flakes' \
        "$ref#$attr" | head -n1)
      local f
      for f in "$out"/iso/*.iso; do iso=$f; done
      if [ ! -e "$iso" ]; then
        say "built $out but found no ISO inside it. That is a nixarchy bug;"
        say "  please report it: https://github.com/olafkfreund/nixarchy/issues"
        exit 1
      fi
    fi

    "$QEMU_IMG" create -q -f qcow2 "$DISK" "${DISK_MB}M"
  fi

  # UEFI, not a nicety: the installer refuses a BIOS machine, correctly --
  # its layout is an ESP with systemd-boot and there is no BIOS path. A VM
  # that boots legacy shows a stranger a refusal as their first experience.
  # Writable vars beside the disk, so the boot entry the install writes
  # survives into --boot (tests/install-iso.nix, the readonly=on lesson).
  if [ ! -e "$VARS" ]; then
    install -m 644 "$OVMF_VARS" "$VARS"
  fi

  local display_args=()
  if [ "$vnc" = 1 ] || { [ -z "${WAYLAND_DISPLAY:-}" ] && [ -z "${DISPLAY:-}" ]; }; then
    if [ "$vnc" = 0 ]; then
      say "no graphical display here (neither WAYLAND_DISPLAY nor DISPLAY is set)."
    fi
    say "serving the VM's screen over VNC instead: point a VNC viewer at"
    say "  127.0.0.1:5900 on this machine. From elsewhere:"
    say "    ssh -L 5900:127.0.0.1:5900 <this-host>   then view localhost:5900"
    display_args=(-display none -vnc 127.0.0.1:0)
  else
    display_args=(-display gtk)
  fi

  local accel_args=(-accel tcg -cpu max)
  if [ "$kvm" = kvm ]; then
    accel_args=(-accel kvm -cpu host)
  fi

  local drive_args=(
    -drive "if=pflash,format=raw,readonly=on,file=$OVMF_CODE"
    -drive "if=pflash,format=raw,file=$VARS"
    -drive "id=hd0,if=none,format=qcow2,file=$DISK"
  )
  if [ "$boot" = 1 ]; then
    drive_args+=(-device "virtio-blk-pci,drive=hd0,bootindex=0")
    say "booting the system installed on $DISK"
  else
    drive_args+=(
      -device "virtio-blk-pci,drive=hd0,bootindex=1"
      -device "virtio-scsi-pci,id=scsi0"
      -drive "id=cd0,if=none,media=cdrom,readonly=on,format=raw,file=$iso"
      -device "scsi-cd,bus=scsi0.0,drive=cd0,bootindex=0"
    )
    say "starting the installer. Answer its questions in the window; it"
    say "  installs onto $DISK in this directory. When it finishes and the"
    say "  machine powers off, boot the result with:"
    say "    nix run github:olafkfreund/nixarchy#try -- --boot"
  fi
  local speed="software emulation (slow)"
  if [ "$kvm" = kvm ]; then speed=KVM; fi
  say "VM: ${mem} MB RAM, ${cpus} CPUs, $speed"

  exec "$QEMU" \
    -name nixarchy-try \
    -machine q35 \
    -m "$mem" -smp "$cpus" \
    "${accel_args[@]}" \
    "${drive_args[@]}" \
    "${display_args[@]}" \
    -device virtio-vga \
    -device qemu-xhci -device usb-tablet \
    -nic user,model=virtio-net-pci
}

if [ -z "${NIXARCHY_TRY_SOURCED:-}" ]; then
  main "$@"
fi
