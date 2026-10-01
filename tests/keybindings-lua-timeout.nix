{ pkgs, ... }:
let
  menuPath = pkgs.lib.makeBinPath [
    pkgs.omarchy
    pkgs.coreutils
    pkgs.gawk
    pkgs.gnugrep
    pkgs.findutils
  ];
in
pkgs.runCommand "nixarchy-keybindings-lua-timeout" { nativeBuildInputs = [ pkgs.shellcheck ]; } ''
  set -eu
  work=$(mktemp -d)
  mkdir -p "$work/bin" "$work/bin-no-lua" "$work/home/.config/hypr"

  cat > "$work/bin/lua" <<'SH'
  #!${pkgs.bash}/bin/bash
  printf '%s\n' "$$" > "$LUA_PID_FILE"
  exec ${pkgs.lua}/bin/lua "$@"
  SH

  cat > "$work/bin/hyprctl" <<'SH'
  #!${pkgs.bash}/bin/bash
  case "$1" in
    binds)
      printf 'bind\n\tmodmask: 64\n\tkey: \n\tkeycode: 0\n\tdescription: Lua fixture\n\tdispatcher: __lua\n\targ: \n'
      ;;
    devices) ;;
    *) exit 1 ;;
  esac
  SH

  cat > "$work/bin/xkbcli" <<'SH'
  #!${pkgs.bash}/bin/bash
  exit 0
  SH
  chmod +x "$work/bin"/*
  ln -s "$work/bin/hyprctl" "$work/bin-no-lua/hyprctl"
  ln -s "$work/bin/xkbcli" "$work/bin-no-lua/xkbcli"

  cleanup() {
    for pid_file in "$work"/*.pid; do
      [ -s "$pid_file" ] || continue
      pid=$(cat "$pid_file")
      if kill -0 "$pid" 2>/dev/null; then
        kill "$pid" 2>/dev/null || true
      fi
    done
  }
  trap cleanup EXIT

  run_menu() {
    name=$1
    bin=$2
    mkdir -p "$work/cache-$name"
    pid_file="$work/$name.pid"
    if env HOME="$work/home" XDG_CACHE_HOME="$work/cache-$name" \
      LUA_PID_FILE="$pid_file" PATH="$bin:${menuPath}" \
      ${pkgs.coreutils}/bin/timeout --foreground -k 1s 7s \
      ${pkgs.omarchy}/bin/omarchy-menu-keybindings --print \
      > "$work/$name.out" 2> "$work/$name.err"; then
      :
    else
      status=$?
      echo "FAIL $name: menu exited $status (outer timeout means the Lua scan is unbounded)" >&2
      cat "$work/$name.err" >&2
      exit 1
    fi
    if [ -s "$pid_file" ]; then
      pid=$(cat "$pid_file")
      if kill -0 "$pid" 2>/dev/null; then
        echo "FAIL $name: Lua scan PID $pid survived the menu" >&2
        exit 1
      fi
    fi
    if ! grep -Fq 'Copy URL from Web App' "$work/$name.out"; then
      echo "FAIL $name: static keybindings disappeared" >&2
      cat "$work/$name.out" >&2
      exit 1
    fi
  }

  printf '%s\n' 'while true do end' > "$work/home/.config/hypr/hyprland.lua"
  run_menu loop "$work/bin"
  [ -s "$work/loop.pid" ] || { echo 'FAIL loop: Lua was never started' >&2; exit 1; }
  echo 'OK looping Lua scan stopped within the menu bound, with no surviving PID'

  printf '%s\n' 'hl.bind("SUPER + T", hl.dsp.exec_cmd("echo hi"), { description = "Lua fixture" })' > "$work/home/.config/hypr/hyprland.lua"
  run_menu normal "$work/bin"
  if ! grep -Eq 'SUPER \+ T.*Lua fixture' "$work/normal.out"; then
    echo 'FAIL normal: the terminating Lua binding was lost' >&2
    cat "$work/normal.out" >&2
    exit 1
  fi
  echo 'OK terminating Lua config still supplies its binding'

  run_menu no-lua "$work/bin-no-lua"
  [ ! -e "$work/no-lua.pid" ] || { echo 'FAIL no-lua: Lua unexpectedly started' >&2; exit 1; }
  echo 'OK absent Lua still leaves static bindings available'

  shellcheck -s bash ${pkgs.omarchy}/bin/omarchy-menu-keybindings
  echo 'OK built keybindings script passes ShellCheck'
  touch "$out"
''
