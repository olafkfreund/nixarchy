#!/usr/bin/env bash
set -euo pipefail
omarchy=$1
engine=$2
work=$(mktemp -d)
trap 'chmod -R u+w "$work"; rm -rf "$work"' EXIT
export HOME=$work/home OMARCHY_PATH=$omarchy/share/omarchy
export XDG_DATA_HOME=$HOME/.local/share XDG_DATA_DIRS=
mkdir -p "$HOME/.local/state/omarchy/current/theme" "$work/bin"
printf '17,34,51\n' > "$HOME/.local/state/omarchy/current/theme/chromium.theme"
export OMARCHY_BROWSER_POLICY_DIRS=$work/etc/chromium/policies/managed
for dir in chromium opt/chrome opt/edge brave; do
  mkdir -p "$work/etc/$dir/policies/managed"
  chmod 0555 "$work/etc/$dir/policies/managed"
done
# Retarget only the four fixed trust roots, not the writer's behavior. Both
# the caller and writer below are the real packaged programs.
sed "s|/etc/|$work/etc/|g" "$omarchy/bin/omarchy-theme-set-browser-policy" > "$work/bin/omarchy-theme-set-browser-policy"
chmod +x "$work/bin/omarchy-theme-set-browser-policy"
export PATH=$work/bin:$omarchy/bin:$PATH
if ! bash "$omarchy/bin/omarchy-theme-set-browser" > "$work/browser.log" 2>&1; then
  cat "$work/browser.log"
  echo 'FAIL: opted-out browser policies break theme switching' >&2
  exit 1
fi
test ! -e "$OMARCHY_BROWSER_POLICY_DIRS/color.json"
test ! -s "$work/browser.log"
echo 'PASS: read-only policy directories stay untouched without a theme error'
chmod 0755 "$OMARCHY_BROWSER_POLICY_DIRS"
bash "$omarchy/bin/omarchy-theme-set-browser"
test "$(jq -r .BrowserThemeColor "$OMARCHY_BROWSER_POLICY_DIRS/color.json")" = '#112233'
test ! -e "$work/etc/brave/policies/managed/color.json"
touch -d @1 "$OMARCHY_BROWSER_POLICY_DIRS/color.json"
bash "$omarchy/bin/omarchy-theme-set-browser"
test "$(stat -c %Y "$OMARCHY_BROWSER_POLICY_DIRS/color.json")" = 1
echo 'PASS: opted-in browser writes its color once and leaves other browsers alone'

mkdir -p "$work/profile/share/icons/Yaru-blue" "$work/profile/share/themes/adw-gtk3" "$work/theme"
printf 'fixture\n' > "$HOME/.local/state/omarchy/current/theme.name"
printf 'Yaru-blue\n' > "$work/theme/icons.theme"
omarchy() { printf '%s\n' "$work/theme"; }
for helper in sync-gtk-theme sync-qt-kde-theme; do
  # Exercise each shipped lookup with a temporary system profile, so the
  # host's installed Yaru and GTK themes cannot make a broken lookup pass.
  # Unset first: an extraction that matches nothing must not test the last helper.
  unset -f omarchy_icon_theme
  source <(sed -n '/^omarchy_icon_theme() {/,/^}/p' "$engine/lib/hyprchroma/$helper" |
    sed "s|/run/current-system/sw|$work/profile|g")
  declare -F omarchy_icon_theme > /dev/null || {
    echo "FAIL: no omarchy_icon_theme extracted from $helper" >&2
    exit 1
  }
  if [[ $(omarchy_icon_theme "$helper") != Yaru-blue ]]; then
    echo "FAIL: $helper misses the system-profile icon theme" >&2
    exit 1
  fi
done
source <(sed -n '/^gtk_theme_installed() {/,/^}/p' "$engine/lib/hyprchroma/sync-gtk-theme" |
  sed "s|/run/current-system/sw|$work/profile|g")
declare -F gtk_theme_installed > /dev/null || {
  echo 'FAIL: no gtk_theme_installed extracted from sync-gtk-theme' >&2
  exit 1
}
if ! gtk_theme_installed adw-gtk3; then
  echo 'FAIL: GTK misses the system-profile base theme' >&2
  exit 1
fi
echo 'PASS: GTK and Qt discover themes in the NixOS system profile'
