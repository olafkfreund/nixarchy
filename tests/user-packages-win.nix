{
  pkgs,
  reference,
  lib,
}:
# #1167: a package nixarchy adds to environment.systemPackages without being
# asked must yield to a user's own copy of the same binary, which sits at the
# default priority (5). D1 (modules/nixos.nix, modules/apps.nix's tools block,
# modules/services/boxes.nix, modules/services/devenv.nix,
# modules/local-ai.nix) wraps every such contribution in `map lib.lowPrio`,
# which sets meta.priority = 10. This check proves that holds, and catches a
# future module that forgets the wrap.
#
# "nixarchy's entries" are whatever is in environment.systemPackages with
# nixarchy on and absent with programs.nixarchy.enable forced off. "The app
# picks" are whatever is absent when every programs.nixarchy.apps.* is forced
# off -- the user's own choice (owner's answer 2), exempt from the wrap.
#
# A NixOS service module nixarchy merely turns on (services.networkmanager,
# pipewire, cups, bluez, docker, sddm, ...) also disappears when nixarchy is
# off, so the plain diff above counts it as "nixarchy's" too -- but nixarchy
# never writes an environment.systemPackages line for it, and cannot wrap a
# list entry it does not own. Out of scope by design (owner's call, #1167
# review): excluded by definitionsWithLocations' file, which for every such
# package is somewhere under nixpkgs' own nixos/modules tree. Everything
# nixarchy's own modules.nix/apps.nix/etc contribute, by contrast, reaches
# `environment.systemPackages` through `import ./modules/*.nix args` rather
# than nix's path-tracked `imports = [ <path> ]`, so the module system cannot
# trace a _file for it and falls back to nixpkgs' own flake.nix -- the same
# fallback installer/host.nix's and installer/disk-config.nix's two inline
# modules land in. That does not produce a false offender today: neither adds
# a package gated on nixarchy, so neither appears in "nixarchy's entries" to
# begin with. Checked empirically (2026-10-03): every definitionsWithLocations
# value for this option is already a flat list of packages, with no mkIf/
# mkOrder wrapper to unwrap.
#
# The reference fixture leaves boxes, devenv and local-ai off, so a plain
# `reference` would never evaluate distrobox's, devenv's or
# opencode/pi-coding-agent's wraps -- a check that cannot fail for them
# (AGENTS.md §1). `base` turns every wrapped-but-optional site on: boxes and
# devenv need only their own enable; local-ai additionally needs allowCpu,
# because the reference declares no GPU and the module asserts against
# shipping an agent that would run on the CPU unannounced. Checked empirically
# (2026-10-03): all three enable cleanly against the reference fixture, no
# assertions fire, nothing here is unfree.
let
  base = reference.extendModules {
    modules = [
      {
        programs.nixarchy = {
          services.boxes.enable = true;
          services.devenv.enable = true;
          localAi = {
            enable = true;
            allowCpu = true;
            agents = [
              "opencode"
              "pi"
            ];
          };
        };
      }
    ];
  };

  noNixarchy = base.extendModules {
    modules = [ { programs.nixarchy.enable = lib.mkForce false; } ];
  };

  # The cleanest way found to express "no apps": every name
  # programs.nixarchy.apps declares an option for, forced off. Reading
  # .options rather than .config avoids forcing each app's own settings.
  noApps = base.extendModules {
    modules = [
      {
        programs.nixarchy.apps = lib.genAttrs (builtins.attrNames base.options.programs.nixarchy.apps) (_: {
          enable = lib.mkForce false;
        });
      }
    ];
  };

  # Attribute keys cannot carry a store path's context; a package's outPath
  # is otherwise exactly the identity a buildEnv list entry has.
  key = p: builtins.unsafeDiscardStringContext p.outPath;
  setOf = pkgs': lib.genAttrs (map key pkgs') (_: true);

  all = base.config.environment.systemPackages;
  nixarchyEntries = builtins.filter (
    p: !(setOf noNixarchy.config.environment.systemPackages ? ${key p})
  ) all;
  appPickSet = setOf (
    builtins.filter (p: !(setOf noApps.config.environment.systemPackages ? ${key p})) all
  );

  nixarchyEntrySet = setOf nixarchyEntries;

  # "Ours": not defined inside nixpkgs' own nixos/modules tree. Everything
  # that reaches this option through a nixpkgs service module keeps its real
  # file there; nixarchy's own contributions (and the two installer-only
  # ones, harmlessly) fall back to nixpkgs' flake.nix instead.
  #
  # Checked by the ITEM nixarchy's own definition contributed, not by
  # re-matching outPaths into the merged list: the same outPath can appear
  # twice in environment.systemPackages, once wrapped (nixarchy's own entry)
  # and once not (a nixpkgs service module's own, unrelated entry for the
  # same package, e.g. xdg-utils from both nixos.nix and a portal module) --
  # NixOS does not deduplicate a listOf by value, so a plain outPath lookup
  # cannot tell which instance it priority-checked. Filtering candidateItems
  # by nixarchyEntrySet (rather than filtering nixarchyEntries by "ours")
  # keeps the two apart.
  nixpkgsModulesPrefix = "${toString base.pkgs.path}/nixos/modules/";
  oursDefs = builtins.filter (
    d: !(lib.hasPrefix nixpkgsModulesPrefix d.file)
  ) base.options.environment.systemPackages.definitionsWithLocations;
  candidateItems = lib.concatMap (d: d.value) oursDefs;

  ours = builtins.filter (
    p: (nixarchyEntrySet ? ${key p}) && !(appPickSet ? ${key p})
  ) candidateItems;
  offenders = builtins.filter (p: (p.meta.priority or 5) < 10) ours;

  lines = map (p: "${p.name or "?"}: priority ${toString (p.meta.priority or 5)}") offenders;
in
pkgs.runCommand "nixarchy-user-packages-win" { } ''
  ${
    if offenders == [ ] then
      ''
        echo "checked ${toString (builtins.length ours)} nixarchy-contributed packages outside the app picks and outside NixOS' own service modules, all at priority >= 10"
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
