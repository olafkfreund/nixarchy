{ pkgs }:
# Upstream's /etc overlay, held to data/etc-overlay.nix in both directions.
#
# The tree is carried into $out/share/omarchy/etc and, apart from the rows the
# manifest classes `installed` (which modules/nixos.nix reads and declares
# through environment.etc), nothing installs it. The manifest says which files
# are ignored because something else answers them and which are ignored because
# nobody has decided yet; this makes upstream's next change force that decision
# rather than arrive silently:
#
#   a file shipped with no row       unclassified -- decide, then add a row
#   a row for a file no longer there stale -- the file went, the row must too
#
# Compared against the SHIPPED tree rather than inputs.omarchy, so the same
# diff also proves the `cp -r .` in pkgs/omarchy/default.nix still carries
# etc/ at all. It cannot be satisfied by editing the manifest alone, which is
# the whole point -- data/bin-ledger.nix makes the same argument about
# classification, and this one is about the inventory.
#
# The floor is the other half. `find` over a path that moved, or a tree that
# stopped being copied, enumerates nothing -- and every assertion over an empty
# list passes. A count below the floor is therefore a failure and not a clean
# run; `find -L` for the same reason, since $shipped may be a result symlink.
let
  inherit (pkgs) lib;

  manifest = import ../data/etc-overlay.nix;

  classes = [
    "covered"
    "divergent"
    "installed"
    "na"
    "native"
    "seed"
  ];

  # Checked at evaluation rather than in the script: a row with a class the
  # manifest's own header does not define, or a one-line "not applicable"
  # reason, is the rubber stamp this file exists to prevent.
  malformed = lib.attrNames (
    lib.filterAttrs (
      _: row: !(builtins.elem row.class classes) || builtins.stringLength row.reason < 80
    ) manifest
  );
in
if malformed != [ ] then
  throw ''
    data/etc-overlay.nix: rows with an unknown class, or a reason under 80
    characters, which is too short to be checkable after a release:

      ${lib.concatStringsSep "\n      " malformed}

    Classes: ${lib.concatStringsSep ", " classes}
  ''
else
  pkgs.runCommand "nixarchy-etc-overlay"
    {
      shipped = pkgs.nixarchy-omarchy or pkgs.omarchy;
      claimed = lib.concatStringsSep "\n" (lib.attrNames manifest);
      passAsFile = [ "claimed" ];

      # Upstream ships 40. A floor rather than the exact count, so adding a
      # classified file is a manifest edit and not two.
      floor = 30;
    }
    ''
      set -o pipefail

      # Named once, so the floor's message reports the directory that was
      # actually walked rather than the one it was meant to be.
      overlay="$shipped/share/omarchy/etc"

      find -L "$overlay" -type f -printf '%P\n' | sort >shipped.list
      sort <"$claimedPath" >claimed.list

      found=$(wc -l <shipped.list)
      if [ "$found" -lt "$floor" ]; then
        echo "etc-overlay: found only $found files under" >&2
        echo "  $overlay" >&2
        echo "which is below the floor of $floor. Either upstream's overlay has" >&2
        echo "shrunk that far -- reclassify it -- or the tree is no longer being" >&2
        echo "copied and this check was about to pass by enumerating nothing." >&2
        exit 1
      fi

      if ! diff -u claimed.list shipped.list; then
        echo >&2
        echo "etc-overlay: data/etc-overlay.nix does not match the shipped tree." >&2
        echo "In that diff, reading against the manifest:" >&2
        echo >&2
        echo "  +path  upstream ships it and no row classifies it. Read the file," >&2
        echo "         decide what answers it here, and add a row with a reason." >&2
        echo "  -path  the row claims a file upstream no longer ships. Delete it;" >&2
        echo "         a stale row is a claim about nothing." >&2
        exit 1
      fi

      echo "etc-overlay: all $found files classified, none stale"
      touch "$out"
    ''
