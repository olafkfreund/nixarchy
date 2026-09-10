{ inputs, pkgs }:
# The shipped images carry the reference machines, and nothing else does.
#
# installer/cd.nix used to name `inputs.self.nixosConfigurations.reference`
# directly. Since #479 it takes a `source` argument instead, so that a user can
# build an image carrying THEIR machines (#478) from the same module rather
# than a second copy of a 900-line file.
#
# That parameter is the risk this check exists for. `source` is passed from
# flake.nix, and a wrong value there does not fail to evaluate -- it produces a
# perfectly good ISO carrying the wrong closure. The failure would surface as
# an install that builds the world on a machine with no network, which is
# #436's symptom and took three days to diagnose the last time.
#
# The refactor itself was proven not to change the shipped image, by evaluating
# the old and new modules in the SAME tree and comparing derivations:
#
#   old: /nix/store/ph0kzibybvalwvndh846xxxav28jic4c-...-x86_64.iso.drv
#   new: /nix/store/ph0kzibybvalwvndh846xxxav28jic4c-...-x86_64.iso.drv
#
# Same tree matters. Comparing across commits cannot work here and it is worth
# writing down why: `inputSources` carries `flake.outPath`, so the source
# tree's own store path is in the closure, and it changes with every commit.
# A cross-commit comparison is confounded by construction, and the first
# attempt at this check read that noise as a real difference.
let
  inherit (pkgs) lib;

  iso = inputs.self.nixosConfigurations.iso.config;
  isoNet = inputs.self.nixosConfigurations.iso-net.config;

  # Named rather than derived from `source`, on purpose: deriving the
  # expectation from the thing under test is how a check comes to assert that
  # a value equals itself. These three are a decision recorded in flake.nix,
  # and this is the copy that disagrees when somebody changes it.
  expected = map (n: inputs.self.nixosConfigurations.${n}.config.system.build.toplevel) [
    "reference"
    "reference-unencrypted"
    "reference-hardware"
  ];

  missingFrom = sc: builtins.filter (t: !(builtins.elem t sc)) expected;
in
pkgs.runCommand "nixarchy-iso-source"
  {
    offlineMissing = lib.concatStringsSep " " (missingFrom iso.isoImage.storeContents);
    offlineCount = toString (builtins.length iso.isoImage.storeContents);

    # The network image carries no toplevels -- it fetches them -- so the
    # assertion is the opposite one. Both directions, because a `source` that
    # silently emptied the offline image and a `source` that silently filled
    # the network one are the same mistake seen from two sides.
    netCount = toString (builtins.length isoNet.isoImage.storeContents);
    netHasToplevels = lib.concatStringsSep " " (
      builtins.filter (t: builtins.elem t isoNet.isoImage.storeContents) expected
    );
  }
  ''
    echo "offline storeContents: $offlineCount entries"
    echo "network storeContents: $netCount entries"

    if [ -n "$offlineMissing" ]; then
      echo "::error::the offline image does not carry the reference machines:" >&2
      for t in $offlineMissing; do echo "  $t" >&2; done
      echo >&2
      echo "  installer/cd.nix bakes whatever `source.configs` names, and" >&2
      echo "  flake.nix decides that. An image missing a reference toplevel" >&2
      echo "  installs a machine that has to BUILD it -- with no network, that" >&2
      echo "  is the source bootstrap, which is #436." >&2
      exit 1
    fi

    if [ -n "$netHasToplevels" ]; then
      echo "::error::the NETWORK image is carrying system closures:" >&2
      for t in $netHasToplevels; do echo "  $t" >&2; done
      echo "  It is meant to fetch them. Carrying them makes it the size of" >&2
      echo "  the offline image for no benefit -- checks.iso-budget will" >&2
      echo "  notice eventually, this notices now and says why." >&2
      exit 1
    fi

    # A floor. Both lists coming back empty satisfies every test above while
    # proving nothing, which is the failure this repository has been bitten by
    # more than once.
    if [ "$offlineCount" -lt 3 ]; then
      echo "::error::the offline image has $offlineCount storeContents entries," >&2
      echo "  which cannot include three toplevels. The check is refusing" >&2
      echo "  rather than passing on an answer it did not get." >&2
      exit 1
    fi

    echo "the offline image carries all three reference machines"
    echo "the network image carries none of them"
    touch $out
  ''
