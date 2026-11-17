{ inputs, pkgs }:
let
  testLib = import ./lib.nix { inherit inputs; };
  search = testLib.vmPackage "nixarchy-search";
  fixture = pkgs.writeText "pkg-index-fixture.nix" ''
    { config ? {}, ... }:
    let
      lib = import ${pkgs.path}/lib;
      pkg = name: version: meta: { type = "derivation"; inherit name version meta; };
    in {
      inherit lib;
      fixVuln = pkg "fixVuln" "1.0" { knownVulnerabilities = [ "x" ]; };
      fixInsecureOnly = pkg "fixInsecureOnly" "1.0" { insecure = true; };
      fixClean = pkg "fixClean" "1.0" { description = "clean package"; };
      fixNullInsecure = pkg "fixNullInsecure" "1.0" { insecure = null; };
      fixThrowVuln = pkg "fixThrowVuln" "1.0" { knownVulnerabilities = throw "boom"; };
      fixThrowElem = pkg "fixThrowElem" "1.0" { knownVulnerabilities = [ (throw "boom") ]; };
      fixThrowInsecureList = pkg "fixThrowInsecureList" "1.0" {
        insecure = throw "boom";
        knownVulnerabilities = [ "x" ];
      };
      fixInsecureThrowVuln = pkg "fixInsecureThrowVuln" "1.0" {
        insecure = true;
        knownVulnerabilities = throw "boom";
      };
      fixThrowMeta = (pkg "fixThrowMeta" "1.0" {}) // { meta = throw "boom"; };
      fixStrVuln = pkg "fixStrVuln" "1.0" { knownVulnerabilities = "oops"; };
      fixEmptyList = pkg "fixEmptyList" "1.0" { knownVulnerabilities = []; };
      fixAll = pkg "fixAll" "1.0" {
        license = { shortName = "fixture"; free = false; };
        broken = true;
        knownVulnerabilities = [ "y" ];
      };
      fixBrokenInsecure = pkg "fixBrokenInsecure" "1.0" { broken = true; insecure = true; };
      fixNoVersion = { type = "derivation"; name = "fixNoVersion"; meta = { insecure = true; }; };
      fixCurated = pkg "fixCurated" "1.0" { knownVulnerabilities = [ "z" ]; };
      sub = {
        recurseForDerivations = true;
        child = pkg "child" "1.0" { description = "nested package"; };
      };
    }
  '';
  appindex = pkgs.writeText "pkg-index-apps.tsv" "fixCurated\tFixture app\tfixture\t\ttry\n";
  apptable = pkgs.writeText "pkg-index-curated.tsv" "fixCurated\tfixcurated\n";
  optionsjson = pkgs.writeText "pkg-index-options.json" ''
    {"services.fixture.enable":{"description":"Fixture option","type":"boolean","default":false,"declarations":["fixture.nix"]}}
  '';
  walkB = pkgs.writeText "pkg-index-walk-newline.nix" (
    builtins.readFile ../modules/pkg-index.nix + "\n"
  );
  mk =
    goldenOnly:
    pkgs.runCommand (if goldenOnly then "pkg-index-golden" else "pkg-index")
      {
        nativeBuildInputs = with pkgs; [
          bash
          coreutils
          diffutils
          gawk
          gnugrep
          gnused
          jq
          nix
        ];
      }
      ''
        set -eo pipefail
        export NIX_STATE_DIR=$PWD/nix-state NIX_LOG_DIR=$PWD/nix-state
        mkdir -p "$NIX_STATE_DIR" cache
        cache=$PWD/cache
        index=$cache/index.tsv
        stamp=$cache/stamp
        nixpkgs=${fixture}
        optionsjson=${optionsjson}
        appindex=${appindex}
        apptable=${apptable}
        walk=${../modules/pkg-index.nix}
        search=${search}/bin/nixarchy-search

        sed -n '/^build_index() {/,/^}/p; /^stamp_key() {/,/^}/p; /^index_stale() {/,/^}/p' "$search" > functions.sh
        for name in build_index stamp_key index_stale; do
          if ! grep -q "^$name() {" functions.sh; then
            echo "pkg-index: empty extraction of $name from nixarchy-search" >&2
            exit 1
          fi
        done
        grep -E '^(flatpakrows|pkgnewrow|allowunfree)=' "$search" > baked.sh || { echo 'pkg-index: baked search inputs moved' >&2; exit 1; }
        [ "$(wc -l < baked.sh)" -eq 3 ] || { echo 'pkg-index: baked search inputs moved' >&2; exit 1; }
        . ./baked.sh

        # A plain statement, not an if/! condition, so errexit holds inside build_index as in production.
        ( set -euo pipefail; . ./functions.sh; build_index )
        awk -F '\t' '$1 == "app" || $1 == "opt" || $1 == "pkg"' "$index" | cut -f1-5 > rows.tsv
        ${
          if goldenOnly then
            ''
              cp rows.tsv "$out"
            ''
          else
            ''
              fails=0
              fail() { echo "FAILED pkg-index: $1" >&2; fails=$((fails + 1)); }

              if ! nix-instantiate --eval --strict --json --arg nixpkgs "$nixpkgs" "$walk" > walk.json; then
                echo 'pkg-index: walk evaluation failed' >&2
                exit 1
              fi
              insecure='["fixAll","fixBrokenInsecure","fixCurated","fixInsecureOnly","fixInsecureThrowVuln","fixNoVersion","fixThrowElem","fixThrowInsecureList","fixVuln"]'
              expected='["fixAll","fixBrokenInsecure","fixClean","fixCurated","fixEmptyList","fixInsecureOnly","fixInsecureThrowVuln","fixNoVersion","fixNullInsecure","fixStrVuln","fixThrowElem","fixThrowInsecureList","fixThrowMeta","fixThrowVuln","fixVuln","sub.child"]'
              jq -e --argjson expected "$expected" '([.[].attr] | sort) == ($expected | sort)' walk.json >/dev/null || fail 'walk attribute set'
              jq -e --argjson expected "$insecure" '([.[] | select(.insecure == true) | .attr] | sort) == ($expected | sort)' walk.json >/dev/null || fail 'walk insecure set'

              awk -F '\t' -v expected=16 '
                $1 == "pkg" { n++ }
                END { if (n != expected) { print "pkg rows: expected " expected ", got " n > "/dev/stderr"; exit 1 } }
              ' "$index" || fail 'package row count'
              for kind in app opt pkg flatpak new; do
                awk -F '\t' -v kind="$kind" '$1 == kind { found = 1 } END { exit !found }' "$index" || fail "$kind row missing"
              done
              awk -F '\t' 'NF != 6 { print "wrong field count in " $1 " row: " $2 > "/dev/stderr"; bad = 1 } END { exit bad }' "$index" || fail 'six fields'
              awk -F '\t' '
                $1 != "pkg" && $6 != "" { print "non-package version: " $1 ":" $2 > "/dev/stderr"; bad = 1 }
                $1 == "pkg" {
                  want = ($2 == "fixNoVersion" ? "" : "1.0")
                  if ($6 != want || index($5, "\\nversion:  " (want == "" ? "?" : want)) == 0) {
                    print "package version: " $2 > "/dev/stderr"; bad = 1
                  }
                }
                END { exit bad }
              ' "$index" || fail 'version field and preview'
              awk -F '\t' '
                $1 == "pkg" {
                  want = ($2 == "fixAll" ? "unfree broken insecure" :
                          $2 == "fixBrokenInsecure" ? "broken insecure" :
                          $2 == "fixCurated" ? "insecure curated:fixcurated" :
                          $2 ~ /^(fixVuln|fixInsecureOnly|fixInsecureThrowVuln|fixThrowElem|fixThrowInsecureList|fixNoVersion)$/ ? "insecure" : "")
                  if ($4 != want) { print "flags: " $2 ": " $4 > "/dev/stderr"; bad = 1 }
                  marked = index($5, "Marked INSECURE") != 0
                  if (marked != (want ~ /(^| )insecure( |$)/)) { print "preview insecurity: " $2 > "/dev/stderr"; bad = 1 }
                  if (index($3, "[insecure]") != 0) { print "summary insecurity: " $2 > "/dev/stderr"; bad = 1 }
                  if ($2 == "fixAll" && (index($3, "[unfree]  [broken]") == 0 || index($5, "Marked BROKEN") == 0)) {
                    print "fixAll lost existing markers" > "/dev/stderr"; bad = 1
                  }
                  if ($2 == "fixInsecureOnly" && index($4, "unfree") != 0) { print "insecure matched unfree" > "/dev/stderr"; bad = 1 }
                }
                END { exit bad }
              ' "$index" || fail 'flags and preview'

              awk -F '\t' -v OFS='\t' '
                $1 == "app" || $1 == "opt" || $1 == "pkg" {
                  if ($1 == "pkg") {
                    gsub(/(^| )insecure( |$)/, " ", $4)
                    gsub(/^ +| +$/, "", $4)
                    gsub(/\\n\\nMarked INSECURE in nixpkgs\./, "", $5)
                  }
                  print $1, $2, $3, $4, $5
                }
              ' "$index" > comparable.tsv
              diff -u ${./fixtures/pkg-index.golden.tsv} comparable.tsv >&2 || fail 'app, opt and pkg fields 1-5 differ from golden'

              . ./functions.sh
              stamp_key > "$stamp"
              index_stale && fail 'walk A stamp is stale'
              walk=${walkB}
              index_stale || fail 'walk B did not stale the stamp'
              [ "$fails" -eq 0 ] || exit 1
              touch "$out"
            ''
        }
      '';
  check = mk false;
in
check.overrideAttrs (old: {
  passthru = (old.passthru or { }) // {
    golden = mk true;
  };
})
