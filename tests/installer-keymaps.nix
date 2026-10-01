{
  pkgs,
  menu,
  kbd,
}:
pkgs.runCommand "nixarchy-installer-keymaps" { nativeBuildInputs = [ pkgs.findutils ]; } ''
  set -euo pipefail
  maps=$(find ${kbd}/share/keymaps \( -type f -o -type l \) -name '*.map.gz' -print) || {
    echo 'FAILED: could not list pinned kbd keymaps' >&2
    exit 1
  }
  count=0
  failed=0
  while IFS= read -r line || [ -n "$line" ]; do
    [ -n "$line" ] || continue
    case "$line" in
      *$'\t'*) ;;
      *) echo "FAILED: malformed keymap menu row: $line" >&2; exit 1 ;;
    esac
    label=''${line%%$'\t'*}
    name=''${line#*$'\t'}
    if [ -z "$label" ] || [ -z "$name" ] || [[ "$name" == *$'\t'* ]]; then
      echo "FAILED: malformed keymap menu row: $line" >&2
      exit 1
    fi
    count=$((count + 1))
    found=0
    while IFS= read -r path; do
      if [ "''${path##*/}" = "$name.map.gz" ] && [ -f "$path" ]; then
        found=1
        break
      fi
    done <<< "$maps"
    if [ "$found" -eq 0 ]; then
      echo "FAILED: $label names missing pinned kbd keymap $name" >&2
      failed=$((failed + 1))
    fi
  done < ${menu}
  [ "$count" -gt 0 ] || { echo 'FAILED: empty keymap menu' >&2; exit 1; }
  [ "$failed" -eq 0 ] || exit 1
  echo "OK: $count installer menu keymaps resolve in pinned kbd"
  mkdir -p "$out"
''
