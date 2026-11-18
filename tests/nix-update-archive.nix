{ pkgs }:
# Proves every nix-update updater uses checkmate's binary and that it bumps an archived flake offline.
# It cannot test network version discovery.
# It cannot test subdirectory flakes.
let
  inherit (pkgs) lib;
  manifest = lib.concatStringsSep "\n" (
    lib.mapAttrsToList (name: p: "${name} ${lib.getExe p.updateScript}") (
      lib.filterAttrs (_: p: p ? updateScript) pkgs.nixarchy-apps
    )
  );
in
pkgs.runCommand "nixarchy-nix-update-archive"
  {
    nativeBuildInputs = [
      pkgs.git
      pkgs.nix
    ];
    inherit manifest;
  }
  ''
    set -euo pipefail

    declare -A paths
    while read -r member script; do
      if ! grep -Eq '^[[:space:]]*nix-update([[:space:]]|$)' "$script"; then
        case "$member" in
          once|hey-cli) continue ;;
          *) echo "$member does not run nix-update" >&2; exit 1 ;;
        esac
      fi

      path_line=$(grep '^export PATH="' "$script") || {
        echo "$member has no exported PATH" >&2; exit 1;
      }
      IFS=: read -ra entries <<< "''${path_line#export PATH=\"}"
      matches=()
      for entry in "''${entries[@]}"; do
        if [[ $entry == /nix/store/*-nix-update-*/bin ]]; then
          matches+=("$entry")
        fi
      done
      if [ "''${#matches[@]}" -ne 1 ]; then
        echo "$member has ''${#matches[@]} nix-update PATH entries; expected exactly one" >&2
        exit 1
      fi
      paths[$member]="''${matches[0]}"
    done <<< "$manifest"

    ref="''${paths[checkmate]:?checkmate has no nix-update PATH entry}"
    for member in "''${!paths[@]}"; do
      if [ "''${paths[$member]}" != "$ref" ]; then
        echo "$member uses ''${paths[$member]}; reference checkmate uses $ref" >&2
        exit 1
      fi
    done

    export HOME=$TMPDIR/home XDG_CACHE_HOME=$TMPDIR/cache
    export NIX_REMOTE="local?root=$TMPDIR/root"
    export NIX_CONFIG=$(printf '%s\n' \
      'experimental-features = nix-command flakes' \
      'sandbox = false' \
      'substituters =')
    mkdir -p "$HOME" "$XDG_CACHE_HOME" "$TMPDIR/root" "$TMPDIR/fixture"
    cd "$TMPDIR/fixture"
    printf '%s\n' \
      '{ outputs = _: { packages.x86_64-linux.demo = let' \
      '  version = "1.0";' \
      '  src = derivation { name = "demo-src-''${version}"; system = "x86_64-linux"; builder = "/bin/sh";' \
      '    args = [ "-c" "echo ''${version} > $out" ]; outputHashMode = "flat"; outputHashAlgo = "sha256";' \
      '    outputHash = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA="; };' \
      '  in { inherit version src; name = "demo-''${version}"; type = "derivation"; }; }; }' \
      > flake.nix
    git init -q
    git add flake.nix
    git -c user.name=Test -c user.email=test@example.invalid commit -qm fixture

    nix flake archive >/dev/null
    "$ref/nix-update" --flake demo --version 2.0
    grep -Fq '"2.0"' flake.nix || { echo 'version did not update to 2.0' >&2; exit 1; }
    if grep -Fq 'sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=' flake.nix; then
      echo 'placeholder hash did not change' >&2
      exit 1
    fi
    touch "$out"
  ''
