{ pkgs, sources }:
# Qt 6.12's QtQuick has its own `Color` singleton, which shadows qs.Commons'
# for an unqualified `Color.` whatever the import order: the palette reads
# undefined and the panel loses its colours (#1381). checks.session saw one
# panel of seventeen, so this reads every plugin nixarchy ships instead.
# `sources` is name -> tree; flake.nix derives it from defaultPluginSet.
pkgs.runCommand "nixarchy-qml-color-qualified" { nativeBuildInputs = [ pkgs.gnugrep ]; } ''
  bad=0
  ${pkgs.lib.concatStrings (
    pkgs.lib.mapAttrsToList (name: src: ''
      if hits=$(grep -rnE '(^|[^.A-Za-z_])Color\.[a-z]' --include='*.qml' ${src}); then
        echo "${name}: unqualified Color. (write Commons.Color.):" >&2
        printf '%s\n' "$hits" >&2
        bad=1
      fi
    '') sources
  )}
  [ "$bad" = 0 ] || exit 1
  touch $out
''
