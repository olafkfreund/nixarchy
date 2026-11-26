{ pkgs, ... }:
pkgs.runCommand "nixarchy-hypr-seedless"
  {
    nativeBuildInputs = [ pkgs.lua5_4 ];
  }
  ''
    export OMARCHY_PATH=${pkgs.omarchy}/share/omarchy
    config=${pkgs.omarchy}/share/omarchy/config/hypr/hyprland.lua
    printf '%s\n' \
      'local calls = {}' \
      'local proxy = setmetatable({}, { __index = function(self) return self end, __call = function() return "stub" end })' \
      'hl = setmetatable({ monitor = function(arg) calls[#calls + 1] = arg.output end }, { __index = function() return proxy end })' \
      'dofile(arg[1])' \
      'assert(calls[1] == (os.getenv("WANT_MONITOR") or ""), "wrong monitor config loaded")' \
      > runner.lua

    mkdir -p empty user/.config/hypr broken/.config/hypr
    printf '%s\n' 'hl.monitor({ output = "user" })' > user/.config/hypr/monitors.lua
    printf '%s\n' 'this is not lua !' > broken/.config/hypr/input.lua

    HOME=$PWD/empty WANT_MONITOR="" lua runner.lua "$config"
    HOME=$PWD/user WANT_MONITOR=user lua runner.lua "$config"
    if HOME=$PWD/broken WANT_MONITOR="" lua runner.lua "$config" > broken.log 2>&1; then
      echo 'broken user input.lua was accepted' >&2
      exit 1
    fi
    grep -F "$PWD/broken/.config/hypr/input.lua" broken.log
    touch $out
  ''
