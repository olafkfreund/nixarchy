{ pkgs, ... }:
# pkgs/cargo-system-libs.nix against stand-in nixpkgs sets (#1722).
#
# The carry appends libraries only when nixpkgs' cargo hook links system
# libraries AND the package lacks one. Each guard is a case, so a break that
# drops a guard fails the case that names it. Evaluation only: the stand-ins
# are never built, and the assertions are forced through `ok` below.
let
  inherit (pkgs) lib;
  carry = import ../pkgs/cargo-system-libs.nix;

  stand =
    pname: version: buildInputs:
    pkgs.stdenvNoCC.mkDerivation {
      inherit pname version buildInputs;
      dontUnpack = true;
      installPhase = "touch $out";
    };

  libs = lib.genAttrs [ "aws-lc" "oniguruma" "sqlite" "zstd" ] (n: stand n "1" [ ]);
  allLibs = lib.attrValues libs;

  # Every case holds both packages and all four libraries; F alone drops omp.
  mkPrev =
    {
      hook,
      codex ? [ ],
      omp ? [ ],
      withOmp ? true,
    }:
    libs
    // {
      path = hook;
      codex = stand "codex" "0" codex;
    }
    // lib.optionalAttrs withOmp { omp = stand "omp" "0" omp; };

  run =
    args:
    let
      prev = mkPrev args;
    in
    {
      inherit prev;
      inherit (carry { inherit lib prev; }) packages status;
    };

  # Sorted, duplicates kept: a second zstd must be visible.
  pnames = p: lib.sort lib.lessThan (map (d: d.pname) p.buildInputs);
  same = r: n: r.packages.${n}.drvPath == r.prev.${n}.drvPath;

  withHook = ./cargo-system-libs/with-hook;
  withoutHook = ./cargo-system-libs/without-hook;
  noHook = ./cargo-system-libs/no-hook;

  a = run { hook = withHook; };
  b = run {
    hook = withHook;
    codex = allLibs;
  };
  c = run { hook = withoutHook; };
  d = run { hook = noHook; };
  e = run {
    hook = withHook;
    # A different zstd derivation with the same pname: matching is by pname.
    omp = [ (stand "zstd" "2" [ ]) ];
  };
  f = run {
    hook = withHook;
    withOmp = false;
  };

  results = [
    (lib.assertMsg
      (
        pnames a.packages.codex == [
          "aws-lc"
          "oniguruma"
          "sqlite"
          "zstd"
        ]
      )
      "case A: codex must gain exactly aws-lc oniguruma sqlite zstd, got ${toString (pnames a.packages.codex)}"
    )
    (lib.assertMsg (a.status.codex == "needed") "case A: status.codex must be needed")
    (lib.assertMsg (same b "codex") "case B: a codex with every library must be prev.codex")
    (lib.assertMsg (b.status.codex == "dead") "case B: status.codex must be dead")
    (lib.assertMsg (same c "codex") "case C: without the hook codex must be prev.codex")
    (lib.assertMsg (c.status.codex == "inactive") "case C: status.codex must be inactive")
    (lib.assertMsg (same d "codex") "case D: with no hook file codex must be prev.codex")
    (lib.assertMsg (d.status.codex == "inactive") "case D: status.codex must be inactive")
    (lib.assertMsg (
      pnames e.packages.omp == [
        "oniguruma"
        "zstd"
      ]
    ) "case E: omp must gain only oniguruma, got ${toString (pnames e.packages.omp)}")
    (lib.assertMsg (e.status.omp == "needed") "case E: status.omp must be needed")
    (lib.assertMsg (
      !(f.packages ? omp) && !(f.status ? omp)
    ) "case F: no omp in prev, none in the carry")
  ];
in
pkgs.runCommand "nixarchy-cargo-system-libs"
  {
    ok = builtins.deepSeq results "yes";
  }
  ''
    touch $out
  ''
