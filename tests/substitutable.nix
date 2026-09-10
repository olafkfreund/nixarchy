{ pkgs }:
# installer/substitutable.sh answers "what would a machine without this store
# have to build?", and the answer decides whether a network reinstall image
# (#483) is honest for a given closure.
#
# The classification is the whole thing, so the fixtures are the three classes
# and the two refusals. Real `nix path-info --json` output, reshaped: the
# fields are the ones nix actually emits (ultimate, signatures, ca, narSize),
# because a fixture invented from the man page proves the script agrees with a
# document rather than with nix.
let
  inherit (pkgs) lib;

  # A closure the script will accept: over the 100-path floor, and carrying one
  # of each class. Padded with signed text derivations, which is what a real
  # closure mostly is.
  padding = lib.listToAttrs (
    lib.genList (i: {
      name = "/nix/store/${toString i}pad000000000000000000000000000-unit-${toString i}.service";
      value = {
        narSize = 4096;
        signatures = [ "cache.nixos.org-1:fake" ];
        ca = null;
        ultimate = false;
        references = [ ];
      };
    }) 120
  );

  closure = padding // {
    # Signed by a cache: free, whatever its size.
    "/nix/store/aaa00000000000000000000000000000-firefox-140.0" = {
      narSize = 300000000;
      signatures = [ "cache.nixos.org-1:fake" ];
      ca = null;
      ultimate = false;
      references = [ ];
    };
    # Built here, big: THE answer. Nothing can supply it.
    "/nix/store/bbb00000000000000000000000000000-vscode-1.136.1" = {
      narSize = 1073000000;
      signatures = [ ];
      ca = null;
      ultimate = true;
      references = [ ];
    };
    # Built here, fixed-output: re-downloadable from upstream, so it costs
    # bandwidth rather than a compiler. Must NOT be reported as a build.
    "/nix/store/ccc00000000000000000000000000000-lmstudio-extracted" = {
      narSize = 2326000000;
      signatures = [ ];
      ca = "fixed:r:sha256:deadbeef";
      ultimate = true;
      references = [ ];
    };
    # Built here and tiny: a unit file. NixOS assembles these on every machine
    # in seconds, and reporting 1,186 of them would bury the entries that
    # matter under a thousand that do not.
    "/nix/store/ddd00000000000000000000000000000-etc-updatedb.conf" = {
      narSize = 200;
      signatures = [ ];
      ca = null;
      ultimate = true;
      references = [ ];
    };
  };

  # Same shape, one path: trips the "that cannot be a system" floor.
  tiny = {
    "/nix/store/eee00000000000000000000000000000-nothing" = {
      narSize = 10;
      signatures = [ ];
      ca = null;
      ultimate = true;
      references = [ ];
    };
  };
in
pkgs.runCommand "nixarchy-substitutable"
  {
    nativeBuildInputs = [
      pkgs.python3
      pkgs.gnugrep
      pkgs.coreutils
    ];
    closureJson = builtins.toJSON closure;
    tinyJson = builtins.toJSON tiny;
    script = ../installer/substitutable.sh;
  }
  ''
    export HOME=$PWD
    mkdir -p bin
    printf '%s' "$closureJson" > closure.json
    printf '%s' "$tinyJson" > tiny.json

    # `nix` is not in this sandbox and must not be: the point is to drive the
    # CLASSIFICATION, not nix. The stub answers with the fixture named by
    # $FIXTURE, and fails the way nix does when asked for a path it has no
    # record of -- which is the refusal path.
    cat > bin/nix <<'STUB'
    #!/bin/sh
    case "$*" in
      *missing-closure*) exit 1 ;;
    esac
    cat "$FIXTURE"
    STUB
    sed -i 's/^    //' bin/nix
    chmod +x bin/nix
    export PATH=$PWD/bin:$PATH

    fails=0
    want() {
      if printf '%s' "$2" | grep -q -- "$3"; then echo "  ok      $1"
      else
        echo "  FAILED  $1: no /$3/ in:"; printf '%s\n' "$2" | sed 's/^/            /'
        fails=$((fails + 1))
      fi
    }
    reject() {
      if printf '%s' "$2" | grep -q -- "$3"; then
        echo "  FAILED  $1: /$3/ is present and should not be"
        printf '%s\n' "$2" | sed 's/^/            /'
        fails=$((fails + 1))
      else echo "  ok      $1"
      fi
    }
    code() {
      if [ "$2" = "$3" ]; then echo "  ok      $1 (exit $3)"
      else echo "  FAILED  $1: wanted exit $3, got $2"; fails=$((fails + 1)); fi
    }

    echo "classification:"
    FIXTURE=$PWD/closure.json
    export FIXTURE
    got=$(sh $script /nix/store/xxx-system 2>&1) || rc=$?
    rc=''${rc:-0}

    want "counts the whole closure"          "$got" "124 paths"
    want "reports the locally built package" "$got" "vscode-1.136.1"
    reject "does not report the signed one"  "$got" "firefox"
    reject "does not report the fixed-output one" "$got" "lmstudio"
    reject "does not report the text derivation" "$got" "etc-updatedb"
    code "says something must be built"      "$rc" 1

    # Size is the only thing separating "a package" from "a unit file", so the
    # floor is a knob and the knob is asserted.
    echo "the floor:"
    rc=0
    got=$(NIXARCHY_SUBSTITUTABLE_FLOOR=1 sh $script /nix/store/xxx-system 2>&1) || rc=$?
    want "a floor of 1 catches the text derivation" "$got" "etc-updatedb"
    reject "and still not the fixed-output one"     "$got" "lmstudio"

    echo "refusals:"
    rc=0
    FIXTURE=$PWD/tiny.json
    got=$(sh $script /nix/store/xxx-system 2>&1) || rc=$?
    want "a one-path closure is refused" "$got" "cannot be a system"
    code "and says so with exit 2"       "$rc" 2

    rc=0
    got=$(sh $script /nix/store/missing-closure 2>&1) || rc=$?
    want "an unreadable closure refuses"          "$got" "cannot read the closure"
    # The tolerance rule: a probe that cannot read must not answer "nothing to
    # build", because that is the answer that gets a disk wiped.
    want "and says what it must not be read as"   "$got" "can all be fetched"
    code "with exit 2, not 0"                     "$rc" 2

    [ "$fails" -eq 0 ] || { echo "$fails failed"; exit 1; }
    echo "all ok"
    touch $out
  ''
