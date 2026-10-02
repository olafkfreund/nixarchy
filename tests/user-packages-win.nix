{
  pkgs,
  reference,
  lib,
}:
# #1167: a package nixarchy adds to environment.systemPackages without being
# asked must yield to a user's own copy of the same binary, which sits at the
# default priority (5). D1 (modules/nixos.nix, modules/apps.nix's tools block,
# modules/services/boxes.nix, modules/local-ai.nix) wraps every such
# contribution in `map lib.lowPrio`, which sets meta.priority = 10. This
# check proves that holds, and catches a future module that forgets the wrap.
#
# "nixarchy's entries" are whatever is in environment.systemPackages with
# nixarchy on and absent with programs.nixarchy.enable forced off.
# "The app picks" are whatever is absent when every programs.nixarchy.apps.*
# is forced off -- the user's own choice (owner's answer 2), exempt from the
# wrap. Offenders are nixarchy's entries that are not app picks and sit below
# priority 10.
let
  noNixarchy = reference.extendModules {
    modules = [ { programs.nixarchy.enable = lib.mkForce false; } ];
  };

  # The cleanest way found to express "no apps": every name
  # programs.nixarchy.apps declares an option for, forced off. Reading
  # .options rather than .config avoids forcing each app's own settings.
  noApps = reference.extendModules {
    modules = [
      {
        programs.nixarchy.apps =
          lib.genAttrs (builtins.attrNames reference.options.programs.nixarchy.apps)
            (_: {
              enable = lib.mkForce false;
            });
      }
    ];
  };

  # Attribute keys cannot carry a store path's context; a package's outPath
  # is otherwise exactly the identity a buildEnv list entry has.
  key = p: builtins.unsafeDiscardStringContext p.outPath;
  setOf = pkgs: lib.genAttrs (map key pkgs) (_: true);

  all = reference.config.environment.systemPackages;
  nixarchyEntries = builtins.filter (
    p: !(setOf noNixarchy.config.environment.systemPackages ? ${key p})
  ) all;
  appPickSet = setOf (
    builtins.filter (p: !(setOf noApps.config.environment.systemPackages ? ${key p})) all
  );

  nonAppNixarchy = builtins.filter (p: !(appPickSet ? ${key p})) nixarchyEntries;
  offenders = builtins.filter (p: (p.meta.priority or 5) < 10) nonAppNixarchy;

  lines = map (p: "${p.name or "?"}: priority ${toString (p.meta.priority or 5)}") offenders;
in
pkgs.runCommand "nixarchy-user-packages-win" { } ''
  ${
    if offenders == [ ] then
      ''
        echo "checked ${toString (builtins.length nonAppNixarchy)} nixarchy-contributed packages outside the app picks, all at priority >= 10"
        touch $out
      ''
    else
      ''
        echo "FAIL: nixarchy-contributed packages below priority 10, outside the app picks (#1167):" >&2
        ${lib.concatMapStringsSep "\n" (l: "echo ${lib.escapeShellArg l} >&2") lines}
        exit 1
      ''
  }
''
