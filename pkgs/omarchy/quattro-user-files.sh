# Edge-only edits to quattro's user-file scripts (#1760), kept out of default.nix's
# installPhase, which has a size budget (tests/install-phase-budget.nix).
# Sourced from installPhase with $out and $sharedMimeInfo set.
substituteInPlace $out/share/omarchy/default/chromium/policies/chrome-extensions.json \
  --replace-fail 'file:///usr/share/omarchy/' 'file://'"$out"'/share/omarchy/'
substituteInPlace $out/share/omarchy/default/chromium/crx/updates.xml \
  --replace-fail 'file:///usr/share/omarchy/' 'file://'"$out"'/share/omarchy/'

substituteInPlace $out/share/omarchy/bin/omarchy-provision-user \
  --replace-fail 'XDG_CURRENT_DESKTOP= xdg-mime default google-chrome.desktop \
  text/html x-scheme-handler/http x-scheme-handler/https x-scheme-handler/about x-scheme-handler/unknown' \
    '. '"$out"'/share/omarchy/lib/nixarchy-store-owned.sh
browser_chosen() {
  local file dir
  local -a config_dirs files
  IFS=: read -ra config_dirs <<< "${XDG_CONFIG_DIRS:-/etc/xdg}"
  files=("${XDG_CONFIG_HOME:-$HOME/.config}/mimeapps.list"
    "${XDG_CONFIG_HOME:-$HOME/.config}/hyprland-mimeapps.list")
  for dir in "${config_dirs[@]}"; do
    [[ $dir == /* ]] || continue
    files+=("$dir/mimeapps.list" "$dir/hyprland-mimeapps.list")
  done
  files+=("${XDG_DATA_HOME:-$HOME/.local/share}/applications/mimeapps.list")
  for file in "${files[@]}"; do
    [[ -f $file ]] || continue
    if awk "/^[[:space:]]*\\[/ { section = /^[[:space:]]*\\[Default Applications\\][[:space:]]*\$/ } section && /^[[:space:]]*x-scheme-handler\\/http[[:space:]]*=[[:space:]]*[^[:space:];]/ { found=1; exit } END { exit !found }" "$file"; then
      return 0
    fi
  done
  return 1
}
if ! store_owned "${XDG_CONFIG_HOME:-$HOME/.config}/mimeapps.list" && ! browser_chosen; then
  XDG_CURRENT_DESKTOP= xdg-mime default chromium-browser.desktop \
    text/html x-scheme-handler/http x-scheme-handler/https x-scheme-handler/about x-scheme-handler/unknown
fi'
# quattro efcf615 dropped HEY's mailto default; older edge pins still set it.
if grep -q 'HEY.desktop' $out/share/omarchy/bin/omarchy-provision-user; then
  substituteInPlace $out/share/omarchy/bin/omarchy-provision-user \
    --replace-fail 'xdg-mime default omarchy-HEY.desktop x-scheme-handler/mailto' \
      'if ! store_owned "${XDG_CONFIG_HOME:-$HOME/.config}/mimeapps.list"; then
  xdg-mime default omarchy-HEY.desktop x-scheme-handler/mailto
fi'
fi

substituteInPlace $out/share/omarchy/bin/omarchy-agent-instructions \
  --replace-fail 'canonical="$HOME/.agents/AGENTS.md"' \
    'canonical="$HOME/.agents/AGENTS.md"
. '"$out"'/share/omarchy/lib/nixarchy-store-owned.sh
shared_linked=false
if [[ -L $canonical ]] || store_owned "$canonical"; then shared_linked=true; fi
if [[ $shared_linked == true && ! -e $canonical ]]; then
  if [[ $edit == true ]]; then
    if store_owned "$canonical"; then
      echo "~/.agents/AGENTS.md is managed by Home Manager; edit it in your configuration (home.file.\".agents/AGENTS.md\")" >&2
      exit 0
    fi
    exec omarchy-launch-editor "$canonical"
  fi
  echo "~/.agents/AGENTS.md is managed elsewhere and does not exist; no harness was linked" >&2
  exit 0
fi' \
  --replace-fail 'blank() {' \
    'blank() {
[[ $shared_linked == false ]] || return 1' \
  --replace-fail '  [[ $target -ef $canonical ]] && return' \
    '  [[ $target -ef $canonical ]] && return
if [[ -L $target ]] || store_owned "$target"; then
  echo "Skipping $target: a link you manage" >&2
  return 0
fi' \
  --replace-fail '  exec omarchy-launch-editor "$canonical"' \
    '  if store_owned "$canonical"; then
  echo "~/.agents/AGENTS.md is managed by Home Manager; edit it in your configuration (home.file.\".agents/AGENTS.md\")" >&2
  exit 0
fi
exec omarchy-launch-editor "$canonical"'
substituteInPlace $out/share/omarchy/bin/omarchy-theme-set-gnome \
  --replace-fail 'gsettings set org.gnome.desktop.interface icon-theme "Adwaita"' \
    '# A theme the user chose stays; gsettings quotes its value, so strip the quotes (\\047).
current=$(gsettings get org.gnome.desktop.interface icon-theme 2>/dev/null | tr -d \\047 || true)
case $current in
  Yaru* | Adwaita | hicolor | "") gsettings set org.gnome.desktop.interface icon-theme "Adwaita" ;;
esac'
substituteInPlace $out/share/omarchy/bin/omarchy-theme-set-qt \
  --replace-fail '[[ -f $CONFIG ]] || exit 0' \
    '[[ -f $CONFIG ]] || exit 0
. '"$out"'/share/omarchy/lib/nixarchy-store-owned.sh
store_owned "$CONFIG" && exit 0' \
  --replace-fail "if [[ \$(jq -r '.theme.iconTheme // empty' \"\$CONFIG\") == \"\$icon_theme\" ]]; then" \
    "current=\$(jq -r '.theme.iconTheme // empty' \"\$CONFIG\")
case \$current in
  \"\" | Adwaita | hicolor | Yaru*) ;;
  *) exit 0 ;;
esac
if [[ \$current == \"\$icon_theme\" ]]; then"

oldEditorCopy=$(printf '%s\n' \
  '# The handler itself, for an install that predates it.' \
  'applications="${XDG_DATA_HOME:-$HOME/.local/share}/applications"' \
  'if [[ ! -f $applications/$handler ]]; then' \
  '  mkdir -p "$applications"' \
  '  cp "$OMARCHY_PATH/applications/$handler" "$applications/"' \
  '  command -v update-desktop-database >/dev/null && update-desktop-database "$applications" || true' \
  'fi')
substituteInPlace $out/share/omarchy/bin/omarchy-cmd-editor-mimetypes \
  --replace-fail "$oldEditorCopy" "" \
  --replace-fail 'list="${XDG_CONFIG_HOME:-$HOME/.config}/mimeapps.list"' 'list="${XDG_CONFIG_HOME:-$HOME/.config}/mimeapps.list"
. '"$out"'/share/omarchy/lib/nixarchy-store-owned.sh
if store_owned "$list"; then
  echo "nixarchy: $list is managed by Home Manager (xdg.mimeApps); text types are left as it sets them" >&2
  exit 0
fi' \
  --replace-fail '[[ -f $older ]] || older=/dev/null' 'older_tmp=$(mktemp)
cleanup_older() { rm -f "$older_tmp"; }
trap cleanup_older EXIT
older=/dev/null
# Lowest precedence first: the awk keeps the last line per type.
add_older() {
  [[ -f $1 ]] || return 0
  cat "$1" >>"$older_tmp"
  printf "\n" >>"$older_tmp"
  older=$older_tmp
}
current_desktop=${XDG_CURRENT_DESKTOP:-}
IFS=: read -ra desktops <<< "${current_desktop,,}"
add_dir() {
  [[ $1 == /* ]] || return 0
  add_older "$1/mimeapps.list"
  for ((j = ${#desktops[@]} - 1; j >= 0; j--)); do
    desktop=${desktops[j]}
    if [[ -n $desktop ]]; then add_older "$1/$desktop-mimeapps.list"; fi
  done
}
IFS=: read -ra data_dirs <<< "${XDG_DATA_DIRS:-}"
for ((i = ${#data_dirs[@]} - 1; i >= 0; i--)); do
  if [[ ${data_dirs[i]} == /* ]]; then add_dir "${data_dirs[i]}/applications"; fi
done
add_dir "${XDG_DATA_HOME:-$HOME/.local/share}/applications"
IFS=: read -ra config_dirs <<< "${XDG_CONFIG_DIRS:-/etc/xdg}"
for ((i = ${#config_dirs[@]} - 1; i >= 0; i--)); do
  add_dir "${config_dirs[i]}"
done
for ((j = ${#desktops[@]} - 1; j >= 0; j--)); do
  desktop=${desktops[j]}
  if [[ -n $desktop ]]; then add_older "${XDG_CONFIG_HOME:-$HOME/.config}/$desktop-mimeapps.list"; fi
done' \
  --replace-fail 'aliases=/usr/share/mime/aliases' "aliases=$sharedMimeInfo/share/mime/aliases" \
  --replace-fail "# The older ~/.local/share list counts too, for a type ~/.config doesn't set:" '# Desktop, system config, and data-dir lists count too:' \
  --replace-fail 'if [[ $unless_chosen == false && -f $desktop_list && ! $desktop_list -ef $list ]]; then' 'if [[ $unless_chosen == false && -f $desktop_list && ! $desktop_list -ef $list ]]; then
  if store_owned "$desktop_list"; then
    echo "nixarchy: $desktop_list is managed by Home Manager; it is left alone" >&2
  else' \
  --replace-fail '"$cleared" >"$desktop_list"' '"$cleared" >"$desktop_list"
  fi'

# A first install removes the shipped launchers /etc/skel seeded. Here a link
# (Home Manager) or an edited copy is the user's, so only a pristine copy goes (#1907).
# Gated on the loop, not the line, so --replace-fail catches a reworded delete.
if grep -qF '"$OMARCHY_PATH"/applications/*.desktop; do' $out/share/omarchy/bin/omarchy-provision-user; then
  substituteInPlace $out/share/omarchy/bin/omarchy-provision-user \
    --replace-fail 'rm -f ~/.local/share/applications/"${launcher##*/}"' \
      'seeded=~/.local/share/applications/"${launcher##*/}"
    if [[ -f $seeded && ! -L $seeded && "$(<"$seeded")" == "$(<"$launcher")" ]]; then rm -f "$seeded"; fi'
fi
