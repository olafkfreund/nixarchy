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
    # Sites and offences are printed, not counted, so a find that xargs
    # splits across several awk runs still adds up.
    find tests modules pkgs installer .github flake.nix -type f \
      \( -name '*.nix' -o -name '*.sh' \) -print0 \
      | xargs -0 awk '
          FNR == 1 { pending = 0 }
          pending && /^[ \t]/ { print "bad " FILENAME ":" FNR - 1 }
          { pending = 0 }
          /(python3?|interpreter\})( +-[A-Za-z]+)* +-c +[\x27"] *$/ { pending = 1; print "site" }
        ' >"$TMPDIR/scan"
    sites=$(grep -c '^site$' "$TMPDIR/scan" || true)
    bad=$(grep '^bad ' "$TMPDIR/scan" || true)
    echo "$sites multi-line python -c site(s)"
    # Zero sites means the pattern stopped matching, not a clean tree.
    if [ "$sites" -lt 1 ]; then
      echo "no python -c site found at all; the pattern no longer matches this tree" >&2
      exit 1
    fi
    if [ -n "$bad" ]; then
      echo "indented python -c code; Python 3.13 refuses it (#1205). Move it to a file:" >&2
      echo "$bad" >&2
      exit 1
    fi
    touch $out
  ''
