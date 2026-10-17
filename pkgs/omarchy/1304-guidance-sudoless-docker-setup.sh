echo "Docker here is rootless by default: it runs as you and needs no group." >&2
echo "For the rooted daemon, the docker group is declared:" >&2
echo "  users.users.<you>.extraGroups = [ \"docker\" ];" >&2
echo "then Apply changes." >&2
exit 1
