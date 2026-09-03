{ pkgs, ... }:
# The half of `nix run .#review` that can be checked without a network.
#
# review.sh answers "is anything we pin behind upstream", and the way it rots
# is not the comparison -- it is the reading. Someone restructures a
# `version = "x"` line, or renames a file under pkgs/apps, and every probe for
# that package quietly reports nothing at all. A watcher that has stopped
# seeing one of its subjects looks exactly like a watcher with nothing to
# report, which is the failure mode this whole change exists to end.
#
# So this asserts on --list-pins: no network, no gh, no GitHub. Every pin the
# script claims to watch must still be findable, and must still yield a
# version that looks like one.
let
  # The pins review.sh is expected to see. Hardcoded here rather than derived
  # from the script, because a list derived from the thing it checks agrees
  # with it by construction and proves nothing.
  expected = [
    "once"
    "hey-cli"
    "omacalc"
    "omacut"
    "omawrite"
    "ttfx"
  ];
in
pkgs.runCommand "nixarchy-review-pins"
  {
    nativeBuildInputs = with pkgs; [
      bash
      gnused
      coreutils
      # flake-pins.py reads flake.lock; review.sh --list-pins does not need it,
      # but they are checked together.
      python3
    ];
  }
  ''
    # review.sh reads the pin files relative to the repository root, the way
    # it does when someone runs it at a prompt.
    mkdir -p pkgs
    cp -r ${../pkgs/apps} pkgs/apps

    bash ${../pkgs/review.sh} --list-pins > pins.txt || {
      echo "review.sh --list-pins failed outright" >&2
      exit 1
    }

    fail=0

    for name in ${builtins.concatStringsSep " " expected}; do
      line=$(grep -E "^$name	" pins.txt || true)
      if [ -z "$line" ]; then
        echo "review: $name is no longer in the pin list" >&2
        echo "  the script watches it, or it does not -- silence is the bug." >&2
        fail=1
        continue
      fi

      file=$(printf '%s' "$line" | cut -f2)
      version=$(printf '%s' "$line" | cut -f3)

      # A version that does not start with a digit is the shape of a failed
      # read, not of a release: an empty field, or a stray match.
      case "$version" in
        [0-9]*) ;;
        *)
          echo "review: $name ($file) yielded version '$version'" >&2
          echo "  the pin moved or its version line changed shape." >&2
          fail=1
          ;;
      esac
    done

    got=$(wc -l < pins.txt)
    want=${toString (builtins.length expected)}
    if [ "$got" != "$want" ]; then
      echo "review: the pin list has $got entries, expected $want" >&2
      echo "  a pin was added or removed; update tests/review-pins.nix too." >&2
      fail=1
    fi

    if [ "$fail" -ne 0 ]; then
      echo >&2
      echo "What review.sh --list-pins actually printed:" >&2
      cat pins.txt >&2
      exit 1
    fi

    # And the flake's own pins, read out of flake.lock by the same script the
    # review uses. Its silent failure is identical in shape: a lock format it
    # no longer parses yields no rows, and no rows reads as nothing to report.
    cp ${../flake.lock} flake.lock
    python3 ${../pkgs/flake-pins.py} > pins-flake.txt || {
      echo "flake-pins.py could not read flake.lock" >&2
      exit 1
    }

    # One of each shape, because the review asks a different question of each
    # and a classifier that has collapsed to one answer is the bug.
    for want_line in "omarchy	tag" "hyprland	rev" "nixpkgs	ref"; do
      name=''${want_line%%	*}
      kind=''${want_line##*	}
      got=$(grep -E "^$name	" pins-flake.txt | cut -f2)
      [ "$got" = "$kind" ] || {
        echo "review: flake.lock pins $name as '$got', expected '$kind'" >&2
        echo "  the review asks a different question of each shape." >&2
        cat pins-flake.txt >&2
        exit 1
      }
    done

    echo "all $want pins are readable, and every version looks like one"
    echo "and flake.lock still classifies tag, rev and ref pins apart"
    touch $out
  ''
