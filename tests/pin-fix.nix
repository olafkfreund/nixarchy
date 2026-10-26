# The pure modes of .github/scripts/pin-fix.sh, against fixtures (#1459).
#
# pin-fix.sh decides whether a nixpkgs bump may be answered with a proposed move
# of a commit-pinned input, and whether a bump PR touches nothing but nixpkgs.
# Both are decisions that fail OPEN when wrong -- a move proposed for an input
# that is not ours to move, an auto-merge armed on a PR that carries more than
# the bump -- so each refusal and each acceptance is asserted here.
#
# The shas are read from the real flake.lock inside the build, not written
# here: they change whenever a pin moves. The probe table is checked at
# evaluation time, because a sandboxed check cannot run `nix eval`.
{ inputs, pkgs, ... }:
let
  inherit (pkgs) lib;
  table = import ../data/pin-fix.nix;
  system = "x86_64-linux";
  has = set: path: lib.hasAttrByPath (lib.splitString "." path) set;
  # A probe is an installable without `.#`: `checks.<system>.x` names a check,
  # a bare name resolves under packages.
  exists =
    probe:
    let
      checksPrefix = "checks.${system}.";
    in
    if lib.hasPrefix checksPrefix probe then
      builtins.elem (lib.removePrefix checksPrefix probe) (
        builtins.attrNames inputs.self.checks.${system}
      )
    else
      has inputs.self.packages.${system} probe;
  missing = lib.filterAttrs (_: row: !exists row.probe) table;
in
assert lib.assertMsg (missing == { })
  "data/pin-fix.nix: probe target does not exist in this flake for: ${lib.concatStringsSep ", " (builtins.attrNames missing)}";
