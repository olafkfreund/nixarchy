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
  allRows = import ../data/omarchy-packages.nix;
  # Inactive rows are dropped only after every row has been validated.
  ledger = lib.filterAttrs (
    _: r: !(r.edge or "" == "only" && !isEdge || r.edge or "" == "absent" && isEdge)
  ) allRows;
  # Exactly one key, nix/module/skip, holding a non-empty string: a typo'd extra
  # key or an empty reason is not a decision.
  # An optional `edge` marker ("only" or "absent") is validated first and is not a decision key.
  isEdge = lib.hasPrefix "edge-" pkgs.omarchy.version;
  wellFormed =
    r:
    let
      ks = lib.filter (k: k != "edge") (lib.attrNames r);
    in
    (
      !(r ? edge)
      || lib.elem r.edge [
        "only"
        "absent"
      ]
    )
    && lib.length ks == 1
    && lib.elem (lib.head ks) [
      "nix"
      "module"
      "skip"
    ]
    && lib.isString r.${lib.head ks}
    && r.${lib.head ks} != "";
  malformed = lib.filter (n: !wellFormed allRows.${n}) (lib.attrNames allRows);
  # A `nix` row must name a package, not merely an attribute (`lib` exists too).
  resolved = lib.mapAttrs (
    _: r:
    if r ? nix then lib.isDerivation (lib.attrByPath (lib.splitString "." r.nix) null pkgs) else true
  ) ledger;
in
assert lib.assertMsg (malformed == [ ])
  "data/omarchy-packages.nix: rows that are not exactly one non-empty nix/module/skip string: ${lib.concatStringsSep ", " malformed}";
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
    sed -E 's/#.*//; s/^[[:space:]]+//; s/[[:space:]]+$//' $lists | grep -v '^$' | sort -u > wanted
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
