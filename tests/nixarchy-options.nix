{ pkgs, reference }:
# #1166: the catalogue nixarchy-options builds and ships to /etc/nixarchy,
# checked for the three things a silent regression would otherwise hide --
# every non-flatsnap option names its real file rather than a store path
# (the _file wraps in flake.nix), the two /etc entries are Mode A inert
# (gated on cfg.enable, not written unconditionally), and the docs linkFarm
# actually carries the manual.
#
# programs.nixarchy.flatsnap.* is exempt from the declaration rule: those
# options are declared by inputs.nixarchy-flatsnap's own module, a separate
# flake this one does not control the _file of. See modules/AGENTS.md.
let
  inherit (pkgs) lib;
  opts = reference.config.system.build.nixarchyOptions;
  etc = reference.config.environment.etc;
  off =
    (reference.extendModules {
      modules = [ { programs.nixarchy.enable = lib.mkForce false; } ];
    }).config.environment.etc;

  hasOn = (etc ? "nixarchy/options.json") && (etc ? "nixarchy/docs");
  hasOff = (off ? "nixarchy/options.json") || (off ? "nixarchy/docs");
in
pkgs.runCommand "nixarchy-options-check"
  {
    options = "${opts}/share/doc/nixos/options.json";
    docs = etc."nixarchy/docs".source;
    hasOn = if hasOn then "1" else "0";
    hasOff = if hasOff then "1" else "0";
    nativeBuildInputs = [ pkgs.jq ];
  }
  ''
    n=$(jq 'length' "$options")
    [ "$n" -gt 250 ] || {
      echo "only $n options in the catalogue (expected > 250)" >&2
      exit 1
    }

    for k in 'programs.nixarchy.enable' 'home-manager.users.<name>.programs.nixarchy.enable'; do
      jq -e --arg k "$k" 'has($k)' "$options" >/dev/null || {
        echo "the catalogue has no key for $k" >&2
        exit 1
      }
    done

    offenders=$(jq -r '
      to_entries
      | map(select(
          (.key | startswith("programs.nixarchy.flatsnap.") | not)
          and (.value.declarations | any(type == "string"))
        ))
      | .[].key
    ' "$options")
    if [ -n "$offenders" ]; then
      echo "options with a store-path (not a URL) declaration:" >&2
      printf '%s\n' "$offenders" | head -n 3 >&2
      exit 1
    fi

    if [ "$hasOn" != 1 ] || [ "$hasOff" != 0 ]; then
      echo "Mode A: on=$hasOn (want 1) off=$hasOff (want 0)" >&2
      exit 1
    fi

    [ -e "$docs/llms.txt" ] || {
      echo "the docs linkFarm has no llms.txt" >&2
      exit 1
    }
    manualCount=$(find -L "$docs/manual" -name '*.md' | wc -l)
    [ "$manualCount" -ge 30 ] || {
      echo "only $manualCount manual/*.md under the docs linkFarm (expected >= 30)" >&2
      exit 1
    }

    echo "nixarchy-options: $n options, both enable keys, no bad declarations, Mode A inert, $manualCount manual pages"
    touch $out
  ''
