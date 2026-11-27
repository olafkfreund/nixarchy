echo "The hostname is part of your NixOS configuration here:" >&2
echo "" >&2
echo "  networking.hostName = \"${1:-workshop}\";" >&2
echo "" >&2
echo "Add it to your host configuration, then Apply changes." >&2
exit 1
