{ inputs, pkgs }:
let
  publisher = pkgs.writeShellScriptBin "omarchy-theme-set-t3code" ''
    printf 'publisher\n' >> "$HOME/calls"
    [ ! -e "$HOME/publisher-fail" ] || exit 1
    [ ! -e "$HOME/no-theme" ] || exit 0
    mkdir -p "$T3CODE_HOME/userdata/themes"
    printf '{}\n' > "$T3CODE_HOME/userdata/themes/omarchy.json"
  '';
  t3 = pkgs.writeShellScriptBin "t3" ''
    printf 't3 %s\n' "$*" >> "$HOME/calls"
    if [ "''${T3_MODE:-}" = fail ]; then
      for n in 1 2 3 4 5 6 7; do printf 'line%s\n' "$n" >&2; done
      exit 1
    fi
    if [ -e "$HOME/t3-hang" ]; then
      ${pkgs.util-linux}/bin/setsid ${pkgs.coreutils}/bin/sleep 60 &
      printf '%s\n' "$!" > "$HOME/detached-pid"
      trap "" TERM
      exec ${pkgs.coreutils}/bin/sleep 60
    fi
    case "$3" in
      ember|grove|iris|ocean|t3-chat) ;;
      *)
        if [ ! -f "$5/userdata/themes/$3.json" ]; then
          printf 'ThemeIdUnknownError: No theme named "%s"\n' "$3" >&2
          exit 1
        fi
        ;;
    esac
    printf '{"defaultTheme":"%s"}\n' "$3" > "$5/userdata/settings.json"
  '';
  empty = pkgs.runCommand "t3code-empty-bin" { } "mkdir -p $out/bin";
  script =
    args:
    pkgs.callPackage ../modules/t3code-theme-script.nix { } (
      {
        inherit publisher t3;
        theme = "omarchy";
        timeoutSecs = 2;
        killSecs = 1;
      }
      // args
    );
  normal = script { };
  nullTheme = script { theme = null; };
  plus = script { theme = "omarchy-plus"; };
  emberTheme = script { theme = "ember"; };
  noT3 = script { t3 = empty; };
  noPublisher = script { publisher = empty; };
  vm = inputs.self.nixosConfigurations.vm.extendModules {
    modules = [
      {
        programs.nixarchy.apps."t3-code" = {
          enable = true;
          package = t3;
        };
      }
    ];
  };
  activation = pkgs.writeText "t3code-activation.sh" (
    vm.config.home-manager.users.omarchy.home.activation.nixarchyT3codeTheme.data
  );
  activationRunner = pkgs.writeShellScript "t3code-activation-runner" ''
    run() {
      if [[ -v DRY_RUN ]]; then printf 'dry run: %s\n' "$*"; else "$@"; fi
    }
    source ${activation}
  '';
