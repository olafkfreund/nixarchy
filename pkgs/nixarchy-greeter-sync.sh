# nixarchy-greeter-sync -- hand the current Omarchy theme to the SDDM greeter.
# Copies colors.toml and the wallpaper into the inbox, then renames a fresh
# `ready` nonce into place, which starts nixarchy-greeter-publish.
# Why: pkgs/AGENTS.md#the-greeter-follows-the-omarchy-theme-1927
dir=${NIXARCHY_GREETER_DIR:-/var/lib/nixarchy-greeter}
inbox=$dir/inbox
if [ ! -d "$inbox" ] || [ ! -w "$inbox" ]; then exit 0; fi
[ -n "${XDG_RUNTIME_DIR:-}" ] || exit 0

exec 9>"$XDG_RUNTIME_DIR/nixarchy-greeter-sync.lock"
flock 9
trap 'rm -f "$inbox"/.tmp.*' EXIT

# Copy via a temp name so the publisher never reads a half-written file.
put() {
  install -m 0644 -- "$1" "$inbox/.tmp.$2"
  mv -f -- "$inbox/.tmp.$2" "$inbox/$2"
}

state=$HOME/.local/state/omarchy/current
if [ -f "$state/theme/colors.toml" ]; then
  put "$state/theme/colors.toml" colors.toml
else
  rm -f "$inbox/colors.toml"
fi

bg=$(readlink -f -- "$state/background" 2>/dev/null || true)
ext=${bg##*.}
ext=${ext,,}
case $ext in
  png | jpg | jpeg | gif | bmp | webp) ok=1 ;;
  *) ok=0 ;;
esac
if [ "$ok" = 1 ] && [ -f "$bg" ]; then
  put "$bg" background
else
  rm -f "$inbox/background"
fi

date +%s%N >"$inbox/.tmp.ready"
chmod 0644 "$inbox/.tmp.ready"
mv -f -- "$inbox/.tmp.ready" "$inbox/ready"
