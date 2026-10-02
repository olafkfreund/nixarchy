{ pkgs, reference }:
# #1163: a second, different Mesa in hardware.graphics.extraPackages(32)
# collides with nixarchy's own Mesa in buildEnv (both ship
# share/glvnd/egl_vendor.d/*mesa.json). The assertions in modules/nixos.nix
# catch this at evaluation; this check proves they fire exactly when they
# should, against seven fixtures built from the reference machine.
#
# Never built: fakeMesa/fakeMesa32 are runCommand derivations whose pname and
# outPath are all the assertion reads. Building merged graphics-drivers
# environments in general is #1164's job, not this one's.
let
  inherit (pkgs) lib;

  fakeMesa =
    pkgs.runCommand "mesa-fake"
      {
        pname = "mesa";
        version = "0-fake";
      }
      ''
        mkdir -p $out/share/glvnd/egl_vendor.d
        echo '{}' > $out/share/glvnd/egl_vendor.d/50_mesa.json
      '';
  fakeMesa32 =
    pkgs.runCommand "mesa-fake-32"
      {
        pname = "mesa";
        version = "0-fake";
      }
      ''
        mkdir -p $out/share/glvnd/egl_vendor.d
        echo '{}' > $out/share/glvnd/egl_vendor.d/50_mesa.json
      '';

  oursMesa = reference.config.hardware.graphics.package;

  extend = modules: (reference.extendModules { modules = [ modules ]; }).config.assertions;

  has1163Failure =
    assertions: lib.filter (a: !a.assertion && lib.hasInfix "#1163" a.message) assertions;

  fixtures = {
    A = {
      assertions = extend { hardware.graphics.extraPackages = [ fakeMesa ]; };
      expectFail = true;
      mustContain = [
        "extraPackages"
        "hardware.graphics.package"
      ];
    };
    B = {
      assertions = extend {
        hardware.graphics.enable32Bit = true;
        hardware.graphics.extraPackages32 = [ fakeMesa32 ];
      };
      expectFail = true;
      mustContain = [
        "extraPackages32"
        "hardware.graphics.package32"
      ];
    };
    C = {
      assertions = extend { hardware.graphics.extraPackages = [ oursMesa ]; };
      expectFail = false;
      mustContain = [ ];
    };
    # The user's own package, and a *different* Mesa beside it: theirs to
    # reconcile, so no #1163 error. Fails if the "still nixarchy's" gate goes.
    D = {
      assertions = extend {
        hardware.graphics.package = fakeMesa;
        hardware.graphics.extraPackages = [ fakeMesa32 ];
      };
      expectFail = false;
      mustContain = [ ];
    };
    # Rusticl: mesa.opencl shares pname "mesa" but ships no egl_vendor.d file,
    # so it collides with nothing (review of #1165).
    F = {
      assertions = extend { hardware.graphics.extraPackages = [ oursMesa.opencl ]; };
      expectFail = false;
      mustContain = [ ];
    };
    # A leftover extraPackages32 with 32-bit off is never merged.
    G = {
      assertions = extend {
        hardware.graphics.enable32Bit = false;
        hardware.graphics.extraPackages32 = [ fakeMesa32 ];
      };
      expectFail = false;
      mustContain = [ ];
    };
    E = {
      assertions = extend { };
      expectFail = false;
      mustContain = [ ];
    };
  };

  verdictOf =
    name: f:
    let
      failing = has1163Failure f.assertions;
      got = failing != [ ];
      textOk = !got || lib.all (needle: lib.any (a: lib.hasInfix needle a.message) failing) f.mustContain;
      ok = got == f.expectFail && textOk;
    in
    {
      inherit name ok;
      line = "${name}: expected ${if f.expectFail then "fail" else "none"}, got ${
        if got then "fail" else "none"
      }${if textOk then "" else " (message missing expected text)"}";
    };

  verdicts = lib.mapAttrsToList verdictOf fixtures;
  failed = lib.filter (v: !v.ok) verdicts;
in
pkgs.runCommand "nixarchy-graphics-mesa-clash" { } ''
  ${lib.concatMapStringsSep "\n" (v: "echo ${lib.escapeShellArg v.line}") verdicts}

  ${
    if failed == [ ] then
      ''
        echo "all fixtures match the #1163 assertion as expected"
        touch $out
      ''
    else
      ''
        echo ${lib.escapeShellArg "FAIL: ${lib.concatMapStringsSep ", " (v: v.name) failed}"} >&2
        exit 1
      ''
  }
''
