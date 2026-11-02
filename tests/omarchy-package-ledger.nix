{ pkgs, ... }:
# Every package name Omarchy installs, classified in data/omarchy-packages.nix.
#
# The delta script reports a name that changes between two Omarchy tags; it
# cannot say that nobody decided about a new one. This holds the ledger to the
# real lists in the real tree, in three directions, and names all offenders:
#
#   a name in the lists with no row       unclassified
#   a row for a name no list has          stale
#   a `nix` row that does not evaluate    unresolvable
#
# The `nix` rows are resolved at evaluation time against pkgs WITH the overlay,
# because a bash step cannot ask Nix whether an attribute exists.
let
  inherit (pkgs) lib;
  ledger = import ../data/omarchy-packages.nix;
  oneOf =
    r:
    lib.count (k: r ? ${k}) [
      "nix"
      "module"
      "skip"
    ];
  malformed = lib.filter (n: oneOf ledger.${n} != 1) (lib.attrNames ledger);
  resolved = lib.mapAttrs (
    _: r: if r ? nix then lib.hasAttrByPath (lib.splitString "." r.nix) pkgs else true
  ) ledger;
in
assert lib.assertMsg (malformed == [ ])
  "data/omarchy-packages.nix: rows with not exactly one of nix/module/skip: ${lib.concatStringsSep ", " malformed}";
pkgs.runCommand "nixarchy-omarchy-package-ledger"
  {
    nativeBuildInputs = [ pkgs.jq ];
    ledgerNames = builtins.toJSON (lib.attrNames ledger);
    resolvedJson = builtins.toJSON resolved;
    passAsFile = [
      "ledgerNames"
      "resolvedJson"
    ];
  }
  ''
    set -euo pipefail
    lists=$(ls ${pkgs.omarchy}/share/omarchy/install/*.packages)
    [ -n "$lists" ] || { echo "no *.packages lists in the omarchy tree" >&2; exit 1; }
    # shellcheck disable=SC2086
    grep -hvE '^\s*(#|$)' $lists | sort -u > wanted
    [ -s wanted ] || { echo "the lists named no packages" >&2; exit 1; }
    jq -r '.[]' "$ledgerNamesPath" | sort -u > have
    jq -r 'to_entries[] | select(.value == false) | .key' "$resolvedJsonPath" | sort -u > unresolvable
    comm -23 wanted have > unclassified
    comm -13 wanted have > stale

    fail=0
    report() {
      if [ -s "$2" ]; then
        printf '%s:\n' "$1" >&2
        sed 's/^/  /' "$2" >&2
        fail=1
      fi
    }
    report "unclassified (in an install list, no row in data/omarchy-packages.nix)" unclassified
    report "stale (a row for a name no install list has)" stale
    report "unresolvable (a nix row whose attribute is not in pkgs)" unresolvable
    [ "$fail" = 0 ] || exit 1
    echo "$(wc -l < wanted) names classified" > $out
  ''
