{ inputs, pkgs, ... }:
let
  inherit (pkgs) lib;
  pkg = inputs.self.nixosConfigurations.reference.config.programs.nixarchy.package;
in
pkgs.runCommand "nixarchy-runtime-path" { } ''
  set +e
  export PATH=${lib.makeBinPath pkg.passthru.runtimeDeps}:${pkgs.coreutils}/bin
  failed=0
  for name in ffplay rsvg-convert; do
    if command -v "$name" >/dev/null 2>&1; then
      echo "PASS: $name is on runtime PATH"
    else
      echo "FAIL: $name is missing from runtime PATH" >&2
      failed=1
    fi
  done
  [ "$failed" -eq 0 ] || exit 1
  touch "$out"
''
