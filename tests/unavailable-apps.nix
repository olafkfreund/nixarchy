{
  pkgs,
  vm,
}:
# Enabling an app that is unavailable warns instead of failing (#1201).
#
# An apps.nix written before an app was removed still says
# `<name>.enable = true`. Without an option for it that is "option does not
# exist", and the rebuild stops for something that should only cost a line.
# Evaluation only: the vm configuration, extended with the setting.
let
  inherit (pkgs) lib;

  warningsOf = c: lib.filter (w: lib.hasInfix "Grok Bot" w) c.config.warnings;

  enabled = vm.extendModules {
    modules = [ { programs.nixarchy.apps.grok-bot.enable = true; } ];
  };

  warned = warningsOf enabled;
  quiet = warningsOf vm;
in
pkgs.runCommand "nixarchy-unavailable-apps"
  {
    warnedCount = toString (lib.length warned);
    namesLine = lib.boolToString (lib.any (lib.hasInfix "grok-bot.enable") warned);
    quietCount = toString (lib.length quiet);
  }
  ''
    if [ "$warnedCount" != 1 ]; then
      echo "grok-bot.enable = true gave $warnedCount Grok Bot warnings, wanted 1" >&2
      exit 1
    fi
    if [ "$namesLine" != true ]; then
      echo "the warning does not name the line to delete (grok-bot.enable)" >&2
      exit 1
    fi
    if [ "$quietCount" != 0 ]; then
      echo "the vm warns about Grok Bot without enabling it" >&2
      exit 1
    fi
    echo "enabling an unavailable app warns and names the line to delete"
    touch $out
  ''
