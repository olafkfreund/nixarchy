{
  inputs,
  pkgs,
  stableVm,
}:
# This flake still evaluates against stable nixpkgs (#527).
#
# ## What this proves, and what it does not
#
# It proves EVALUATION. The expression is valid against nixos-26.05: every
# attribute it names exists, every option it sets is an option, and the
# system's derivation can be computed.
#
# It does NOT prove the machine boots, that the desktop comes up, or that
# anything on it works. Nothing here starts a VM. Read a green tick on this
# check as "the expression is valid on stable" and nothing more -- the
# temptation is to read it as "stable works", and it does not say that.
#
# That limit is a budget decision, not an oversight. The install job is 55 of
# 58 minutes on a single self-hosted runner and gates every pull request; a
# second install slot for stable would roughly double merge latency on the
# hardware that is already the bottleneck. Evaluation is what is affordable,
# so evaluation is what is claimed.
#
# ## Why it exists
#
# Stable stopped evaluating and nobody noticed, because nothing looked:
#
#   error: undefined variable 'hyprland-preview-share-picker'
#   at modules/nixos.nix:758
#
# The cheapest class of failure there is, found by hand months later. This
# costs about twenty seconds and no VM.
#
# ## Why the assertions below, and not just the evaluation
#
# Forcing the toplevel would catch an `undefined variable`. It would not
# catch the thing that made stable DANGEROUS rather than merely broken:
# nixos-26.05 ships quickshell 0.3.0, whose session lock reaches qFatal when
# screens sleep and wake while locked, leaving the machine blank with nowhere
# to type a password (#35, #528). That was fixed by a floor in flake.nix, and
# a floor with nothing watching it is one somebody removes as dead code.
let
  inherit (pkgs) lib;

  cfg = stableVm.config;

  # The evaluation itself. `unsafeDiscardStringContext` on purpose: the point
  # is to force the system's derivation to be COMPUTED, not to build it. With
  # the context left on, this check would depend on the stable toplevel and a
  # twenty-second evaluation would become a full system build of a package set
  # nothing here has cached -- which is precisely the install-slot cost this
  # check exists to avoid.
  toplevel = builtins.unsafeDiscardStringContext cfg.system.build.toplevel.drvPath;

  release = stableVm.pkgs.lib.trivial.release;

  # #528, watched. Read off the built system's own package set rather than
  # from nixpkgs, because what matters is the version the SESSION launches
  # after the floor in flake.nix has been applied -- asking nixpkgs directly
  # would ask a question whose answer is 0.3.0 and always was.
  quickshellVersion = cfg.programs.nixarchy.package.passthru.quickshell.version;
in
pkgs.runCommand "nixarchy-stable-eval"
  {
    inherit toplevel release;

    # Named so the log says which stable this was, not merely "stable".
    stableRev = inputs.nixpkgs-stable.rev or "unlocked";

    # #526, watched from the other side. The picker is absent on 26.05, and
    # modules/nixos.nix guards it -- so the guard is doing its job when this
    # is false, and the guard has become dead code when it is true. Either is
    # worth knowing; only one of them is worth failing on, below.
    pickerPresent = lib.boolToString (stableVm.pkgs ? hyprland-preview-share-picker);

    inherit quickshellVersion;

    # The version below which 0.3.0's lockscreen bug is present. Named so the
    # failure message can quote it rather than restate it.
    quickshellFloor = "0.3.1";

    # Decided in Nix, not in shell: a shell string comparison orders 0.3.10
    # before 0.3.9, and this is the assertion that is load-bearing for whether
    # somebody can get back into their laptop.
    quickshellOk = lib.boolToString (lib.versionAtLeast quickshellVersion "0.3.1");
  }
  ''
    echo "nixpkgs-stable: $release @ $stableRev"
    echo "the system evaluates: $toplevel"

    # A floor, in the shape this repository keeps arriving at: a check whose
    # inputs came back empty satisfies every comparison below while proving
    # nothing. tests/reference-initrd.nix refuses for the same reason.
    case "$toplevel" in
      /nix/store/*-nixos-system-*.drv) ;;
      *)
        echo "::error::the stable toplevel is not a system derivation path:" >&2
        echo "  '$toplevel'" >&2
        echo "  This check cannot answer anything and is refusing rather" >&2
        echo "  than passing." >&2
        exit 1
        ;;
    esac

    if [ "$release" != "${cfg.system.nixos.release}" ]; then
      echo "::error::the evaluated release ($release) is not the one the" >&2
      echo "  system reports (${cfg.system.nixos.release})." >&2
      exit 1
    fi

    echo "the share picker is present on this nixpkgs: $pickerPresent"

    echo "the session's quickshell: $quickshellVersion (floor $quickshellFloor)"
    if [ "$quickshellOk" != "true" ]; then
      echo "::error::this stable machine would run quickshell" >&2
      echo "  $quickshellVersion, below the $quickshellFloor floor." >&2
      echo >&2
      echo "  quickshell 0.3.0's session lock reaches qFatal when screens" >&2
      echo "  sleep and wake while locked, and the Wayland protocol keeps the" >&2
      echo "  compositor locked when its lock client dies -- so the machine" >&2
      echo "  is left blank with nowhere to type a password (#35, #528)." >&2
      echo >&2
      echo "  The floor is on the quickshell argument to pkgs/omarchy in" >&2
      echo "  flake.nix. If it was removed as a no-op, this is why it was" >&2
      echo "  not one." >&2
      exit 1
    fi

    echo
    echo "PROVEN: nixarchy evaluates against nixpkgs $release."
    echo "NOT PROVEN: that it boots, or that the desktop comes up. Nothing"
    echo "here starts a VM. A green tick on this check is not 'stable works'."
    touch $out
  ''
