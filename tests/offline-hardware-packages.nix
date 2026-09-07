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
    # NOT the microcode. It is not a runtime reference of anything -- it lives
    # in boot.initrd.prepend -- so no closure will ever list it, and grepping
    # for it here can only ever fail. It is asserted below, where it can
    # actually be seen.
  ];
in
pkgs.runCommand "nixarchy-offline-hardware-packages"
  {
    nativeBuildInputs = [ pkgs.gnugrep ];
    # Both mechanisms the image uses, because the two kinds of package arrive
    # by different routes and only one is a runtime reference.
    #
    # The GPU drivers are in reference-hardware's toplevel, which cd.nix bakes
    # via isoImage.storeContents. The microcode is NOT in any toplevel: it
    # lives in boot.initrd.prepend, so it is a build input of the initrd image
    # and a runtime reference of nothing -- it reaches the medium as one of
    # the initrd's BUILD inputs, which cd.nix seeds via
    # initialRamdisk.inputDerivation. So that derivation is the second root.
    #
    # Deliberately not the ISO's own toplevel, which would assert the same
    # thing: it drags in flake-template, which refuses to build from a dirty
    # tree, and this would become the one check that cannot be run while
    # editing.
    #
    # A check rooted only at reference-hardware could never see the microcode,
    # and that blind spot is exactly how it stayed missing.
    closure = "${
      pkgs.closureInfo {
        rootPaths = [ ref.config.system.build.toplevel ];
      }
    }/store-paths";
    inherit wanted;

    # What the initrd is told to prepend, which is the only place the microcode
    # is visible at all.
    #
    # This is the invariant that was broken and could not be seen: the
    # reference host baked onto the image had no microcode and every installed
    # machine asked for it, because nixos-generate-config emits those two lines
    # only on bare metal. Seeded and installed drifted, and an offline install
    # had to compile microcode-intel with no compiler.
    #
    # Asserted on the REFERENCE, deliberately. cd.nix seeds
    # initialRamdisk.inputDerivation for every reference config, so the medium
    # carries whatever that initrd is built from -- which makes "the reference
    # wants the microcode" and "the microcode is on the image" the same claim.
    # `reference`, NOT reference-hardware. reference-hardware imports
    # nixos-hardware's common-cpu-*, which sets updateMicrocode itself -- so an
    # assertion there passes whether or not nixarchy's own module does, and a
    # first draft of this did exactly that: it read the one config that could
    # not fail. `reference` is the host tests/install.nix actually seeds, and
    # the one that drifted.
    prepend = toString inputs.self.nixosConfigurations.reference.config.boot.initrd.prepend;
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

    for u in microcode-intel amd-ucode; do
      if printf '%s' "$prepend" | grep -q -- "-$u"; then
        echo "  ok      the reference initrd prepends $u"
      else
        echo "  FAILED  the reference initrd does NOT prepend $u"
        echo "          so the image carries no microcode, and any real"
        echo "          machine -- which always asks for it -- has to build it"
        fails=$((fails + 1))
      fi
    done

    [ "$fails" = 0 ] || exit 1
    echo "the offline image can satisfy every module the installer selects"
    touch $out
  ''
