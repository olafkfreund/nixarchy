{
  lib,
  runCommand,
  jq,
  glib,
  omarchy,
  omarchy-nvim-config,
}:
let
  isEdge = lib.hasPrefix "edge-" omarchy.version;
  ledger = builtins.toFile "nixarchy-user-migrations.json" (
    builtins.toJSON (
      lib.filterAttrs (
        _: r: !(lib.isAttrs r && (r.edge or "" == "only" && !isEdge || r.edge or "" == "absent" && isEdge))
      ) (import ../../data/user-migrations.nix)
    )
  );
  tree = "${omarchy}/share/omarchy";
in
runCommand "nixarchy-user-migrations"
  {
    nativeBuildInputs = [ jq ];
  }
  ''
    set -euo pipefail
    mkdir -p "$out/scripts"
    : > "$out/list"
    jq -r 'del(.predates) | to_entries[] | select((.value.decision | IN("ported", "partial")) and .value.run != "bar") | [.key, .value.run] | @tsv' ${ledger} | sort > rows
    while IFS=$'\t' read -r id run; do
      [[ $id =~ ^[0-9]+$ && -n $run ]] || { echo "invalid migration row: $id" >&2; exit 1; }
      case $run in
        upstream)
          script=${tree}/migrations/$id.sh
          test -f "$script"
          ;;
        port)
          case $id in
            1791479273)
              script=${omarchy}/bin/omarchy-migrate-dictation-default
              test -f "$script"
              ;;
            1787481315)
              script=$out/scripts/$id.sh
              cp ${./user-migrations/1787481315.sh} "$script"
              ;;
            1794397144)
              script=$out/scripts/$id.sh
              cp ${./user-migrations/1794397144.sh} "$script"
              substituteInPlace "$script" \
                --replace-fail '@gsettings@' '${glib}/bin/gsettings' \
                --replace-fail '@jq@' '${jq}/bin/jq' \
                --replace-fail '@helper@' '${tree}/lib/nixarchy-store-owned.sh'
              ;;
            *) echo "no port defined for $id" >&2; exit 1 ;;
          esac
          ;;
        edited)
          script=$out/scripts/$id.sh
          cp "${tree}/migrations/$id.sh" "$script"
          chmod u+w "$script"
          case $id in
            1786719479)
              block=$(sed -n '/^if omarchy-cmd-missing agy &&/,/^fi$/p' "$script")
              [[ $block == *'omarchy-mise-install antigravity-cli agy'* ]] || exit 1
              substituteInPlace "$script" --replace-fail "$block" ""
              ;;
            1788129995)
              substituteInPlace "$script" \
                --replace-fail 'omarchy-pkg-add omasnap' "" \
                --replace-fail 'omarchy-pkg-drop satty tensaku' ""
              ;;
            1791723398)
              substituteInPlace "$script" \
                --replace-fail '/usr/share/omarchy-nvim/config' '${omarchy-nvim-config}/share/omarchy-nvim' \
                --replace-fail 'omarchy-pkg-present omarchy-nvim || exit 0' \
                  '[[ ''${NIXARCHY_NEOVIM:-} != off ]] || exit 0
                   [[ -f $config/plugin/after/transparency.lua ]] || exit 0
                   case $(sha256sum <"$config/plugin/after/transparency.lua") in
                     bd833dc094e3546b5fad512e61cfb09f3032c2a4461c23be7bd90851de80688e* | \
                       6e31b917f13e16514ac94ff9270d47f24e76509a3e559ca85116a5aa2d61306a* | \
                       33d29360df84ed48c70606580749536520384ec64afe650151d4e26e7922b410*) ;;
                     *) exit 0 ;;
                   esac'
              ;;
            1792902457)
              substituteInPlace "$script" --replace-fail 'omarchy-pkg-add qtengine' ""
              ;;
            1794165002)
              substituteInPlace "$script" \
                --replace-fail 'omarchy-pkg-add papers' "" \
                --replace-fail 'omarchy-pkg-drop evince' ""
              block=$(sed -n '/^if \[\[ -f \$user_mimeapps \]\] && grep -q/,/^fi$/p' "$script")
              [[ $block == *"sed --follow-symlinks -i 's/org\\.gnome\\.Evince\\.desktop/org.gnome.Papers.desktop/g' \"\$user_mimeapps\""* ]] || exit 1
              substituteInPlace "$script" --replace-fail "$block" 'if [[ -L $user_mimeapps ]]; then
                if [[ -e $user_mimeapps && -r $user_mimeapps && $(<"$user_mimeapps") == *org.gnome.Evince.desktop* ]]; then
                  echo "nixarchy: $user_mimeapps is a link, left alone; it still names Evince"
                fi
              elif [[ -f $user_mimeapps && -w $user_mimeapps && $(<"$user_mimeapps") == *org.gnome.Evince.desktop* ]]; then
                sed -i '"'"'s/org\.gnome\.Evince\.desktop/org.gnome.Papers.desktop/g'"'"' "$user_mimeapps"
              fi'
              ;;
            1794330979)
              substituteInPlace "$script" \
                --replace-fail 'omarchy-pkg-add folio' "" \
                --replace-fail ${
                  if isEdge then
                    ''
                      'nautilus_packages=()
                      for package_name in nautilus nautilus-python nautilus-dropbox sushi; do
                        pacman -Qq "$package_name" &>/dev/null && nautilus_packages+=("$package_name")
                      done
                      if ((''${#nautilus_packages[@]})); then
                        sudo pacman -Rn --noconfirm "''${nautilus_packages[@]}"
                      fi' ''
                  else
                    "'omarchy-pkg-drop nautilus nautilus-python nautilus-dropbox sushi' "
                }"" \
                --replace-fail '# A dock that still pins Nautilus pins Files instead.' ""
              block=$(sed -n '/^if \[\[ -f \$user_mimeapps \]\] && grep -q/,/^fi$/p' "$script")
              [[ $block == *"sed --follow-symlinks -i 's/org\\.gnome\\.Nautilus\\.desktop/folio.desktop/g' \"\$user_mimeapps\""* ]] || exit 1
              substituteInPlace "$script" --replace-fail "$block" 'if [[ -L $user_mimeapps ]]; then
                if [[ -e $user_mimeapps && -r $user_mimeapps && $(<"$user_mimeapps") == *org.gnome.Nautilus.desktop* ]]; then
                  echo "nixarchy: $user_mimeapps is a link, left alone; it still names Nautilus"
                fi
              elif [[ -f $user_mimeapps && -w $user_mimeapps && $(<"$user_mimeapps") == *org.gnome.Nautilus.desktop* ]]; then
                sed -i '"'"'s/org\.gnome\.Nautilus\.desktop/folio.desktop/g'"'"' "$user_mimeapps"
              fi'
              block=$(sed -n '/^shell_json=/,/^fi$/p' "$script")
              [[ $block == *"sed --follow-symlinks -i 's/\"org\\.gnome\\.Nautilus\"/\"folio\"/' \"\$shell_json\""* ]] || exit 1
              substituteInPlace "$script" --replace-fail "$block" ""
              ;;
            1794341736)
              substituteInPlace "$script" --replace-fail 'user_mimeapps="$HOME/.config/mimeapps.list"' 'user_mimeapps="$HOME/.config/mimeapps.list"
              if [[ -L $user_mimeapps ]]; then
                echo "nixarchy: $user_mimeapps is a link, left alone"
                exit 0
              fi
              [[ ! -e $user_mimeapps || ( -f $user_mimeapps && -w $user_mimeapps ) ]] || exit 0'
              ;;
            1794387387)
              substituteInPlace "$script" \
                --replace-fail 'if [[ -f $bindings ]] && grep -qxF "$legacy" "$bindings"; then' \
                  '. @helper@
              if [[ -f $bindings ]] && ! store_owned "$bindings" && grep -qxF "$legacy" "$bindings"; then' \
                --replace-fail '@helper@' '${tree}/lib/nixarchy-store-owned.sh'
              ;;
            *) echo "no edit defined for $id" >&2; exit 1 ;;
          esac
          ;;
        *) echo "unknown migration run for $id: $run" >&2; exit 1 ;;
      esac
      printf '%s\t%s\n' "$id" "$script" >> "$out/list"
    done < rows
  ''
