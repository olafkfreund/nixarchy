# Edge-only edits to quattro's user-file scripts (#1760), kept out of default.nix's
# installPhase, which has a size budget (tests/install-phase-budget.nix).
# Sourced from installPhase with $out and $sharedMimeInfo set.
substituteInPlace $out/share/omarchy/bin/omarchy-provision-user \
  --replace-fail 'env -u BROWSER XDG_CURRENT_DESKTOP= xdg-settings set default-web-browser google-chrome.desktop' \
    '. '"$out"'/share/omarchy/lib/nixarchy-store-owned.sh
if ! store_owned "${XDG_CONFIG_HOME:-$HOME/.config}/mimeapps.list" \
  && [[ -z $(env -u BROWSER XDG_CURRENT_DESKTOP= xdg-settings get default-web-browser 2>/dev/null || true) ]]; then
  env -u BROWSER XDG_CURRENT_DESKTOP= xdg-settings set default-web-browser chromium-browser.desktop
fi' \
  --replace-fail 'xdg-mime default omarchy-HEY.desktop x-scheme-handler/mailto' \
    'if ! store_owned "${XDG_CONFIG_HOME:-$HOME/.config}/mimeapps.list"; then
  xdg-mime default omarchy-HEY.desktop x-scheme-handler/mailto
fi'

substituteInPlace $out/share/omarchy/bin/omarchy-agent-instructions \
  --replace-fail 'canonical="$HOME/.agents/AGENTS.md"' \
    'canonical="$HOME/.agents/AGENTS.md"
. '"$out"'/share/omarchy/lib/nixarchy-store-owned.sh
shared_linked=false
if [[ -L $canonical ]] || store_owned "$canonical"; then shared_linked=true; fi' \
  --replace-fail 'blank() {' \
    'blank() {
[[ $shared_linked == false ]] || return 1' \
  --replace-fail '  [[ $target -ef $canonical ]] && return' \
    '  [[ $target -ef $canonical ]] && return
if [[ -L $target ]] || store_owned "$target"; then
  echo "Skipping $target: a link you manage" >&2
  return 0
fi' \
  --replace-fail '  exec omarchy-launch-config-editor "$canonical"' \
    '  if store_owned "$canonical"; then
  echo "~/.agents/AGENTS.md is managed by Home Manager; edit it in your configuration (home.file.\".agents/AGENTS.md\")" >&2
  exit 0
fi
exec omarchy-launch-config-editor "$canonical"'
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
IFS=: read -ra config_dirs <<< "${XDG_CONFIG_DIRS:-/etc/xdg}"
for dir in "${config_dirs[@]}"; do
  if [[ -f $dir/mimeapps.list ]]; then
    cat "$dir/mimeapps.list" >>"$older_tmp"
    printf "\n" >>"$older_tmp"
    older=$older_tmp
  fi
done
if [[ -f ${XDG_DATA_HOME:-$HOME/.local/share}/applications/mimeapps.list ]]; then
  cat "${XDG_DATA_HOME:-$HOME/.local/share}/applications/mimeapps.list" >>"$older_tmp"
  printf "\n" >>"$older_tmp"
  older=$older_tmp
fi' \
  --replace-fail 'aliases=/usr/share/mime/aliases' "aliases=$sharedMimeInfo/share/mime/aliases" \
  --replace-fail "# The older ~/.local/share list counts too, for a type ~/.config doesn't set:" '# System config lists and the older user data list count too:' \
  --replace-fail 'if [[ $unless_chosen == false && -f $desktop_list && ! $desktop_list -ef $list ]]; then' 'if [[ $unless_chosen == false && -f $desktop_list && ! $desktop_list -ef $list ]]; then
  if store_owned "$desktop_list"; then
    echo "nixarchy: $desktop_list is managed by Home Manager; it is left alone" >&2
  else' \
  --replace-fail '"$cleared" >"$desktop_list"' '"$cleared" >"$desktop_list"
  fi'
