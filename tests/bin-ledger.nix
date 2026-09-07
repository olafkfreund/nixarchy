{ inputs, pkgs, ... }:
# Every shipped command is upstream's, or data/bin-ledger.nix says why it is not.
#
# The whole argument for this check's shape is in the ledger's own header, so
# it is not repeated here. The one thing worth saying at the derivation is why
# both trees are inputs: the class is DERIVED by comparing the built package
# against the source it was built from, so the check cannot be fooled by a
# ledger that agrees with itself. omarchy.src is the same store path as
# inputs.omarchy -- verified, not assumed -- which is what makes this pure.
let
  omarchy = inputs.self.packages.${pkgs.stdenv.hostPlatform.system}.omarchy;
in
pkgs.runCommand "nixarchy-bin-ledger"
  {
    nativeBuildInputs = [ pkgs.python3 ];
    ledger = builtins.toJSON (import ../data/bin-ledger.nix);
    passAsFile = [ "ledger" ];
  }
  ''
    python3 ${../.github/scripts/check-bin-ledger.py} \
      --upstream ${omarchy.src} \
      --shipped ${omarchy}/share/omarchy \
      --nix-bin ${../pkgs/omarchy/nix-bin} \
      --ledger "$ledgerPath"
    touch $out
  ''
