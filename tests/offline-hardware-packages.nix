{ inputs, pkgs, ... }:
# The packages behind every selectable nixos-hardware module are on the
# offline image.
#
# checks.hardware-modules proves the installer picks the right MODULE NAMES.
# This proves the medium can satisfy them. They are different questions and
# only one of them has ever cost a release: #382 was a real machine whose
# generated config differed from the reference by a PACKAGE, on an image with
# no compiler, and the install walked backwards to the source bootstrap and
# died fetching a perl tarball from CPAN.
#
# installer/hardware-modules.sh made that failure mode reachable again and
# wider: common-gpu-intel alone pulls intel-media-driver, intel-compute-runtime
# and vpl-gpu-rt, and an offline Intel laptop selects it without asking. The
# reference-hardware host imports the union of every selectable module so those
# land in the closure the ISO bakes -- this asserts they actually did.
#
# It cannot be tested by installing: the QEMU guest has a virtio GPU, so no
# install test ever selects an Intel or AMD graphics module. The image's
# contents are the only place the question can be answered.
let
  ref = inputs.self.nixosConfigurations.reference-hardware;

  # Named as they appear in a store path. Not the nixpkgs attribute names --
  # what is asserted is what is ON the image, and the two differ often enough
  # (vpl-gpu-rt was onevpl-intel-gpu) that using the attribute would be
  # asserting something else.
  wanted = [
    # common-gpu-intel
    "intel-media-driver"
    "intel-compute-runtime"
    # common-gpu-amd / common-gpu-intel both want a mesa
    "mesa"
    # NOT microcode. common-cpu-{intel,amd} gate it on
    # hardware.enableRedistributableFirmware, so asserting it here would make
    # this check fail for a reason that has nothing to do with the image --
    # which it did on the first run. tests/firmware-guard.nix owns that claim.
  ];
in
pkgs.runCommand "nixarchy-offline-hardware-packages"
  {
    nativeBuildInputs = [ pkgs.gnugrep ];
    closure = "${pkgs.closureInfo { rootPaths = [ ref.config.system.build.toplevel ]; }}/store-paths";
    inherit wanted;
  }
  ''
    fails=0
    total=$(wc -l < "$closure")
    for w in $wanted; do
      if grep -q -- "-$w" "$closure"; then
        echo "  ok      $w is on the offline image"
      else
        echo "  FAILED  $w is NOT on the offline image"
        echo "          an offline install selecting the module that wants it"
        echo "          would build it from source, with no compiler."
        fails=$((fails + 1))
      fi
    done

    # A floor, for the same reason every other check here has one: if
    # reference-hardware ever stops evaluating to a real desktop, every grep
    # above fails at once and the message would read as four missing packages
    # rather than as the closure being empty.
    # 2192 measured on 2026-09-07. Half of it, so the floor catches a closure
    # that has collapsed without tripping on ordinary growth or shrinkage --
    # the first draft guessed 5000, which is simply above the real number and
    # would have failed forever.
    if [ "$total" -lt 1000 ]; then
      echo "  FAILED  the reference-hardware closure is only $total paths;"
      echo "          that is not a desktop, so the checks above proved nothing"
      fails=$((fails + 1))
    else
      echo "  ok      closure is $total paths"
    fi

    [ "$fails" = 0 ] || exit 1
    echo "the offline image can satisfy every module the installer selects"
    touch $out
  ''
