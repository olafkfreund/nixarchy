echo "Move Yaru icon settings to Adwaita while preserving other icon choices"

if [[ -n ${DBUS_SESSION_BUS_ADDRESS:-} && $(@gsettings@ get org.gnome.desktop.interface icon-theme) == "'Yaru"* ]]; then
  @gsettings@ set org.gnome.desktop.interface icon-theme "Adwaita"
fi

qt_config="${XDG_CONFIG_HOME:-$HOME/.config}/qtengine/config.json"
source @helper@
if [[ -f $qt_config ]] && ! store_owned "$qt_config" && [[ $(@jq@ -r '.theme.iconTheme // empty' "$qt_config") == Yaru* ]]; then
  omarchy-theme-set-qt
fi