pkgs.runCommand "nixarchy-pin-fix"
  {
    nativeBuildInputs = with pkgs; [
      bash
      jq
      coreutils
      gnugrep
      gnused
      gawk
      diffutils
      git
    ];
  }
  ''
    set +e # the checks below read exit statuses on purpose
    P=${../.github/scripts/pin-fix.sh}
    fail=0
    expect() { # name, wanted, got
      if [ "$2" != "$3" ]; then
        echo "FAIL $1: wanted '$2', got '$3'" >&2
        fail=1
      fi
    }
    expect_prefix() { # name, wanted prefix, got
      case "$3" in
        "$2"*) ;;
        *) echo "FAIL $1: wanted '$2...', got '$3'" >&2; fail=1 ;;
      esac
    }

    # ---- --decide
    NEW=$(printf 'a%.0s' $(seq 40))
    cmp_json() { jq -n --arg s "$1" --argjson n "$2" '{status: $s, ahead_by: $n}' > c.json; }
    cmp_json ahead 42;      expect "decide ahead 42" "move $NEW 42" "$(bash $P --decide microvm-nix c.json $NEW)"
    cmp_json ahead 100;     expect_prefix "decide ahead 100" "move " "$(bash $P --decide microvm-nix c.json $NEW)"
    cmp_json ahead 101;     expect_prefix "decide ahead 101" "refuse" "$(bash $P --decide microvm-nix c.json $NEW)"
    cmp_json ahead 0;       expect_prefix "decide ahead 0" "refuse" "$(bash $P --decide microvm-nix c.json $NEW)"
    cmp_json identical 0;   expect_prefix "decide identical" "refuse" "$(bash $P --decide microvm-nix c.json $NEW)"
    cmp_json diverged 5;    expect_prefix "decide diverged" "refuse" "$(bash $P --decide microvm-nix c.json $NEW)"
    cmp_json behind 5;      expect_prefix "decide behind" "refuse" "$(bash $P --decide microvm-nix c.json $NEW)"
    cmp_json ahead 3;       expect_prefix "decide bad sha" "refuse" "$(bash $P --decide microvm-nix c.json not-a-sha)"
    expect_prefix "decide own repo" "refuse" "$(bash $P --decide olafkfreund c.json $NEW)"

    # ---- --replace, on a copy of the real flake.nix
    rev_of() { jq -r --arg n "$1" '.nodes[$n].locked.rev' ${../flake.lock}; }
    for in in microvm zen-browser; do
      cp ${../flake.nix} f.nix; chmod u+w f.nix
      bash $P --replace f.nix $in "$(rev_of $in)" $NEW || { echo "FAIL replace $in: non-zero" >&2; fail=1; }
      expect "replace $in changes one line" "1" "$(diff ${../flake.nix} f.nix | grep -c '^>')"
      expect "replace $in writes the full sha" "1" "$(grep -cF "/$NEW\"" f.nix)"
      # every other pinned url is byte-identical
      expect "replace $in leaves the other urls" \
        "$(grep 'url = "github:' ${../flake.nix} | grep -vF "$(rev_of $in | cut -c1-12)" | md5sum)" \
        "$(grep 'url = "github:' f.nix | grep -vF "$NEW" | md5sum)"
    done
    cp ${../flake.nix} f.nix; chmod u+w f.nix
    if bash $P --replace f.nix microvm "$(printf 'b%.0s' $(seq 40))" $NEW 2>/dev/null; then
      echo "FAIL replace: accepted an old sha that is not in the file" >&2; fail=1
    fi
    cmp ${../flake.nix} f.nix || { echo "FAIL replace: file changed on refusal" >&2; fail=1; }
    if bash $P --replace f.nix zen-browser "$(rev_of microvm)" $NEW 2>/dev/null; then
      echo "FAIL replace: accepted a prefix mismatch" >&2; fail=1
    fi
    cmp ${../flake.nix} f.nix || { echo "FAIL replace: file changed on mismatch" >&2; fail=1; }
    # the same url twice: not exactly one occurrence
    cp ${../flake.nix} dup.nix; chmod u+w dup.nix
    grep -F 'url = "github:microvm-nix/microvm.nix/' ${../flake.nix} >> dup.nix
    cp dup.nix dup.orig
    if bash $P --replace dup.nix microvm "$(rev_of microvm)" $NEW 2>/dev/null; then
      echo "FAIL replace: accepted a url present twice" >&2; fail=1
    fi
    cmp dup.orig dup.nix || { echo "FAIL replace: file changed on duplicate" >&2; fail=1; }

    # ---- --moved
    L=${../flake.lock}
    jq '.nodes.microvm.locked.rev = "1111111111111111111111111111111111111111"' $L > mv.lock
    jq '.nodes.microvm.locked.rev = "1111111111111111111111111111111111111111"
        | .nodes.spectrum.locked.rev = "2"' $L > mvs.lock
    jq '.nodes.root.inputs.extra = "x"' $L > add.lock
    jq '.nodes.nixpkgs_2.locked.rev = "3"' $L > np.lock
    jq '.nodes.nixpkgs_2.locked.rev = "3" | .nodes.microvm.locked.rev = "1"' $L > npmv.lock
    jq '.nodes.nixpkgs_3 = .nodes.nixpkgs_2 | del(.nodes.nixpkgs_2)
        | .nodes.root.inputs.nixpkgs = "nixpkgs_3"' $L > ren.lock
    expect "moved microvm" "microvm" "$(bash $P --moved $L mv.lock)"
    expect "moved microvm + spectrum" "microvm" "$(bash $P --moved $L mvs.lock)"
    expect "moved nothing" "" "$(bash $P --moved $L $L)"
    bash $P --moved $L add.lock >/dev/null 2>&1; expect "moved added input" "2" "$?"

    # ---- --only-nixpkgs
    bash $P --only-nixpkgs $L np.lock;   expect "only-nixpkgs nixpkgs" "0" "$?"
    bash $P --only-nixpkgs $L mv.lock;   expect "only-nixpkgs microvm" "1" "$?"
    bash $P --only-nixpkgs $L npmv.lock; expect "only-nixpkgs nixpkgs+microvm" "1" "$?"
    bash $P --only-nixpkgs $L ren.lock;  expect "only-nixpkgs renamed node" "1" "$?"
    printf 'flake.lock\n' > files-lock; printf 'flake.lock\nflake.nix\n' > files-more; : > files-none
    bash $P --only-nixpkgs $L np.lock files-lock; expect "only-nixpkgs files lock" "0" "$?"
    bash $P --only-nixpkgs $L np.lock files-more; expect "only-nixpkgs files +flake.nix" "1" "$?"
    bash $P --only-nixpkgs $L np.lock files-none; expect "only-nixpkgs files none" "1" "$?"

    # ---- --intact: a moved input keeps what it follows, and brings no nixpkgs
    jq '.nodes.microvm.inputs.nixpkgs = "nixpkgs_9" | .nodes.nixpkgs_9 = .nodes.nixpkgs_2' mvs.lock > own.lock
    jq '.nodes.microvm.inputs.nixpkgs = ["nixpkgs-stable"]' mvs.lock > refollow.lock
    bash $P --intact $L mvs.lock microvm;      expect "intact microvm + spectrum" "0" "$?"
    bash $P --intact $L own.lock microvm;      expect "intact own nixpkgs" "1" "$?"
    bash $P --intact $L refollow.lock microvm; expect "intact follows changed" "1" "$?"
    jq '.nodes.nixpkgs_9 = .nodes.nixpkgs_2 | .nodes.spectrum.inputs = {nixpkgs: "nixpkgs_9"}' mvs.lock > deep.lock
    bash $P --intact $L deep.lock microvm;     expect "intact nixpkgs added below" "1" "$?"

    # ---- --sanitize and --quote-subject. The markers are built from parts so
    # this file never holds one (AGENTS.md section 8).
    s1="[ Ski""p  CI ]"; s2="[CI sk""ip]"; s3="[No ""Ci]"; s4="[skip ""ACTIONS]"; s5="[actions ""skip]"
    san=$(printf 'a %s b %s c %s d %s e %s f [keep]\n' "$s1" "$s2" "$s3" "$s4" "$s5" | bash $P --sanitize)
    expect "sanitize" "a (skip-ci marker removed) b (skip-ci marker removed) c (skip-ci marker removed) d (skip-ci marker removed) e (skip-ci marker removed) f [keep]" "$san"
    expect "quote-subject" '`Fix @user and #12 code`' "$(printf 'Fix @user and #12 `code`\n' | bash $P --quote-subject)"

    # ---- --owner
    T='Generated by .github/workflows/flake-update.yml.'
    owner() { printf '%s' "$1" > o.json; bash $P --owner o.json; }
    expect "owner no branch" "writable " "$(owner '{"branch_exists":false,"pr":null,"commits":[],"bot":"b"}')"
    expect "owner no pr" "writable " "$(owner '{"branch_exists":true,"pr":null,"commits":[],"bot":"b"}')"
    expect "owner closed pr" "writable " "$(owner '{"branch_exists":true,"pr":{"number":7,"isDraft":true,"author":"h","state":"CLOSED"},"commits":[],"bot":"b"}')"
    expect "owner bot draft" "writable 7" "$(owner '{"branch_exists":true,"pr":{"number":7,"isDraft":true,"author":"b","state":"OPEN"},"commits":[{"message":"x\n\n'"$T"'"}],"bot":"b"}')"
    expect_prefix "owner human commit" "held" "$(owner '{"branch_exists":true,"pr":{"number":7,"isDraft":true,"author":"b","state":"OPEN"},"commits":[{"message":"x\n\n'"$T"'"},{"message":"fix"}],"bot":"b"}')"
    expect_prefix "owner ready pr" "held" "$(owner '{"branch_exists":true,"pr":{"number":7,"isDraft":false,"author":"b","state":"OPEN"},"commits":[],"bot":"b"}')"
    expect_prefix "owner other author" "held" "$(owner '{"branch_exists":true,"pr":{"number":7,"isDraft":true,"author":"h","state":"OPEN"},"commits":[],"bot":"b"}')"

    # ---- --table and --nixpkgs-rev (flake-update.yml's summaries and comment marker)
    expect "table" "$(printf '| target | error |\n|---|---|\n| `.#a` | x \\| y |')" \
      "$(printf '.#a\tx | y\n' | bash $P --table)"
    expect "nixpkgs-rev" "$(jq -r '.nodes.nixpkgs_2.locked.rev' $L)" "$(bash $P --nixpkgs-rev $L)"

    [ "$fail" = 0 ] || exit 1
    touch $out
  ''
