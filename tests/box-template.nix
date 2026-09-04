# Reads the catalogue and `nixarchy box` structurally, without the one step
# that can fail offline: the first-start package-manager update inside a
# freshly created box (`pacman -Syy` / `apt-get update`). That is
# `checks.box-boot`'s job, deliberately left to a later, CI-gate issue
# (#262) -- the same split #224/#228 used for microvm.
#
# What this proves, from nixpkgs source the way tests/microvm-template.nix
# and tests/plugin.nix already do for their own features:
#
#   * `dockerTools.pullImage` is fixed-output, so pinning `imageDigest` and
#     `sha256` gets a real base image into the store at build time with no
#     network needed to trust the result -- Nix permits the fetch (over the
#     real network) for a fixed-output derivation specifically because the
#     hash, not the sandbox, is what makes it reproducible. `imagePins`
#     below is exactly that pin, one entry per catalogue template that has
#     shipped so far -- verified once, by hand, against
#     registry-1.docker.io, the same way a `sha256` for `fetchurl` is.
#   * each template's raw `ini` names the same image the pin was taken
#     against -- a structural cross-check, not a build of the container.
#   * `nixarchy box`'s built script never resolves `distrobox` through a
#     literal /nix/store path, and never lists it in a derivation that would
#     put one on PATH -- grepping the built script is the cheapest form of
#     the assertion pkgs/box.nix's header makes in prose.
{
  pkgs,
  lib,
  templates,
  nixarchyBox,
  # name -> { imageName, imageDigest, sha256 } -- see the header. A template
  # with no entry here fails loudly (missingPins below) rather than being
  # silently skipped, so #259 adding `debian` cannot forget this half.
  imagePins,
}:
let
  names = builtins.attrNames templates;
  missingPins = lib.subtractLists (builtins.attrNames imagePins) names;

  pulledImages = lib.mapAttrs (
    _: pin:
    pkgs.dockerTools.pullImage {
      inherit (pin) imageName imageDigest;
      finalImageTag = pin.tag or "latest";
      inherit (pin) sha256;
    }
  ) imagePins;
in
assert
  missingPins == [ ] || throw "checks.box-template: no imagePins entry for: ${toString missingPins}";
pkgs.runCommand "nixarchy-box-template"
  {
    nativeBuildInputs = [ pkgs.gnugrep ];
  }
  ''
    fail=0

    ${lib.concatMapStrings (name: ''
      echo "== template: ${name} =="
      ini=${lib.escapeShellArg templates.${name}.ini}

      # The catalogue INI names an image. Breaking this looks like dropping
      # the `image =` line from a template.
      if ! echo "$ini" | grep -qE '^image=.+'; then
        echo "${name}: ini has no non-empty 'image=' line" >&2
        fail=1
      fi

      # The pin taken for this template is a real image name -- a
      # structural cross-check that the pin was not taken against the wrong
      # template.
      if ! echo "$ini" | grep -q ${lib.escapeShellArg imagePins.${name}.imageName}; then
        echo "${name}: ini does not mention pinned image '${imagePins.${name}.imageName}'" >&2
        fail=1
      fi

      # The pinned image is a fixed-output derivation that actually landed
      # in the store -- non-empty tarball, no container ever started.
      size=$(stat -c%s ${pulledImages.${name}} 2>/dev/null || echo 0)
      if [ "$size" -le 0 ]; then
        echo "${name}: pulled image ${pulledImages.${name}} is empty or missing" >&2
        fail=1
      fi
    '') names}

    echo "== nixarchy box: no /nix/store distrobox path =="

    # Breaking this looks like adding `runtimeInputs = [ pkgs.distrobox ]`
    # back to pkgs/box.nix, or calling it via `''${pkgs.distrobox}/bin/...`.
    # Either would put a literal /nix/store/*-distrobox-*/bin path into the
    # built script, either on the PATH= line writeShellApplication generates
    # or directly in the text -- one grep catches both.
    if grep -oE '/nix/store/[^ "]*-distrobox-[^ "/]*' ${nixarchyBox}/bin/nixarchy-box; then
      echo "nixarchy-box resolves distrobox through a /nix/store path -- see pkgs/box.nix's header" >&2
      fail=1
    else
      echo "nixarchy-box calls distrobox only by bare name"
    fi

    [ "$fail" -eq 0 ] || exit 1
    echo "every catalogue template names a real, pinned image, and" \
         "nixarchy box never bakes a /nix/store path to distrobox."
    touch $out
  ''
