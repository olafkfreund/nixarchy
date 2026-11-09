{
  runCommand,
  jq,
  omarchy,
  omarchy-nvim-config,
}:
let
  ledger = builtins.toFile "nixarchy-user-migrations.json" (
    builtins.toJSON (import ../../data/user-migrations.nix)
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
            *) echo "no edit defined for $id" >&2; exit 1 ;;
          esac
          ;;
        *) echo "unknown migration run for $id: $run" >&2; exit 1 ;;
      esac
      printf '%s\t%s\n' "$id" "$script" >> "$out/list"
    done < rows
  ''
