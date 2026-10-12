{
  pkgs,
  pluginNames, # builtins.attrNames of defaultPluginSet
  services, # import ../data/services.nix
  doc, # ../docs/manual/configuration.md
}:
# configuration.md lists every default plugin and every service by the line that
# turns it off or on. The plugin list had drifted to 9 of 16 without anything
# going red (#1246), so this names each missing line instead of counting.
let
  inherit (pkgs) lib;
  pluginLines = map (n: "programs.nixarchy.defaultPlugins.${n} = false;") pluginNames;
  # The same rule as serviceRow in modules/apps.nix.
  serviceLines = lib.mapAttrsToList (
    name: svc:
    if svc.kind == "bundled" then
      "programs.nixarchy.services.${name}.enable = true;"
    else
      "${lib.concatStringsSep "." svc.option}.${svc.optionAttr or "enable"} = true;"
  ) services;
  linesFile = name: ls: pkgs.writeText name (lib.concatMapStrings (l: l + "\n") ls);
in
pkgs.runCommand "nixarchy-docs-lists" { } ''
  set -euo pipefail
  # An empty list is not a pass.
  [ ${toString (builtins.length pluginLines)} -gt 0 ] || { echo "FAILED: no plugin names"; exit 1; }
  [ ${toString (builtins.length serviceLines)} -gt 0 ] || { echo "FAILED: no services"; exit 1; }
  missing=0
  # Each line must be where a reader looks for it: a plugin line alone on a line
  # in the code block, a service line in the table's third column. A bare
  # substring match is satisfied by prose, so a dropped row would go unseen.
  while IFS= read -r line; do
    if ! grep -qxF -- "$line" ${doc}; then
      echo "FAILED: configuration.md does not mention $line"
      missing=1
    fi
  done < ${linesFile "docs-lists-plugins" pluginLines}
  while IFS= read -r line; do
    if ! grep -qF -- "| \`$line\` |" ${doc}; then
      echo "FAILED: configuration.md has no table row for $line"
      missing=1
    fi
  done < ${linesFile "docs-lists-services" serviceLines}
  [ "$missing" = 0 ] || exit 1
  touch $out
''
