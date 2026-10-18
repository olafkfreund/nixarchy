{
  pkgs,
  omarchy,
  menuPlugin,
  nixi,
}:
# #1305, #1314: a partial override in the user's omarchy-menu.jsonc keeps the
# rest of the row. Node runs the BUILT MenuModel.js (tests/AGENTS.md has the
# why) in three readers: the stock menu, nixarchy-menu and nixi. The last two
# import a store path, read here out of their built QML. `nixi` is
# services.nixi.package, not the module's nixiPkg: the module re-overrides
# only the adapters (hm-module.nix:18), which leaves omarchySrc as set.
pkgs.runCommand "nixarchy-menu-model-merge" { nativeBuildInputs = [ pkgs.nodejs ]; } ''
  node ${./menu-model-merge.js} ${omarchy}/share/omarchy/shell/plugins/menu/MenuModel.js
  for qml in ${menuPlugin}/providers/OmarchyMenu.qml \
      ${nixi}/share/omarchy/plugins/io.github.olafkfreund.nixi/MenuSearch.qml; do
    # `|| true` keeps the message below reachable under stdenv's set -eu -o pipefail.
    model=$(grep -oE 'file:///nix/store/[^"]*/MenuModel\.js' "$qml" | head -1 || true)
    [ -n "$model" ] || { echo "menu-model-merge: $qml imports no store MenuModel.js"; exit 1; }
    echo "menu-model-merge: $qml"
    node ${./menu-model-merge.js} "''${model#file://}"
  done
  touch $out
''
