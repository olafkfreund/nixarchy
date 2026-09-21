# Reads the catalogue structurally, without the one step
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
#
# What it no longer proves: `nixarchy box` is retired (#801), and the
# /nix/store-path assertion over its built script went with it. The panel
# that replaced it has no generated script to grep. See the body for why
# that has no equivalent here, and tests/AGENTS.md for the gap it leaves.
{
  pkgs,
  lib,
  templates,
  # name -> { imageName, imageDigest, sha256 } -- see the header. A template
  # with no entry here fails loudly (missingPins below) rather than being
  # silently skipped, so #259 adding `debian` cannot forget this half.
  imagePins,
  images,
  # packages.box-test-image: the one cache-allowlist entry that has to carry
  # every pinned image, byte for byte the ones checked here (#800).
  cached,
}:
let
  names = builtins.attrNames templates;
  missingPins = lib.subtractLists (builtins.attrNames imagePins) names;
  uncached = builtins.filter (
    n: !(cached.images ? ${n}) || cached.images.${n}.outPath != images.${n}.outPath
  ) (builtins.attrNames images);
in
assert
  missingPins == [ ] || throw "checks.box-template: no imagePins entry for: ${toString missingPins}";
assert
  uncached == [ ]
  || throw "checks.box-template: box-test-image does not carry the pinned image for: ${toString uncached}";
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
      if ! <<<"$ini" grep -qE '^image=.+'; then
        echo "${name}: ini has no non-empty 'image=' line" >&2
        fail=1
      fi

      # The pin taken for this template is a real image name -- a
      # structural cross-check that the pin was not taken against the wrong
      # template.
      if ! <<<"$ini" grep -q ${lib.escapeShellArg imagePins.${name}.imageName}; then
        echo "${name}: ini does not mention pinned image '${imagePins.${name}.imageName}'" >&2
        fail=1
      fi

      # The pinned image is a fixed-output derivation that actually landed
      # in the store -- non-empty tarball, no container ever started.
      size=$(stat -c%s ${images.${name}} 2>/dev/null || echo 0)
      if [ "$size" -le 0 ]; then
        echo "${name}: pulled image ${images.${name}} is empty or missing" >&2
        fail=1
      fi
    '') names}

    # What this check no longer makes, and why there is no replacement.
    #
    # `nixarchy box` was a writeShellApplication, so a stray
    # `runtimeInputs = [ pkgs.distrobox ]` would have baked a literal
    # /nix/store/*-distrobox-*/bin path into the generated script, and one
    # grep over that script caught it. The Distrobox panel that replaces it
    # is QML, pinned by rev, and resolves `distrobox` through PATH by
    # construction -- there is no generated script here to grep, so this
    # assertion has no panel equivalent rather than a moved one.
    #
    # The property itself still matters and is still covered, one layer up:
    # modules/services/boxes.nix's header states it (nixpkgs#478154) and
    # checks.box-boot observes it on a real container's recorded
    # distrobox-init mount, which is the stronger of the two measurements.
    # What is lost is the cheap static half that ran on every pull request.
    # tests/AGENTS.md names that gap.

    [ "$fail" -eq 0 ] || exit 1
    echo "every catalogue template names a real, pinned image."
    touch $out
  ''
