{ pkgs, ... }:
# The package delta that goes in every Omarchy bump PR.
#
# Omarchy pins no versions, so the only thing to compare between releases is
# the SET of packages it installs -- and a set diff has exactly one dangerous
# failure: reporting nothing. "No change to the package set" is what a reader
# sees both when upstream changed nothing and when the script stopped being
# able to read the lists, and those two mean opposite things.
#
# So this feeds it fixtures with a known answer. Files, not tags, because a
# check has no network -- the workflow does the fetching.
let
  # Shaped like upstream's: comments, blank lines, one package per line.
  old = builtins.toFile "old.packages" ''
    # Omarchy base
    base
    bat

    cups
    cups-browsed
    cups-pdf
    hyprland
  '';

  new = builtins.toFile "new.packages" ''
    # Omarchy base
    base
    bat

    cups
    cups-pk-helper
    hyprland
  '';

  # Same content, different order and spacing: a set comparison must not care.
  reordered = builtins.toFile "reordered.packages" ''
    hyprland
    bat

    # a comment that moved
    cups-browsed
    base
    cups
    cups-pdf
  '';
in
pkgs.runCommand "nixarchy-package-delta"
  {
    nativeBuildInputs = with pkgs; [
      bash
      coreutils
      gnugrep
      gnused
    ];
  }
  ''
    delta=${../.github/scripts/omarchy-package-delta.sh}
    fail=0

    report=$(bash "$delta" ${old} ${new} v4.0.1 v4.0.2)

    # The real 4.0.1 -> 4.0.2 change, which is what this fixture models.
    echo "$report" | grep -q 'cups-pk-helper' || {
      echo "delta: an added package is missing from the report" >&2
      fail=1
    }
    for gone in cups-browsed cups-pdf; do
      echo "$report" | grep -q "$gone" || {
        echo "delta: removed package $gone is missing from the report" >&2
        fail=1
      }
    done

    # Added and removed must not be confused for each other -- the whole point
    # of reading a removal twice is knowing it was one.
    added_block=$(echo "$report" | sed -n '/\*\*Added\*\*/,/\*\*Removed\*\*/p')
    echo "$added_block" | grep -q 'cups-pk-helper' || {
      echo "delta: cups-pk-helper is not under Added" >&2
      fail=1
    }
    echo "$added_block" | grep -q 'cups-browsed' && {
      echo "delta: a removed package is listed under Added" >&2
      fail=1
    }

    # A package present in both must appear in neither list.
    for unchanged in base bat cups hyprland; do
      echo "$report" | grep -qE "^- \`$unchanged\`$" && {
        echo "delta: unchanged package $unchanged was reported as a change" >&2
        fail=1
      }
    done

    # Silence has to mean silence. Order and blank lines are not changes, and
    # this is the case that would otherwise let a broken read look like calm.
    quiet=$(bash "$delta" ${old} ${reordered} v1 v2)
    echo "$quiet" | grep -q 'No change to the package set' || {
      echo "delta: reordering the same packages was reported as a change" >&2
      echo "$quiet" >&2
      fail=1
    }

    [ "$fail" -eq 0 ] || {
      echo >&2
      echo "What the delta actually printed:" >&2
      echo "$report" >&2
      exit 1
    }

    echo "the package delta names what moved, in the right direction,"
    echo "and stays quiet when nothing did"
    touch $out
  ''
