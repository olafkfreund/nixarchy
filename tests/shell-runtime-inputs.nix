{
  inputs,
  pkgs,
  doctor,
}:
let
  testLib = import ./lib.nix { inherit inputs; };
  apply = testLib.vmPackage "nixarchy-apply";
in
pkgs.runCommand "nixarchy-shell-runtime-inputs" { } ''
  require_path() {
    while IFS= read -r line; do
      if [[ $line == 'export PATH='* && $line == *"$2/bin"* ]]; then
        return 0
      fi
    done < "$1"
    echo "missing $3 from $4 wrapper PATH" >&2
    exit 1
  }

  require_path "${doctor}/bin/nixarchy-doctor" "${pkgs.xdg-utils}" xdg-utils doctor
  require_path "${apply}/bin/nixarchy-apply" "${pkgs.git}" git apply
  require_path "${apply}/bin/nixarchy-apply" "${pkgs.gnused}" gnused apply
  echo "shell runtime inputs: doctor xdg-utils and apply git, gnused present"
  touch "$out"
''
