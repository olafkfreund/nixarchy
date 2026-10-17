{ pkgs, omarchy }:
# #1305: a partial override in the user's omarchy-menu.jsonc keeps the rest
# of the row. Node runs the BUILT MenuModel.js; tests/AGENTS.md has the why.
pkgs.runCommand "nixarchy-menu-model-merge" { nativeBuildInputs = [ pkgs.nodejs ]; } ''
  node ${./menu-model-merge.js} ${omarchy}/share/omarchy/shell/plugins/menu/MenuModel.js
  touch $out
''
