{ pkgs, ... }:
let
  shipped = pkgs.nixarchy-omarchy or pkgs.omarchy;
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
    ln -s "$TMPDIR/loop-b" "$TMPDIR/loop-a"
    ln -s "$TMPDIR/loop-a" "$TMPDIR/loop-b"

    store_owned "$TMPDIR/store-file" || fail store-file-link
    store_owned "$TMPDIR/store-dir" || fail store-directory-link
    store_owned "$TMPDIR/store-dir/a/b/c.json" || fail missing-under-store-directory-link
    if store_owned "$TMPDIR/plain/file"; then fail regular-file; fi
    if store_owned "$TMPDIR/plain/missing.json"; then fail missing-under-regular-directory; fi
    store_owned "$TMPDIR/dangling-store" || fail dangling-store-link
    store_owned "$TMPDIR/loop-a" || fail link-loop
    if store_owned ""; then fail empty-path; fi

    [ "$failures" -eq 0 ] || exit 1
    touch "$out"
  ''
