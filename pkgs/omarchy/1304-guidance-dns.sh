echo "DNS is part of your NixOS configuration here, not a file to edit:" >&2
echo "" >&2
echo "  networking.nameservers = [ \"1.1.1.1\" \"1.0.0.1\" ];" >&2
echo "  services.resolved.fallbackDns = [ \"9.9.9.9\" ];" >&2
echo "" >&2
echo "Add it to your host configuration, then Apply changes." >&2
exit 1
