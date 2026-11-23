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
  substituteInPlace "$f" --replace-fail "$use" "$(sed "s/omarchy-agent-local/$name/g" "$3")"
done

# quattro efcf615's Setup > Network > Hostname runs hostnamectl; the hostname
# here is networking.hostName, so it says so before asking for a name (#1896).
hn=$out/share/omarchy/bin/omarchy-setup-hostname
if [ -e "$hn" ]; then
  substituteInPlace "$hn" --replace-fail 'name=${1:-}' "$(cat "$4")" \
    --replace-fail 'sudo hostnamectl set-hostname "$name"' ': # nixarchy: networking.hostName, never hostnamectl (#1896)'
fi

# Upstream names sddm.service; on NixOS SDDM is display-manager.service (#1905).
f=$out/share/omarchy/bin/omarchy-system-sddm-recover
# Absent under the tag and edge before ebd2974; drop-ins without it mean a rename.
if [ ! -e "$f" ] && [ -e $out/share/omarchy/etc/systemd/system/systemd-suspend.service.d/10-omarchy-sddm-recover.conf ]; then
  echo "omarchy-system-sddm-recover: the sleep drop-ins ship but the script does not" >&2
  exit 1
fi
# A restart ends a live session, so only a probe that read every line and found
# no seat may cause one: a failed or unreadable probe leaves the greeter alone (#1908).
[ ! -e "$f" ] || substituteInPlace "$f" \
  --replace-fail 'is-active --quiet sddm.service' 'is-active --quiet display-manager.service' \
  --replace-fail 'restart --no-block sddm.service' 'restart --no-block display-manager.service' \
  --replace-fail "if awk '\$4 ~ /^seat/ { found=1; exit } END { exit !found }' <<<\"\$sessions\"; then
  exit 0
fi" \
    "verdict=\$(awk 'NF == 0 { next } NF < 4 || \$2 !~ /^[0-9]+\$/ || \$4 !~ /^(seat|-\$)/ { bad = 1 } \$4 ~ /^seat/ { seat = 1 }
  END { print (bad ? \"unreadable\" : seat ? \"seated\" : \"seatless\") }' <<<\"\$sessions\") || exit 0
[ \"\$verdict\" = seatless ] || exit 0"
