{ pkgs, ... }:
let
  package = pkgs.nixarchy-omarchy or pkgs.omarchy;
  isEdge = pkgs.lib.hasPrefix "edge-" package.version;
  storeList = pkgs.writeText "editor-mimeapps.list" ''
    [Default Applications]
    text/plain=kate.desktop
  '';
  storeConfig = pkgs.writeTextDir "mimeapps.list" ''
    [Default Applications]
    text/plain=kate.desktop
  '';
in
pkgs.runCommand "nixarchy-editor-mimetypes"
  {
    nativeBuildInputs = [
      pkgs.bash
      pkgs.coreutils
      pkgs.gawk
      pkgs.gnugrep
      pkgs.gnused
    ];
  }
  (
    if !isEdge then
      ''
        echo "SKIP editor-mimetypes: stable pin has no editor MIME command"
        touch "$out"
      ''
    else
      ''
        set -euo pipefail
        root=$PWD
        export HOME=$root/home XDG_CONFIG_HOME=$root/config XDG_DATA_HOME=$root/data XDG_CONFIG_DIRS=$root/xdg
        export OMARCHY_PATH=${package}/share/omarchy
        script=$OMARCHY_PATH/bin/omarchy-cmd-editor-mimetypes
        list=$XDG_CONFIG_HOME/mimeapps.list
        desktop=$XDG_CONFIG_HOME/hyprland-mimeapps.list
        mkdir -p "$HOME" "$XDG_CONFIG_HOME" "$XDG_DATA_HOME" "$XDG_CONFIG_DIRS"
        fail() { echo "FAILED $1" >&2; exit 1; }
        reset_config() { rm -rf "$root/config"; mkdir -p "$root/config"; }

        ln -s ${storeList} "$list"
        target=$(readlink "$list")
        bash "$script" --unless-chosen || fail store-linked-file-exit
        [[ -L $list && $(readlink "$list") == "$target" ]] || fail store-linked-file-unchanged

        rm "$list"
        rmdir "$XDG_CONFIG_HOME"
        export XDG_CONFIG_HOME=${storeConfig}
        bash "$script" --unless-chosen || fail store-linked-directory-exit
        [[ $(cat "$XDG_CONFIG_HOME/mimeapps.list") == *text/plain=kate.desktop* ]] || fail store-linked-directory-unchanged
        export XDG_CONFIG_HOME=$root/config
        mkdir -p "$XDG_CONFIG_HOME"

        printf '%s\n' '[Default Applications]' 'text/plain=kate.desktop' > "$list"
        bash "$script" --unless-chosen || fail regular-choice-exit
        grep -qxF 'text/plain=kate.desktop' "$list" || fail regular-choice-kept
        bash "$script" || fail explicit-choice-exit
        grep -qxF 'text/plain=omarchy-launch-editor.desktop' "$list" || fail explicit-choice-handler

        reset_config
        printf '%s\n' '[Default Applications]' 'text/plain=kate.desktop' > "$XDG_CONFIG_DIRS/mimeapps.list"
        bash "$script" --unless-chosen || fail system-choice-exit
        if grep -qxF 'text/plain=omarchy-launch-editor.desktop' "$list"; then fail system-choice-kept; fi
        printf '%s\n' '[Default Applications]' 'text/plain=nvim.desktop' > "$XDG_CONFIG_DIRS/mimeapps.list"
        bash "$script" --unless-chosen || fail system-own-default-exit
        grep -qxF 'text/plain=omarchy-launch-editor.desktop' "$list" || fail system-own-default-replaced

        # Two system dirs disagree: the first in XDG_CONFIG_DIRS wins, as GLib reads them.
        reset_config
        mkdir -p "$root/xdg2"
        printf '%s\n' '[Default Applications]' 'text/plain=kate.desktop' > "$XDG_CONFIG_DIRS/mimeapps.list"
        printf '%s\n' '[Default Applications]' 'text/plain=nvim.desktop' > "$root/xdg2/mimeapps.list"
        XDG_CONFIG_DIRS=$XDG_CONFIG_DIRS:$root/xdg2 bash "$script" --unless-chosen || fail system-order-exit
        if grep -qxF 'text/plain=omarchy-launch-editor.desktop' "$list"; then fail system-order-first-dir-wins; fi
        rm "$XDG_CONFIG_DIRS/mimeapps.list" "$root/xdg2/mimeapps.list"

        reset_config
        printf '%s\n' '[Default Applications]' 'text/plain=kate.desktop' > "$XDG_CONFIG_DIRS/hyprland-mimeapps.list"
        XDG_CURRENT_DESKTOP=Hyprland bash "$script" --unless-chosen || fail system-desktop-choice-exit
        if grep -qxF 'text/plain=omarchy-launch-editor.desktop' "$list"; then fail system-desktop-choice-kept; fi
        reset_config
        XDG_CONFIG_DIRS=:$XDG_CONFIG_DIRS XDG_CURRENT_DESKTOP=Hyprland bash "$script" --unless-chosen || fail empty-system-dir-exit
        if grep -qxF 'text/plain=omarchy-launch-editor.desktop' "$list"; then fail empty-system-dir-skipped; fi
        rm "$XDG_CONFIG_DIRS/hyprland-mimeapps.list"

        reset_config
        printf '%s\n' '[Default Applications]' 'text/plain=kate.desktop' > "$desktop"
        XDG_CURRENT_DESKTOP=Hyprland bash "$script" --unless-chosen || fail user-desktop-choice-exit
        if grep -qxF 'text/plain=omarchy-launch-editor.desktop' "$list"; then fail user-desktop-choice-kept; fi

        reset_config
        mkdir -p "$XDG_DATA_HOME/applications"
        printf '%s\n' '[Default Applications]' 'text/plain=kate.desktop' > "$XDG_DATA_HOME/applications/mimeapps.list"
        bash "$script" --unless-chosen || fail older-user-choice-exit
        if grep -qxF 'text/plain=omarchy-launch-editor.desktop' "$list"; then fail older-user-choice-wins; fi
        rm "$XDG_DATA_HOME/applications/mimeapps.list"

        reset_config
        mkdir -p "$root/data-dir/applications"
        printf '%s\n' '[Default Applications]' 'text/plain=kate.desktop' > "$root/data-dir/applications/mimeapps.list"
        XDG_DATA_DIRS=$root/data-dir bash "$script" --unless-chosen || fail system-data-choice-exit
        if grep -qxF 'text/plain=omarchy-launch-editor.desktop' "$list"; then fail system-data-choice-kept; fi

        reset_config
        printf '%s\n' '[Default Applications]' 'text/plain=kate.desktop' > "$list"
        ln -s ${storeList} "$desktop"
        target=$(readlink "$desktop")
        bash "$script" || fail store-linked-desktop-exit
        [[ -L $desktop && $(readlink "$desktop") == "$target" ]] || fail store-linked-desktop-unchanged

        reset_config
        types=$(sed -n 's/^MimeType=//p' "$OMARCHY_PATH/applications/omarchy-launch-editor.desktop" | tr ';' '\n')
        alias_type=$(awk -v types="$types" 'BEGIN { split(types, a, "\n"); for (i in a) wanted[a[i]] = 1 } $2 in wanted && !($1 in wanted) { print $1; exit }' ${pkgs.shared-mime-info}/share/mime/aliases)
        [[ -n $alias_type ]] || fail alias-fixture
        canonical=$(awk -v alias="$alias_type" '$1 == alias { print $2; exit }' ${pkgs.shared-mime-info}/share/mime/aliases)
        printf '%s\n' '[Default Applications]' "$alias_type=kate.desktop" > "$list"
        bash "$script" --unless-chosen || fail alias-choice-exit
        grep -qxF "$alias_type=kate.desktop" "$list" || fail alias-choice-kept
        if grep -qxF "$canonical=omarchy-launch-editor.desktop" "$list"; then fail alias-choice-replaced; fi

        [[ ! -e $XDG_DATA_HOME/applications/omarchy-launch-editor.desktop ]] || fail handler-not-copied
        touch "$out"
      ''
  )
