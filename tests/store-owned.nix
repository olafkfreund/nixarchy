{ pkgs, ... }:
let
  shipped = pkgs.nixarchy-omarchy or pkgs.omarchy;
  storeBridge = pkgs.runCommand "store-owned-out-of-store-hop" { } ''
    mkdir -p "$out"
    ln -s /dev/null "$out/file"
  '';
in
pkgs.runCommand "nixarchy-store-owned"
  {
    nativeBuildInputs = [
      pkgs.bash
      pkgs.coreutils
    ];
    helper = "${shipped}/share/omarchy/lib/nixarchy-store-owned.sh";
  }
  ''
    set -euo pipefail
    source "$helper"
    failures=0
    fail() { echo "FAILED $1" >&2; failures=$((failures + 1)); }

    mkdir -p "$TMPDIR/plain"
    printf 'x\n' > "$TMPDIR/plain/file"
    ln -s "$helper" "$TMPDIR/store-file"
    ln -s "${pkgs.coreutils}" "$TMPDIR/store-dir"
    ln -s /nix/store/does-not-exist "$TMPDIR/dangling-store"
    mkdir -p "$TMPDIR/home"
    ln -s ${storeBridge}/file "$TMPDIR/home/x"
    ln -s "$TMPDIR/loop-b" "$TMPDIR/loop-a"
    ln -s "$TMPDIR/loop-a" "$TMPDIR/loop-b"

    store_owned "$TMPDIR/store-file" || fail store-file-link
    store_owned "$TMPDIR/store-dir" || fail store-directory-link
    store_owned "$TMPDIR/store-dir/a/b/c.json" || fail missing-under-store-directory-link
    if store_owned "$TMPDIR/plain/file"; then fail regular-file; fi
    if store_owned "$TMPDIR/plain/missing.json"; then fail missing-under-regular-directory; fi
    store_owned "$TMPDIR/dangling-store" || fail dangling-store-link
    [[ $(readlink -f "$TMPDIR/home/x") == /dev/null ]] || fail out-of-store-fixture
    store_owned "$TMPDIR/home/x" || fail store-hop-to-out-of-store
    store_owned "$TMPDIR/loop-a" || fail link-loop
    if store_owned ""; then fail empty-path; fi

    [ "$failures" -eq 0 ] || exit 1
    touch "$out"
  ''
