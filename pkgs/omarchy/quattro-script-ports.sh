# Sourced from omarchy's installPhase: $1 fingerprint guidance, $2 upstream
# agent-local `use` block, $3 our preflight, $4 hostname guidance. Each patch knows every text a pin
# can carry (the tag, older edge pins, the current one) and fails loudly on any
# other, because a skipped patch reads as a working script.
# Why: pkgs/AGENTS.md#quattro-script-ports

fp=$out/share/omarchy/bin/omarchy-setup-security-fingerprint
if grep -qF 'if omarchy-pkg-missing "${packages[@]}"; then' "$fp"; then
  substituteInPlace "$fp" \
    --replace-fail 'libfprint_owner=$(pacman -Qqo /usr/lib/libfprint-2.so.2 2>/dev/null || true)' 'libfprint_owner=' \
    --replace-fail 'if omarchy-pkg-missing "${packages[@]}"; then' 'if ! command -v fprintd-enroll >/dev/null 2>&1; then' \
    --replace-fail '  sudo pacman -S --needed --noconfirm --ask 4 -- "${packages[@]}"' "$(cat "$1")"
else
  substituteInPlace "$fp" \
    --replace-fail 'if omarchy-pkg-missing libfprint-git fprintd usbutils; then' 'if ! command -v fprintd-enroll >/dev/null 2>&1; then' \
    --replace-fail '  sudo pacman -S --needed --noconfirm --ask 4 -- libfprint-git fprintd usbutils' "$(cat "$1")"
fi

wifi=$out/share/omarchy/install/user/first-run/wifi.sh
if grep -qF 'checkupdates --nocolor >/dev/null 2>&1 || status=$?' "$wifi"; then
  substituteInPlace "$wifi" --replace-fail 'checkupdates --nocolor >/dev/null 2>&1 || status=$?' 'status=2'
elif grep -q checkupdates "$wifi"; then
  echo "wifi.sh: checkupdates appears in a form this patch does not know" >&2
  exit 1
fi

# The tag ships neither name; edge before ebd2974 ships omarchy-agent-local.
for name in omarchy-models omarchy-agent-local; do
  f=$out/share/omarchy/bin/$name
  [ -e "$f" ] || continue
  use=$(cat "$2")
  [ "$name" = omarchy-agent-local ] || use=${use/The agents panel starts/The local models panel starts}
  substituteInPlace "$f" --replace-fail "$use" "$(sed "s/omarchy-agent-local/$name/g" "$3")"
done

# quattro efcf615's Setup > Network > Hostname runs hostnamectl; the hostname
# here is networking.hostName, so it says so before asking for a name (#1896).
hn=$out/share/omarchy/bin/omarchy-setup-hostname
if [ -e "$hn" ]; then
  substituteInPlace "$hn" --replace-fail 'name=${1:-}' "$(cat "$4")"
fi
