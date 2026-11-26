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
      'local found = package.searchpath("hypr.monitors", package.path)' \
      'assert(found == os.getenv("WANT_FILE"), "hypr.monitors resolved to " .. tostring(found))' \
      'if os.getenv("WANT_USER") then assert(USER_MONITORS_RAN, "the user file did not run") end' \
      > runner.lua

    mkdir -p empty user/.config/hypr broken/.config/hypr
    # A global, not an hl call: quattro's defaults wrap hl, so a stubbed call can miss.
    printf '%s\n' 'USER_MONITORS_RAN = true' > user/.config/hypr/monitors.lua
    printf '%s\n' 'this is not lua !' > broken/.config/hypr/input.lua

    # Which file Lua resolved, not what it did: quattro's shipped monitors.lua
    # is all comments, so a call it makes cannot be the marker (#1954).
    HOME=$PWD/empty WANT_FILE=$OMARCHY_PATH/config/hypr/monitors.lua lua runner.lua "$config"
    HOME=$PWD/user WANT_FILE=$PWD/user/.config/hypr/monitors.lua WANT_USER=1 lua runner.lua "$config"
    if HOME=$PWD/broken WANT_FILE=$OMARCHY_PATH/config/hypr/monitors.lua lua runner.lua "$config" > broken.log 2>&1; then
      echo 'broken user input.lua was accepted' >&2
      exit 1
    fi
    grep -F "$PWD/broken/.config/hypr/input.lua" broken.log
    touch $out
  ''
