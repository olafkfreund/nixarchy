{
  inputs,
  pkgs,
  doctor,
}:
let
  testLib = import ./lib.nix { inherit inputs; };
  apply = testLib.vmPackage "nixarchy-apply";
in
pkgs.runCommand "nixarchy-shell-runtime-inputs" { nativeBuildInputs = [ pkgs.gnugrep ]; } ''
  require_path() {
    if ! grep -Fq "$2/bin" "$1"; then
      echo "missing $3 from $4 wrapper PATH" >&2
      exit 1
    fi
  }

  require_path "${doctor}/bin/nixarchy-doctor" "${pkgs.xdg-utils}" xdg-utils doctor
  require_path "${apply}/bin/nixarchy-apply" "${pkgs.git}" git apply
  require_path "${apply}/bin/nixarchy-apply" "${pkgs.gnused}" gnused apply
  echo "shell runtime inputs: doctor xdg-utils and apply git, gnused present"
  touch "$out"
''
