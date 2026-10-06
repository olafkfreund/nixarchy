{ pkgs, ... }:
# #1205: an indented `python3 -c` program builds on unstable and not on
# stable. Python 3.14 dedents -c code before running it; 3.13 (nixos-26.05)
# refuses it with "unexpected indent". Inside an indented Nix string the
# code is indented by construction, so the omarchy package built everywhere
# this repo tests and failed on every stable machine.
#
# Fails on a `python -c '` / `python3 -c '` that ends its line and whose
# first line of code is indented. Put the program in a file instead.
let
  inherit (pkgs) lib;
  src = lib.fileset.toSource {
    root = ../.;
    fileset = lib.fileset.unions [
      ../tests
      ../modules
      ../pkgs
      ../installer
      ../.github
      ../flake.nix
    ];
  };
in
pkgs.runCommand "nixarchy-inline-python"
  {
    nativeBuildInputs = [
      pkgs.findutils
      pkgs.gawk
    ];
  }
  ''
    cd ${src}
    find tests modules pkgs installer .github flake.nix -type f \
      \( -name '*.nix' -o -name '*.sh' \) -print0 \
      | xargs -0 awk '
          FNR == 1 { pending = 0 }
          pending && /^[ \t]/ { print FILENAME ":" FNR - 1; bad++ }
          { pending = 0 }
          /python3?( +-[A-Za-z]+)* +-c +\x27$/ { pending = 1; seen++ }
          END {
            printf "%d multi-line python -c site(s), %d indented\n", seen, bad > "/dev/stderr"
            exit (bad > 0)
          }
        ' >"$TMPDIR/bad" || {
      echo "indented python -c code; Python 3.13 refuses it (#1205). Move it to a file:" >&2
      cat "$TMPDIR/bad" >&2
      exit 1
    }
    touch $out
  ''
