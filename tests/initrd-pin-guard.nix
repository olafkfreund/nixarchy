{ inputs, pkgs, ... }:
# The initrd pin installer/install.sh writes must stay conditional on the
# kernel it was captured from.
#
# What this defends, in full:
#
#   install.sh forces the installed machine's initrd module lists to the ones
#   the image carries, so the install copies the baked initrd instead of
#   spending minutes building a near-identical one. That pin is a frozen
#   literal list.
#
#   nixpkgs gates entries in the default initrd module set on kernel version:
#   kernel.nix and all-hardware.nix both add xhci_pci_prom21 under
#   `versionAtLeast kernel.version "7.2"`. Force a list captured at 7.2 onto a
#   machine running 6.18 and modprobe is asked for a module that does not
#   exist, and linux-6.18.49-modules-shrunk fails to build. That is not a
#   warning -- nixos-rebuild refuses to produce a system, so the machine's
#   next `omarchy update` fails outright.
#
#   It happened, on a machine installed from a 7.2 image whose /etc/nixos
#   still resolved nixarchy to a revision with no kernel policy.
#
# Two things are asserted, and the second is the one that rots quietly: that
# the guard is there at all, and that the version inside it is the version the
# module lists actually came from. A guard naming the wrong kernel is worse
# than none -- it would never apply, and the pin would silently stop working
# without anything failing.
let
  installer = inputs.self.packages.${pkgs.stdenv.hostPlatform.system}.install;

  # The same attribute flake.nix substitutes into @initrdkernel@.
  kernel =
    inputs.self.nixosConfigurations.reference-unencrypted.config.boot.kernelPackages.kernel.version;
in
pkgs.runCommand "nixarchy-initrd-pin-guard"
  {
    inherit kernel;
    script = "${installer}/bin/nixarchy-install";
  }
  ''
    guard='lib.mkIf (config.boot.kernelPackages.kernel.version == "%s")'

    grep -qF "$guard" "$script" || {
      echo "installer/install.sh writes an UNGUARDED initrd pin." >&2
      echo "" >&2
      echo "  expected this line to be emitted:" >&2
      echo "    $guard" >&2
      echo "" >&2
      echo "  A bare lib.mkForce of the baked module lists is only correct" >&2
      echo "  while the machine runs the kernel they were captured from." >&2
      echo "  nixpkgs adds xhci_pci_prom21 to the defaults at 7.2 and later;" >&2
      echo "  forcing that list onto an older kernel makes modprobe fail and" >&2
      echo "  the initrd underivable, so nixos-rebuild produces no system at" >&2
      echo "  all and the machine cannot update." >&2
      exit 1
    }

    grep -qF "kernelversion=\"$kernel\"" "$script" || {
      echo "the initrd pin's guard does not name the kernel the lists came from." >&2
      echo "" >&2
      echo "  reference-unencrypted is on: $kernel" >&2
      echo "  the installer says:          $(grep -o 'kernelversion="[^"]*"' "$script" || echo '<nothing>')" >&2
      echo "" >&2
      echo "  A guard naming the wrong kernel never applies, so the pin stops" >&2
      echo "  working and every install builds an initrd it did not need to." >&2
      echo "  Nothing fails; it just gets slower, which is why this is" >&2
      echo "  checked rather than trusted." >&2
      exit 1
    }

    echo "the initrd pin is guarded, and names $kernel -- the kernel its lists came from"
    touch $out
  ''
