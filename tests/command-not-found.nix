{ inputs, pkgs }:
let
  handler = (import ./lib.nix { inherit inputs; }).vmPackage "nixarchy-command-not-found";
in
pkgs.runCommand "nixarchy-command-not-found"
  {
    nativeBuildInputs = [
      pkgs.coreutils
      pkgs.gnugrep
      pkgs.gnused
    ];
  }
  ''
    cnf=${handler}/bin/nixarchy-command-not-found
    fail() { echo "FAIL: $1" >&2; exit 1; }

    rc=0
    output=$($cnf rg 2>&1) || rc=$?
    [ "$rc" -eq 127 ] || fail "lookup returned $rc instead of 127"
    grep -qF -- 'In nixpkgs it comes from:' <<<"$output" || fail "real nix-locate found no provider: $output"
    grep -qF -- 'Run it once:' <<<"$output" || fail "provider advice missing: $output"

    rc=0
    output=$($cnf nixarchy-1618-no-such-command 2>&1) || rc=$?
    [ "$rc" -eq 127 ] || fail "empty lookup returned $rc instead of 127"
    grep -qF -- 'nothing in nixpkgs provides' <<<"$output" || fail "empty result misreported: $output"

    # Shadow only nix-locate, using the real pkgs.nix-index binary with no database.
    mkdir -p raw-bin
    ln -s ${pkgs.nix-index}/bin/nix-locate raw-bin/nix-locate
    sed "s#^export PATH=\"#export PATH=\"$PWD/raw-bin:#" "$cnf" > no-db-handler
    chmod +x no-db-handler
    grep -q "^export PATH=\"$PWD/raw-bin:" no-db-handler || fail 'handler PATH could not be changed'
    rc=0
    output=$(NIX_INDEX_DATABASE="$PWD/no-db" ./no-db-handler rg 2>&1) || rc=$?
    [ "$rc" -eq 127 ] || fail "missing database returned $rc instead of 127"
    grep -qF -- 'nix-locate failed' <<<"$output" || fail "missing database hidden: $output"
    if grep -qF -- 'nothing in nixpkgs provides' <<<"$output"; then
      fail "missing database reported as an empty result: $output"
    fi

    touch "$out"
  ''
