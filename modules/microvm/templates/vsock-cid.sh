# cwd is the VM's directory (pkgs/microvm.nix exec_vm); never read share/.
f=./vsock-cid
if [ -L "$f" ]; then
  echo "nixarchy-vsock-cid: $f is a symlink; refusing" >&2
  exit 1
fi
if [ ! -s "$f" ]; then
  # 0-2 are reserved and 2^32-1 is VMADDR_CID_ANY: draw from 3..4294967294.
  cid=$(( $(od -An -N4 -tu4 /dev/urandom) % 4294967292 + 3 ))
  printf '%s\n' "$cid" > "$f"
fi
cid=$(cat "$f")
case $cid in
  '' | *[!0-9]* | ???????????*)
    echo "nixarchy-vsock-cid: $f is not a number of at most 10 digits" >&2
    exit 1
    ;;
esac
cid=$((10#$cid))
if [ "$cid" -lt 3 ] || [ "$cid" -gt 4294967294 ]; then
  echo "nixarchy-vsock-cid: $f holds $cid, outside 3..4294967294" >&2
  exit 1
fi
printf -- '-device vhost-vsock-pci,guest-cid=%s\n' "$cid"
