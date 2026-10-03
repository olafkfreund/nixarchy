{ pkgs, reference }:
# A user's own config, beside nixarchy's: tests/coexistence/fixtures.nix
# names what a user commonly sets, and this checks nixarchy still produces a
# working machine. AGENTS.md#14 is the rule this check exists to enforce.
#
# Two failure modes, two kinds of assertion (spec: 2026-10-02-1164):
# - graphics: hardware.graphics' merged envs (nixos/modules/hardware/
#   graphics.nix) use buildEnv with no ignoreCollisions -- a clash fails the
#   BUILD, and any nixarchy assertion firing on one of these fixtures is
#   itself a failure here: these are configurations we promise work.
# - systempkg-own-ffmpeg: environment.systemPackages' buildEnv sets
#   ignoreCollisions = true, so a clash resolves silently by meta.priority
#   then order. The user's own ffmpeg-full must win over nixarchy's ffmpeg.
let
  inherit (pkgs) lib;

  fixtures = import ./fixtures.nix;

  configOf = fixture: (reference.extendModules { modules = [ fixture ]; }).config;

  graphicsNames = [
    "graphics-own-mesa"
    "graphics-32bit"
    "graphics-own-package"
    "graphics-opencl"
  ];

  # "/run/opengl-driver"."L+".argument carries toString of the buildEnv
  # derivation with its store-path context intact, so interpolating it below
  # forces that exact derivation to build -- the same one systemd.tmpfiles
  # would link into place on a real machine.
  driverArgOf =
    c: path:
    let
      settings = c.systemd.tmpfiles.settings.graphics-driver;
      entry = settings.${path}."L+" or null;
    in
    if entry == null then null else entry.argument;

  checkGraphics =
    name:
    let
      c = configOf fixtures.${name};
      failing = builtins.filter (a: !a.assertion) c.assertions;
      env = driverArgOf c "/run/opengl-driver";
      env32 = if c.hardware.graphics.enable32Bit then driverArgOf c "/run/opengl-driver-32" else null;
    in
    {
      inherit name env env32;
      failingMessages = map (a: a.message) failing;
    };

  graphicsChecks = map checkGraphics graphicsNames;

  ffmpegCheck =
    let
      c = configOf fixtures.systempkg-own-ffmpeg;
      failing = builtins.filter (a: !a.assertion) c.assertions;
    in
    {
      name = "systempkg-own-ffmpeg";
      path = c.system.path;
      ffmpegFull = pkgs.ffmpeg-full;
      failingMessages = map (a: a.message) failing;
    };

  shQuote = lib.escapeShellArg;

  graphicsScriptOf =
    gc:
    let
      failBody =
        if gc.failingMessages != [ ] then
          ''
            echo ${shQuote "${gc.name}: FAIL nixarchy assertion fired: ${lib.concatStringsSep "; " gc.failingMessages}"} >&2
            fail=1
          ''
        else
          ''
            ok=1
            for env in ${shQuote gc.env} ${if gc.env32 == null then "" else shQuote gc.env32}; do
              if [ -n "$env" ]; then
                if ! ls "$env"/share/glvnd/egl_vendor.d/*mesa*.json >/dev/null 2>&1; then
                  echo ${shQuote "${gc.name}: FAIL no mesa egl_vendor.d json under $env"} >&2
                  ok=0
                fi
              fi
            done
            if [ "$ok" = 1 ]; then
              echo ${shQuote "${gc.name}: ok"}
            else
              fail=1
            fi
          '';
    in
    failBody;

  ffmpegScript =
    if ffmpegCheck.failingMessages != [ ] then
      ''
        echo ${shQuote "systempkg-own-ffmpeg: FAIL nixarchy assertion fired: ${lib.concatStringsSep "; " ffmpegCheck.failingMessages}"} >&2
        fail=1
      ''
    else
      ''
        target=$(readlink -f "${ffmpegCheck.path}/bin/ffmpeg")
        case "$target" in
          ${ffmpegCheck.ffmpegFull}/*|${ffmpegCheck.ffmpegFull})
            echo "systempkg-own-ffmpeg: ok"
            ;;
          *)
            echo "systempkg-own-ffmpeg: FAIL bin/ffmpeg resolved to $target, not the user's ffmpeg-full" >&2
            fail=1
            ;;
        esac
      '';
in
pkgs.runCommand "nixarchy-coexistence"
  {
    # Named so the drivers env derivations and system.path are build inputs,
    # not just strings -- see driverArgOf's comment.
    passthru.fixtures = fixtures;
  }
  ''
    fail=0
    ${lib.concatMapStringsSep "\n" graphicsScriptOf graphicsChecks}
    ${ffmpegScript}
    if [ "$fail" = 1 ]; then
      exit 1
    fi
    touch $out
  ''
