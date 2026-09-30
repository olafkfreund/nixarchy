{
  pkgs,
  installScript,
  dashboardScript,
}:
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
    sed -n '/^ui_finished()/,/^}/p' ${dashboardScript} > finished.sh
    sed -n '/^main()/,/^}/p' ${installScript} > main.sh
    grep -Fq 'ui_finished "$elapsed" "$username" "''${installed_baked:-false}"' main.sh || {
      echo 'FAILED main does not pass the baked-install result to finish'; exit 1;
    }
    grep -q "$PWD/ref-" ri.sh || { echo "run_install no longer reads /etc/nixarchy-reference-<encrypt>" >&2; exit 1; }
    printf '%s\n' /nix/store/baked-system > ref-false

    fails=0
    t() { # t <name> <want: baked|built> <disk_mode> <from_repo> [flag]
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
        nixos-install() { printf '%s\n' "$@" > install-args; return "''${INSTALL_RC:-0}"; }
        if run_install; then echo success > "result-$1"; else echo refused > "result-$1"; fi
        printf '%s\n' "$installed_baked" > "flag-$1"
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
      want_flag=false
      [ "$2" != baked ] || want_flag=true
      [ "''${5:-}" != false ] || want_flag=false
      [ "$(cat "flag-$1" 2>/dev/null)" = "$want_flag" ] || {
        echo "  FAILED  $1: recorded baked flag is wrong"; fails=$((fails + 1));
      }
    }
    t whole-disk baked whole ""
    t free-space built free ""
    t from-repo built whole file:///repo
    INSTALL_RC=1 t failed-install baked whole "" false
    [ "$(cat result-failed-install)" = refused ] || { echo 'FAILED copied system marked installed after nixos-install failure'; fails=$((fails+1)); }
    (
      . ./finished.sh
      ui_init() { :; }
      ui_clear() { :; }
      ui_logo() { :; }
      ui_elapsed() { echo 1m; }
      ui_centre() { printf '%s\n' "$1"; }
      ui_interactive() { return 1; }
      ui_finished 60 alice true
    ) > finished-baked.out
    grep -q 'log in as .*omarchy' finished-baked.out || { echo 'FAILED copied system login is not omarchy'; fails=$((fails+1)); }
    grep -q 'alice appears after the first online rebuild' finished-baked.out || { echo 'FAILED copied system does not explain online rebuild'; fails=$((fails+1)); }
    (
      . ./finished.sh
      ui_init() { :; }
      ui_clear() { :; }
      ui_logo() { :; }
      ui_elapsed() { echo 1m; }
      ui_centre() { printf '%s\n' "$1"; }
      ui_interactive() { return 1; }
      ui_finished 60 alice false
    ) > finished-built.out
    grep -q 'log in as .*alice' finished-built.out || { echo 'FAILED built system login changed'; fails=$((fails+1)); }
    grep -q 'building rather than copying' ri-free-space.out || {
      echo "  FAILED  free-space: the log does not say why it builds"
      fails=$((fails + 1))
    }
    [ "$fails" = 0 ] || { echo "$fails case(s) failed (#1078)" >&2; exit 1; }
    echo "only a whole-disk install without --from copies the image's system"
    touch $out
  ''