in
pkgs.runCommand "nixarchy-t3code-theme-check"
  {
    nativeBuildInputs = [
      pkgs.coreutils
      pkgs.gnugrep
    ];
  }
  ''
    set -euo pipefail
    root=$PWD
    fail() { echo "FAILED: $1" >&2; exit 1; }
    stage() {
      mkdir -p "$root/$1/.local/state/omarchy/current/theme"
      printf '%s\n' "''${2:-{}}" > "$root/$1/.local/state/omarchy/current/theme/t3code.json"
    }
    run_case() {
      mkdir -p "$root/$1/tmp"
      if env -i HOME="$root/$1" TMPDIR="$root/$1/tmp" PATH=/var/empty T3_MODE="''${T3_MODE:-}" "$2"/bin/nixarchy-t3code-theme >"$root/$1.out" 2>&1; then
        echo "  exit 0: $1"
      else
        fail "$1 exited nonzero: $(cat "$root/$1.out")"
      fi
    }
    called() { grep -qF "$2" "$root/$1/calls"; }
    logged() { grep -qF "t3code-theme: $2" "$root/$1.out"; }

    run_case no-palette ${normal}
    [ ! -e no-palette/.t3 ] && [ ! -e no-palette/calls ] || fail "no palette created state or called a command"
    logged no-palette "no Omarchy palette staged yet; next activation retries" || fail "no palette log"

    stage publisher-fails
    mkdir -p publisher-fails/.t3/userdata/themes
    printf '{}\n' > publisher-fails/.t3/userdata/themes/omarchy.json
    touch publisher-fails/publisher-fail
    run_case publisher-fails ${normal}
    logged publisher-fails "publisher exited 1" || fail "publisher failure log"
    ! called publisher-fails "t3 " || fail "t3 ran after publisher failed"

    stage placeholder '{{'
    run_case placeholder ${normal}
    logged placeholder "palette has unresolved colours; kept the previous one" || fail "placeholder log"
    called placeholder "t3 " || fail "placeholder skipped selection"

    stage placeholder-no-theme '{{'
    touch placeholder-no-theme/no-theme
    run_case placeholder-no-theme ${normal}
    logged placeholder-no-theme "palette has unresolved colours; nothing published yet" || fail "placeholder without prior palette log"
    ! logged placeholder-no-theme "kept the previous one" || fail "placeholder claimed a previous palette"
    logged placeholder-no-theme "t3 theme set exited 1" || fail "placeholder missing theme failure log"
    logged placeholder-no-theme 'ThemeIdUnknownError: No theme named "omarchy"' || fail "placeholder missing theme detail"
    called placeholder-no-theme "t3 theme set omarchy" || fail "missing theme was not attempted"

    stage no-settings
    run_case no-settings ${normal}
    called no-settings "t3 theme set omarchy --base-dir $root/no-settings/.t3" || fail "missing settings did not select"
    grep -q '"defaultTheme":"omarchy"' no-settings/.t3/userdata/settings.json || fail "selection not written"

    stage ember
    mkdir -p ember/.t3/userdata
    printf '{"defaultTheme":"ember"}\n' > ember/.t3/userdata/settings.json
    run_case ember ${normal}
    called ember "t3 theme set omarchy" || fail "ember was not replaced"

    stage selected
    mkdir -p selected/.t3/userdata
    printf '{"defaultTheme":"omarchy"}\n' > selected/.t3/userdata/settings.json
    run_case selected ${normal}
    ! called selected "t3 " || fail "already selected theme ran t3"

    stage built-in-ember
    mkdir -p built-in-ember/.t3/userdata
    printf '{"defaultTheme":"omarchy"}\n' > built-in-ember/.t3/userdata/settings.json
    run_case built-in-ember ${emberTheme}
    called built-in-ember "t3 theme set ember --base-dir" || fail "built-in ember was not selected"
    grep -q '"defaultTheme":"ember"' built-in-ember/.t3/userdata/settings.json || fail "built-in ember selection missing"
    ! logged built-in-ember "using omarchy" || fail "built-in ember fell back"

    stage t3-error
    T3_MODE=fail run_case t3-error ${normal}
    logged t3-error "t3 theme set exited 1" || fail "t3 error log"
    for n in 3 4 5 6 7; do logged t3-error "line$n" || fail "missing tail line $n"; done
    ! logged t3-error "line1" && ! logged t3-error "line2" || fail "logged more than last five lines"

    stage t3-hangs
    touch t3-hangs/t3-hang
    trap 'if [ -f t3-hangs/detached-pid ]; then kill "$(cat t3-hangs/detached-pid)" 2>/dev/null || :; fi' EXIT
    start=$(date +%s)
    run_case t3-hangs ${plus}
    if [ -f t3-hangs/detached-pid ]; then kill "$(cat t3-hangs/detached-pid)" 2>/dev/null || :; fi
    trap - EXIT
    [ $(( $(date +%s) - start )) -lt 15 ] || fail "t3 timeout took 15 seconds"
    logged t3-hangs "t3 theme set exited 137" || fail "t3 timeout did not kill"
    [ "$(grep -c '^t3 ' t3-hangs/calls)" -eq 1 ] || fail "timeout caused a second t3 call"
    [ -z "$(find t3-hangs/tmp -type f -print)" ] || fail "t3 timeout left temp file"

    stage missing-t3
    run_case missing-t3 ${noT3}
    logged missing-t3 "t3 not found" || fail "missing t3 log"
    [ ! -e missing-t3/.t3 ] || fail "missing t3 created state"

    stage publish-only
    run_case publish-only ${nullTheme}
    called publish-only "publisher" && logged publish-only "publish only" || fail "null did not publish"
    ! called publish-only "t3 " || fail "null selected a theme"

    stage plus-fallback
    run_case plus-fallback ${plus}
    called plus-fallback "t3 theme set omarchy-plus --base-dir" || fail "unknown theme was not attempted"
    logged plus-fallback 'ThemeIdUnknownError: No theme named "omarchy-plus"' || fail "unknown theme detail"
    logged plus-fallback "theme omarchy-plus not available; using omarchy" || fail "fallback log"
    called plus-fallback "t3 theme set omarchy --base-dir" || fail "fallback did not select omarchy"
    [ "$(grep -c '^t3 ' plus-fallback/calls)" -eq 2 ] || fail "fallback made the wrong number of calls"

    stage plus-current
    mkdir -p plus-current/.t3/userdata
    printf '{"defaultTheme":"omarchy"}\n' > plus-current/.t3/userdata/settings.json
    run_case plus-current ${plus}
    called plus-current "t3 theme set omarchy-plus --base-dir" || fail "unknown theme was not attempted from omarchy"
    logged plus-current "theme omarchy-plus not available; using omarchy" || fail "current theme fallback log"
    [ "$(grep -c '^t3 ' plus-current/calls)" -eq 1 ] || fail "already current omarchy was selected again"

    stage plus-present
    mkdir -p plus-present/.t3/userdata/themes
    printf '{}\n' > plus-present/.t3/userdata/themes/omarchy-plus.json
    run_case plus-present ${plus}
    called plus-present "t3 theme set omarchy-plus --base-dir" || fail "plus theme not selected"

    mkdir -p no-home/tmp
    if env -i TMPDIR="$root/no-home/tmp" PATH=/var/empty ${normal}/bin/nixarchy-t3code-theme > no-home.out 2>&1; then
      echo "  exit 0: no-home"
    else
      fail "unset HOME exited nonzero"
    fi
    logged no-home "HOME unset" || fail "unset HOME log"

    stage plus-missing
    touch plus-missing/no-theme
    run_case plus-missing ${plus}
    logged plus-missing "t3 theme set exited 1" || fail "plus missing failure log"
    logged plus-missing 'ThemeIdUnknownError: No theme named "omarchy-plus"' || fail "plus missing detail"
    called plus-missing "t3 theme set omarchy-plus --base-dir" || fail "plus missing was not attempted"
    ! called plus-missing "t3 theme set omarchy --base-dir" || fail "fallback ran without omarchy palette"

    stage missing-publisher
    run_case missing-publisher ${noPublisher}
    logged missing-publisher "omarchy-theme-set-t3code not found" || fail "missing publisher log"
    [ ! -e missing-publisher/.t3 ] || fail "missing publisher created state"

    # Run the module's generated entry with the real publisher and a stub t3.
    stage activation
    mkdir -p activation/tmp
    if env -i HOME="$root/activation" TMPDIR="$root/activation/tmp" PATH=/var/empty ${activationRunner} > activation.out 2>&1; then
      echo "  exit 0: generated activation"
    else
      fail "generated activation failed: $(cat activation.out)"
    fi
    called activation "t3 theme set omarchy --base-dir" || fail "generated activation did not run t3"
    grep -q '"defaultTheme":"omarchy"' activation/.t3/userdata/settings.json || fail "generated activation did not set theme"

    stage activation-dry
    mkdir -p activation-dry/tmp
    if env -i HOME="$root/activation-dry" TMPDIR="$root/activation-dry/tmp" PATH=/var/empty DRY_RUN=1 ${activationRunner} > activation-dry.out 2>&1; then
      echo "  exit 0: generated activation dry"
    else
      fail "generated activation dry failed"
    fi
    [ ! -e activation-dry/.t3 ] && [ ! -e activation-dry/calls ] || fail "dry activation wrote state"

    stage activation-placeholder '{{'
    mkdir -p activation-placeholder/tmp activation-placeholder/.t3/userdata/themes
    printf 'previous palette\n' > activation-placeholder/.t3/userdata/themes/omarchy.json
    printf '{"defaultTheme":"omarchy"}\n' > activation-placeholder/.t3/userdata/settings.json
    if env -i HOME="$root/activation-placeholder" TMPDIR="$root/activation-placeholder/tmp" PATH=/var/empty ${activationRunner} > activation-placeholder.out 2>&1; then
      echo "  exit 0: generated activation placeholder"
    else
      fail "generated activation placeholder failed"
    fi
    grep -q '^previous palette$' activation-placeholder/.t3/userdata/themes/omarchy.json || fail "placeholder overwrote palette"
    logged activation-placeholder "palette has unresolved colours; kept the previous one" || fail "real publisher placeholder log"
    [ ! -e activation-placeholder/calls ] || fail "placeholder called t3"

    touch "$out"
  ''
