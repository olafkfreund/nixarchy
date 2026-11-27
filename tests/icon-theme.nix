{ pkgs, ... }:
let
  shipped = pkgs.nixarchy-omarchy or pkgs.omarchy;
  isEdge = pkgs.lib.hasPrefix "edge-" shipped.version;
  migrations = shipped.passthru.userMigrations;
  storeQt = pkgs.writeText "qtengine-store-icons.json" ''{"theme":{"iconTheme":"Yaru-blue"}}'';
in
pkgs.runCommand "nixarchy-icon-theme"
  {
    nativeBuildInputs = [
      pkgs.bash
      pkgs.coreutils
      pkgs.gnugrep
      pkgs.gnused
      pkgs.jq
    ];
    package = "${shipped}/share/omarchy";
    migration = "${migrations}/scripts/1794397144.sh";
  }
  ''
    set -euo pipefail
    ${
      if isEdge then
        ''
          root=$PWD
          export HOME=$root/home XDG_CONFIG_HOME=$root/config DBUS_SESSION_BUS_ADDRESS=stub
          mkdir -p "$root/bin" "$XDG_CONFIG_HOME/qtengine" "$HOME"
          export PATH=$root/bin:$PATH GSETTINGS_STATE=$root/gtk-icon
          printf '%s\n' '#!${pkgs.bash}/bin/bash' \
            'case $1 in' \
            '  get) cat "$GSETTINGS_STATE" ;;' \
            '  set) [[ $3 == icon-theme ]] && printf "\047%s\047\n" "$4" > "$GSETTINGS_STATE"; exit 0 ;;' \
            '  *) exit 1 ;;' \
            'esac' > "$root/bin/gsettings"
          printf '%s\n' '#!${pkgs.bash}/bin/bash' 'echo dark' > "$root/bin/omarchy-theme-color"
          chmod +x "$root/bin/gsettings" "$root/bin/omarchy-theme-color"
          gnome=$package/bin/omarchy-theme-set-gnome
          qt=$package/bin/omarchy-theme-set-qt
          export QT_SCRIPT=$qt QT_CALLS=$root/qt-calls
          printf '%s\n' '#!${pkgs.bash}/bin/bash' 'echo call >> "$QT_CALLS"' 'exec "$QT_SCRIPT"' > "$root/bin/omarchy-theme-set-qt"
          chmod +x "$root/bin/omarchy-theme-set-qt"
          config=$XDG_CONFIG_HOME/qtengine/config.json

          printf "'Papirus'\n" > "$GSETTINGS_STATE"
          bash "$gnome"
          [[ $(<"$GSETTINGS_STATE") == "'Papirus'" ]] || { echo 'FAILED GTK Papirus' >&2; exit 1; }
          printf "'Yaru-blue'\n" > "$GSETTINGS_STATE"
          bash "$gnome"
          [[ $(<"$GSETTINGS_STATE") == "'Adwaita'" ]] || { echo 'FAILED GTK Yaru-blue' >&2; exit 1; }

          printf '%s\n' '{"theme":{"iconTheme":"Papirus"}}' > "$config"
          bash "$qt"
          [[ $(jq -r .theme.iconTheme "$config") == Papirus ]] || { echo 'FAILED Qt Papirus' >&2; exit 1; }
          printf '%s\n' '{"theme":{"iconTheme":"Yaru-blue"}}' > "$config"
          bash "$qt"
          [[ $(jq -r .theme.iconTheme "$config") == Adwaita ]] || { echo 'FAILED Qt Yaru-blue' >&2; exit 1; }

          rm "$config"
          ln -s ${storeQt} "$config"
          bash "$qt"
          [[ -L $config && $(readlink "$config") == ${storeQt} ]] || { echo 'FAILED Qt store-owned link' >&2; exit 1; }
          [[ $(jq -r .theme.iconTheme "$config") == Yaru-blue ]] || { echo 'FAILED Qt store-owned value' >&2; exit 1; }

          # Keep the port's logic intact; redirect its fixed gsettings path to the state stub.
          grep -qF '${pkgs.glib}/bin/gsettings' "$migration" || { echo 'FAILED port gsettings path' >&2; exit 1; }
          sed 's|${pkgs.glib}/bin/gsettings|'"$root"'/bin/gsettings|g' "$migration" > "$root/migration-test"
          rm "$config"
          printf '%s\n' '{"theme":{"iconTheme":"Papirus"}}' > "$config"
          printf "'Papirus'\n" > "$GSETTINGS_STATE"
          bash "$root/migration-test"
          [[ $(<"$GSETTINGS_STATE") == "'Papirus'" ]] || { echo 'FAILED port GTK Papirus' >&2; exit 1; }
          [[ $(jq -r .theme.iconTheme "$config") == Papirus ]] || { echo 'FAILED port Qt Papirus' >&2; exit 1; }
          [[ ! -e $QT_CALLS ]] || { echo 'FAILED port Qt Papirus called setter' >&2; exit 1; }
          printf '%s\n' '{"theme":{"iconTheme":"Yaru-blue"}}' > "$config"
          printf "'Yaru-blue'\n" > "$GSETTINGS_STATE"
          bash "$root/migration-test"
          [[ $(<"$GSETTINGS_STATE") == "'Adwaita'" ]] || { echo 'FAILED port GTK Yaru-blue' >&2; exit 1; }
          [[ $(jq -r .theme.iconTheme "$config") == Adwaita ]] || { echo 'FAILED port Qt Yaru-blue' >&2; exit 1; }
          [[ $(<"$QT_CALLS") == call ]] || { echo 'FAILED port Qt Yaru-blue did not call setter' >&2; exit 1; }

          rm "$config"
          rm "$QT_CALLS"
          ln -s ${storeQt} "$config"
          printf "'Yaru-blue'\n" > "$GSETTINGS_STATE"
          bash "$root/migration-test"
          [[ -L $config && $(readlink "$config") == ${storeQt} ]] || { echo 'FAILED port Qt store-owned link' >&2; exit 1; }
          [[ $(jq -r .theme.iconTheme "$config") == Yaru-blue ]] || { echo 'FAILED port Qt store-owned value' >&2; exit 1; }
          [[ ! -e $QT_CALLS ]] || { echo 'FAILED port Qt store-owned called setter' >&2; exit 1; }
        ''
      else
        "echo 'SKIP icon-theme: edge-only theme setters and migration on this pin' "
    }
    touch "$out"
  ''
