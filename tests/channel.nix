{ pkgs, omarchy }:
# nixarchy-channel rewrites a file the user owns, so what it REFUSES to do
# matters more than what it does.
#
# Every case here runs offline. `stable` takes an optional release argument
# precisely so it can, and so somebody can follow 25.11 while 26.05 settles --
# a test seam and a real feature being the same thing is the good case.
#
# The fixture is the real installer template with its placeholders filled, not
# a hand-written flake: the whole risk in this command is sed against a shape,
# and a fixture written to match the sed would prove nothing about the file
# users actually have.
let
  template = builtins.readFile ../installer/template/flake.nix;
  filled =
    builtins.replaceStrings
      [ "@nixpkgs_url@" "@nixarchy_url@" ]
      [ "github:NixOS/nixpkgs/nixos-unstable" "github:olafkfreund/nixarchy/release" ]
      template;
in
pkgs.runCommand "nixarchy-channel"
  {
    nativeBuildInputs = [
      pkgs.gnugrep
      pkgs.gnused
      pkgs.coreutils
    ];
  }
  ''
    export HOME=$PWD/home
    mkdir -p "$HOME"
    ch=${omarchy}/share/omarchy/bin/nixarchy-channel

    mk() { mkdir -p "$1"; cat > "$1/flake.nix" < ${pkgs.writeText "flake.nix" filled}; }

    fails=0
    want() {
      if printf '%s' "$2" | grep -q -- "$3"; then echo "  ok      $1"
      else
        echo "  FAILED  $1: no /$3/ in the output"
        printf '%s\n' "$2" | sed 's/^/          | /'
        fails=$((fails + 1))
      fi
    }
    wantnot() {
      if printf '%s' "$2" | grep -q -- "$3"; then
        echo "  FAILED  $1: /$3/ present and should not be"; fails=$((fails + 1))
      else echo "  ok      $1"; fi
    }

    mk plain
    r=$(NIXARCHY_FLAKE=$PWD/plain $ch 2>&1 || true)
    want "reports the channel"        "$r" 'follows: unstable'
    want "and says it is the tested one" "$r" 'developed and tested against'
    # THE BUG THIS TEST WAS WRITTEN FOR.
    #
    # The template carries a COMMENTED example of inputs.home-manager.url -- it
    # is the prose telling you to add it by hand. An unanchored grep matches that
    # comment, and the damage is not cosmetic: a switch to stable then rewrites
    # the COMMENT instead of adding a real override, leaving a machine on stable
    # nixpkgs with a master home-manager. That is exactly the pairing this
    # command exists to prevent, arrived at silently and reported as success.
    want "the commented example is not read as a setting" "$r" 'no override here'
    wantnot "and its line number never leaks" "$r" '#   inputs.home-manager'

    # Declining must leave the file byte-identical. A backup is not a substitute
    # for not writing.
    mk decline
    before=$(cksum < decline/flake.nix)
    echo n | NIXARCHY_FLAKE=$PWD/decline $ch stable 25.11 >/dev/null 2>&1 || true
    if [ "$before" = "$(cksum < decline/flake.nix)" ]; then echo "  ok      declining changes nothing"
    else echo "  FAILED  declining rewrote the file"; fails=$((fails + 1)); fi

    # A flake reshaped past recognition is not ours to sed. Printing the edit is
    # the right answer; guessing at it is how a working machine stops booting.
    mk reshaped
    grep -v 'nixpkgs.url' plain/flake.nix > reshaped/flake.nix
    r=$(NIXARCHY_FLAKE=$PWD/reshaped $ch 2>&1 || true)
    want "a reshaped flake is refused"  "$r" 'has been reshaped'

    mk custom
    sed -i 's|nixos-unstable|someone/their-own-branch|' custom/flake.nix
    r=$(NIXARCHY_FLAKE=$PWD/custom $ch stable 25.11 2>&1 || true)
    want "a deliberate choice is kept"  "$r" 'neither channel'
    wantnot "and not overwritten"       "$r" 'Rewrote'

    r=$(NIXARCHY_FLAKE=$PWD/plain $ch unstable 2>&1 || true)
    want "already-on-it is a no-op"     "$r" 'Nothing to do'

    # Arguments that cannot mean anything are refused rather than interpreted.
    r=$(NIXARCHY_FLAKE=$PWD/plain $ch stable banana 2>&1 || true)
    want "a bad release is rejected"    "$r" 'looks like 25.05'
    r=$(NIXARCHY_FLAKE=$PWD/plain $ch unstable 25.11 2>&1 || true)
    want "a release needs stable"       "$r" "only means something with 'stable'"

    # The rewrite itself, offline. Re-locking needs a network and is not part of
    # what this asserts; the file's shape is.
    mk rewrite
    echo y | NIXARCHY_FLAKE=$PWD/rewrite $ch stable 25.11 >/dev/null 2>&1 || true
    f=$(cat rewrite/flake.nix)
    want "nixpkgs moved to the release" "$f" 'github:NixOS/nixpkgs/nixos-25.11'
    # The pairing is the entire point of the command existing.
    want "home-manager moved with it"   "$f" 'home-manager/release-25.11'
    want "beside the follows, as the template's own prose says" \
      "$f" 'inputs.nixpkgs.follows = "nixpkgs";'
    if [ -f rewrite/flake.nix.pre-channel ]; then echo "  ok      the previous file is kept"
    else echo "  FAILED  no .pre-channel backup"; fails=$((fails + 1)); fi

    # Back again, and the override must GO -- not be left pointing at a release
    # while nixpkgs follows unstable, which is the same broken pairing mirrored.
    echo y | NIXARCHY_FLAKE=$PWD/rewrite $ch unstable >/dev/null 2>&1 || true
    f=$(cat rewrite/flake.nix)
    want "and back to unstable"         "$f" 'nixos-unstable'
    wantnot "the override is removed"   "$f" 'release-25.11'

    # A floor. Every assertion above fails identically if the command printed
    # nothing at all, which reads as every rule being wrong rather than as the
    # binary being missing.
    [ -x "$ch" ] || { echo "nixarchy-channel is not executable at $ch"; exit 1; }

    echo
    if [ "$fails" -gt 0 ]; then echo "$fails failed"; exit 1; fi
    echo "nixarchy-channel: all assertions hold"
    touch $out
  ''
