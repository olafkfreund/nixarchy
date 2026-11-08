{
  runCommand,
  jq,
  omarchy,
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
          script=${omarchy}/bin/omarchy-migrate-dictation-default
          test -f "$script"
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
            *) echo "no edit defined for $id" >&2; exit 1 ;;
          esac
          ;;
        *) echo "unknown migration run for $id: $run" >&2; exit 1 ;;
      esac
      printf '%s\t%s\n' "$id" "$script" >> "$out/list"
    done < rows
  ''
