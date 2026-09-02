# Refuse to start the installer VM when the disk images it is about to create
# cannot fit, or would be written into RAM.
#
# Both images are sparse qcow2, so neither fails at creation. They fail LATE:
# a `No space left on device` inside the guest, partway through nixos-install,
# surfacing three levels beneath `error: Cannot build '...-etc.drv'. Reason: 1
# dependency failed.` -- which names neither the file nor the filesystem. A
# day went into chasing that once. An early refusal naming the directory is
# worth more than a late error naming nothing.
#
# The images live in two different places, and the qemu-vm module decides
# both, not us -- the working directory has no say over the first:
#
#   $TMPDIR/nix-vm.XXXXXX/empty0.qcow2   the install target (emptyDiskImages)
#   $PWD/nixos.qcow2                     this VM's own root and store (diskSize)
#
# TMPDIR carries BOTH on a first run, which reading the run script is the only
# way to find out: createEmptyFilesystemImage builds the root disk as a raw
# image under `mktemp` -- so under TMPDIR -- runs mkfs.ext4 over it, and only
# then converts it into $PWD. So the requirement here is the sum, not the
# target alone.
#
# TMPDIR defaults to /tmp, and on a systemd host /tmp is usually tmpfs -- RAM.
# `df` reports it as free space, but it is the same RAM the guest is claiming
# for itself, so filling it is worse than running out of disk. Hence the
# refusal on filesystem type as well as size: on a tmpfs the number df prints
# is not an answer to the question being asked.

need_target=@tmpneed@ # MB, from virtualisation.emptyDiskImages
need_root=@pwdneed@   # MB, from virtualisation.diskSize
need_tmp=$((need_target + need_root))

fail() {
  echo "installer-vm: $*" >&2
}

# $1 directory, $2 MB required, $3 what lands there, $4 how to move it
check() {
  local dir=$1 need=$2 what=$3 fix=$4 fstype avail

  if [ ! -d "$dir" ]; then
    fail "$dir does not exist, and $what is written there."
    fail "  $fix"
    return 1
  fi

  # One df call for both answers, in MB, resolving the mount point behind the
  # directory rather than trusting its name.
  read -r fstype avail < <(df --output=fstype,avail -BM "$dir" | tail -n1)
  avail=${avail%M}

  case "$fstype" in
    tmpfs | ramfs)
      fail "$dir is $fstype -- RAM, not disk. $what would be written there,"
      fail "  competing with the memory the VM itself needs. df calls it free"
      fail "  space; it is not."
      fail "  $fix"
      return 1
      ;;
  esac

  if [ "$avail" -lt "$need" ]; then
    fail "$dir has ${avail}M free, and $what needs ${need}M."
    fail "  $fix"
    return 1
  fi
}

tmp=${TMPDIR:-/tmp}
ok=0
check "$tmp" "$need_tmp" "the install target and the root disk staged beside it" \
  "Point TMPDIR at a real filesystem with room: export TMPDIR=/var/tmp" || ok=1
check "$PWD" "$need_root" "this VM's own root disk" \
  "Run it from a directory on a real filesystem with room." || ok=1
[ "$ok" -eq 0 ] || exit 1

exec @vmscript@ "$@"
