{
  pkgs,
  menu,
  kbd,
  omarchy,
}:
pkgs.runCommand "nixarchy-installer-keymaps"
  {
    nativeBuildInputs = [
      pkgs.findutils
      pkgs.python3
      pkgs.kbd
      pkgs.libxkbcommon
      pkgs.lua5_4
    ];
  }
  ''
    set -euo pipefail
    maps=$(find ${kbd}/share/keymaps \( -type f -o -type l \) -name '*.map.gz' -print) || {
      echo 'FAILED: could not list pinned kbd keymaps' >&2
      exit 1
    }
    nonlatin=$(sed -n '/local non_latin_layouts =/{n;s/^[[:space:]]*"\([^"]*\)".*/\1/p;q;}' ${omarchy}/default/hypr/input.lua)
    [ -n "$nonlatin" ] || { echo 'FAILED: could not read non_latin_layouts from input.lua' >&2; exit 1; }

    work=$(mktemp -d)
    mkdir -p "$work/config/omarchy"
    printf '%s\n' \
      'package.path = arg[1].."/?.lua;"..package.path' \
      'hl={config=function(t) if t.input then print("kb_layout="..t.input.kb_layout.." kb_variant="..t.input.kb_variant.." kb_options="..t.input.kb_options) end end}' \
      'o={window=function() end}' \
      'package.loaded["default.hypr.paths"]={config_home=arg[2]}' \
      'local real=io.open' \
      'io.open=function(p,m) if p=="/etc/vconsole.conf" then return real(arg[3],m) end return real(p,m) end' \
      'dofile(arg[1].."/default/hypr/input.lua")' \
      >"$work/probe.lua"

    count=0
    failed=0
    while IFS= read -r line || [ -n "$line" ]; do
      [ -n "$line" ] || continue
      case "$line" in
        *$'\t'*) ;;
        *) echo "FAILED: malformed keymap menu row: $line" >&2; exit 1 ;;
      esac
      label=''${line%%$'\t'*}
      name=$(cut -f2 <<<"$line")
      xkb=$(cut -f3 <<<"$line")
      if [ -z "$label" ] || [ -z "$name" ] || [ -z "$xkb" ]; then
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

      lpart=''${xkb%%:*}
      vpart=""
      case "$xkb" in *:*) vpart=''${xkb#*:} ;; esac
      IFS=',' read -r -a larr <<<"$lpart"
      IFS=',' read -r -a varr <<<"$vpart"
      for ((i = 0; i < ''${#larr[@]}; i++)); do
        gl=''${larr[i]}
        gv=''${varr[i]:-}
        if [ -n "$gv" ]; then
          xkbcli compile-keymap --layout "$gl" --variant "$gv" >/dev/null || {
            echo "FAILED: $label XKB $gl:$gv did not compile" >&2
            failed=$((failed + 1))
          }
        else
          xkbcli compile-keymap --layout "$gl" >/dev/null || {
            echo "FAILED: $label XKB $gl did not compile" >&2
            failed=$((failed + 1))
          }
        fi
      done

      first=''${lpart%%,*}
      case "$nonlatin" in
        *" $first "*)
          echo "FAILED: $label first XKB group $first is in non_latin_layouts" >&2
          failed=$((failed + 1))
          ;;
      esac
      case "$lpart" in
        us,*)
          second=''${lpart#us,}
          case "$nonlatin" in
            *" $second "*) ;;
            *)
              echo "FAILED: $label has us,$second but $second is not in non_latin_layouts" >&2
              failed=$((failed + 1))
              ;;
          esac
          ;;
      esac

      printf 'XKBLAYOUT=%s\nXKBVARIANT=%s\n' "$lpart" "$vpart" >"$work/vconsole.conf"
      lua_out=$(lua "$work/probe.lua" ${omarchy} "$work/config" "$work/vconsole.conf")
      want_opts="omarchy:shift_caps_compose"
      case "$lpart" in
        us,*) want_opts="omarchy:shift_caps_compose,grp:alts_toggle" ;;
      esac
      want_lua="kb_layout=$lpart kb_variant=$vpart kb_options=$want_opts"
      if [ "$lua_out" != "$want_lua" ]; then
        echo "FAILED: $label: input.lua produced '$lua_out', expected '$want_lua'" >&2
        failed=$((failed + 1))
      fi
    done < ${menu}

    printf 'XKBLAYOUT=de\nXKBVARIANT=\n' >"$work/vconsole.conf"
    printf 'XKBLAYOUT=fr\n' >"$work/config/omarchy/keyboard-layouts"
    lua_out=$(lua "$work/probe.lua" ${omarchy} "$work/config" "$work/vconsole.conf")
    if [ "$lua_out" != "kb_layout=fr kb_variant= kb_options=omarchy:shift_caps_compose" ]; then
      echo "FAILED: keyboard-layouts did not beat vconsole.conf: $lua_out" >&2
      failed=$((failed + 1))
    fi

    LOADKEYS_KEYMAP_PATH='${pkgs.kbd}/share/keymaps/**' python3 ${./installer-keymaps-compare.py} ${menu} \
      ${pkgs.libxkbcommon}/lib/libxkbcommon.so.0 ${pkgs.libx11}/share/X11/locale/en_US.UTF-8/Compose || failed=$((failed + 1))

    [ "$count" -gt 0 ] || { echo 'FAILED: empty keymap menu' >&2; exit 1; }
    [ "$failed" -eq 0 ] || exit 1
    echo "OK: $count installer menu keymaps resolve in pinned kbd"
    mkdir -p "$out"
  ''
