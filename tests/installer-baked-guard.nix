{ pkgs, installScript }:
# run_install's choice between the system the offline image carries and a
# build (#1078): the baked system is the whole-disk reference machine, so a
# free-space or --from install must build. nix and nixos-install are stubs;
# what is asserted is the --system nixos-install was handed.
pkgs.runCommand "nixarchy-installer-baked-guard"
  {
    nativeBuildInputs = [
      pkgs.gnugrep
      pkgs.gnused
    ];
  }
  ''
    # The reference file lives in /etc on the image. Point the extracted
    # function at one written here, and prove the rewrite landed.
    sed -n '/^run_install()/,/^}/p' ${installScript} > ri-orig.sh
    sed "s|/etc/nixarchy-reference-|$PWD/ref-|" ri-orig.sh > ri.sh
    grep -q "$PWD/ref-" ri.sh || { echo "run_install no longer reads /etc/nixarchy-reference-<encrypt>" >&2; exit 1; }
    printf '%s\n' /nix/store/baked-system > ref-false

    fails=0
    t() { # t <name> <want: baked|built> <disk_mode> <from_repo>
      rm -f install-args
      (
        . ./ri.sh
        NIX_FLAGS=()
        SUBSTITUTE_FLAGS=()
        SUBSTITUTERS=""
        TRUSTED_KEYS=""
        build_store_choice=live hostname=h encrypt=false
        disk_mode=$3 from_repo=$4
        nix() {
          case "$*" in
            *path-info*) return 0 ;;
            *--dry-run*) echo "these 0 paths will be fetched" ;;
            *--print-out-paths*) echo /nix/store/built-system ;;
          esac
        }
        rescue_build() { return 1; }
        nixos-install() { printf '%s\n' "$@" > install-args; }
        run_install
      ) > "ri-$1.out" 2>&1 || true
      got=none
      if grep -qx /nix/store/baked-system install-args 2>/dev/null; then got=baked; fi
      if grep -qx /nix/store/built-system install-args 2>/dev/null; then got=built; fi
      if [ "$got" = "$2" ]; then
        echo "  ok      $1 ($got)"
      else
        echo "  FAILED  $1: wanted $2, got $got"
        sed 's/^/            /' "ri-$1.out"
        fails=$((fails + 1))
      fi
    }
    t whole-disk baked whole ""
    t free-space built free ""
    t from-repo built whole file:///repo
    grep -q 'building rather than copying' ri-free-space.out || {
      echo "  FAILED  free-space: the log does not say why it builds"
      fails=$((fails + 1))
    }
    [ "$fails" = 0 ] || { echo "$fails case(s) failed (#1078)" >&2; exit 1; }
    echo "only a whole-disk install without --from copies the image's system"
    touch $out
  ''
