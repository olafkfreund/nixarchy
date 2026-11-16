{ inputs, pkgs }:
let
  lib = pkgs.lib;
  omarchy = (pkgs.extend inputs.self.overlays.default).omarchy;
  fixtureT3 = pkgs.writeShellScriptBin "t3" ''
    echo "t3 $*" >> "$T3_CALLS"
    exec ${pkgs.t3code}/bin/t3 "$@"
  '';
  sleepyT3 = pkgs.writeShellScriptBin "t3" ''
    trap "" TERM
    echo "t3 $*" >> "$T3_CALLS"
    sleep 600
  '';
  publisher = pkgs.writeShellScript "fixture-theme-set-t3code" ''
    echo publish >> "$T3_CALLS"
    [ -n "''${FIXTURE_PUBLISH_FAIL:-}" ] && exit 1
    exec "$(dirname "$0")/.real-theme-set-t3code" "$@"
  '';
  fixtureTree = pkgs.runCommand "nixarchy-t3code-theme-tree" { } ''
    cp -r ${omarchy}/share/omarchy "$out"
    chmod -R u+w "$out"
    mv "$out/bin/omarchy-theme-set-t3code" "$out/bin/.real-theme-set-t3code"
    cp ${publisher} "$out/bin/omarchy-theme-set-t3code"
    chmod +x "$out/bin/omarchy-theme-set-t3code"
  '';
  homeWith =
    {
      package,
      sessionT3 ? null,
    }:
    let
      home =
        (inputs.home-manager.lib.homeManagerConfiguration {
          inherit pkgs;
          extraSpecialArgs.osConfig.programs.nixarchy = {
            apps.t3-code = {
              enable = true;
              inherit package;
            };
            tree = fixtureTree;
          };
          modules = [
            inputs.self.homeManagerModules.nixarchy
            {
              home = {
                username = "someone";
                homeDirectory = "/build/t3-home";
                stateVersion = "25.05";
                sessionVariables = lib.optionalAttrs (sessionT3 != null) { T3CODE_HOME = sessionT3; };
              };
              programs.nixarchy.enable = true;
            }
          ];
        }).config;
      entry = home.home.activation.nixarchyT3CodeTheme;
    in
    assert lib.assertMsg (builtins.elem "nixarchySeed" entry.after) "T3 Code must follow nixarchySeed";
    pkgs.writeText "nixarchy-t3code-theme-entry" entry.data;
  regular = homeWith { package = fixtureT3; };
  spaced = homeWith {
    package = fixtureT3;
    sessionT3 = "/build/t3-home/my t3";
  };
  sleepy = homeWith { package = sleepyT3; };
  cases = pkgs.writeText "nixarchy-t3code-theme-cases" ''
    set -eu -o pipefail
    trap 'echo "case $1 failed at line $LINENO" >&2' ERR
    export HOME=/build/t3-home USER=someone T3_CALLS=$TMPDIR/calls
    [ -w /build ] || { echo '/build is not writable' >&2; exit 1; }
    rm -rf "$HOME"
    mkdir -p "$HOME/.local/state/omarchy/current/theme" "$HOME/.local/state/nix/profiles"
    : > "$T3_CALLS"
    theme=$HOME/.local/state/omarchy/current/theme/t3code.json
    marker=$HOME/.local/state/nixarchy/t3code-theme-selected
    t3home=$HOME/.t3
    settings=$t3home/userdata/settings.json
    palette=$t3home/userdata/themes/omarchy.json
    sed -E 's/\{\{[^}]*\}\}/#336699/g; s/"appearance": "#336699"/"appearance": "dark"/' \
      ${fixtureTree}/default/themed/t3code.json.tpl > "$theme"

    # The pinned init runs Nix profile sanity calls; only those calls are stubbed.
    nix-build() { :; }
    nix-env() { :; }
    source ${inputs.home-manager}/lib/bash/home-manager.sh
    source ${inputs.home-manager}/modules/lib-bash/activation-init.sh
    source_entry() { source "$1"; }
    set_calls() { grep -Fc 't3 theme set omarchy --base-dir ' "$T3_CALLS" || :; }
    no_set() { [ "$(set_calls)" -eq 0 ]; }
    published() { grep -Fxq publish "$T3_CALLS"; }
    choice() { [ ! -e "$settings" ] || ${pkgs.jq}/bin/jq -r '.defaultTheme // empty' "$settings"; }
    fresh() {
      source_entry ${regular}
      published && cmp -s "$theme" "$palette" && [ "$(choice)" = omarchy ] &&
        [ -f "$marker" ] && [ "$(set_calls)" -eq 1 ]
    }
    case "$1" in
      1) fresh ;;
      2) fresh; source_entry ${regular}; [ "$(set_calls)" -eq 1 ] ;;
      3) mkdir -p "$(dirname "$settings")"; printf '%s\n' '{"defaultTheme":"ember"}' > "$settings"
         source_entry ${regular}; [ "$(choice)" = ember ] && [ -f "$marker" ] && no_set ;;
      4) fresh; ${pkgs.t3code}/bin/t3 theme clear --base-dir "$t3home"
         : > "$T3_CALLS"; source_entry ${regular}; no_set && [ -f "$marker" ] &&
         [ -z "$(choice)" ] ;;
      5) rm "$theme"; source_entry ${regular}; published && no_set &&
           [ ! -e "$palette" ] && [ ! -e "$marker" ] ;;
      6) mkdir -p "$(dirname "$palette")"; printf '%s\n' '{"old":true}' > "$palette"
         sed -i 's/"accent": "#336699"/"accent": "{{ accent }}"/' "$theme"
         source_entry ${regular}; published && no_set && [ ! -e "$marker" ] &&
           grep -Fq '"old":true' "$palette" ;;
      6b) mkdir -p "$(dirname "$palette")"; cp "$theme" "$palette"
          export FIXTURE_PUBLISH_FAIL=1; source_entry ${regular}; published && no_set && [ ! -e "$marker" ] ;;
      7) mkdir -p "$(dirname "$settings")"; printf '{' > "$settings"
         source_entry ${regular} 2> "$TMPDIR/warning"; no_set && [ ! -e "$marker" ] &&
           grep -Fq 'nixarchy: T3 Code:' "$TMPDIR/warning" ;;
      8) printf '%s\n' blocked > "$t3home"
         source_entry ${regular} 2> "$TMPDIR/warning"; no_set && ! published &&
           grep -Fq 'nixarchy: T3 Code:' "$TMPDIR/warning" ;;
      9) [ ! -e "$(dirname "$marker")" ]; fresh ;;
      10) t3home="$HOME/my t3"; settings=$t3home/userdata/settings.json
          palette=$t3home/userdata/themes/omarchy.json
          source_entry ${spaced}; published && cmp -s "$theme" "$palette" &&
            [ "$(choice)" = omarchy ] && [ -f "$marker" ] && [ "$(set_calls)" -eq 1 ] ;;
      # The marker's parent exists, so only run's dry-run guard keeps the marker away.
      11) mkdir -p "$(dirname "$palette")" "$(dirname "$marker")"; cp "$theme" "$palette"
          export DRY_RUN=1; source_entry ${regular}; no_set && [ ! -e "$marker" ] &&
            [ ! -e "$settings" ] && [ -z "$(find "$t3home/userdata" -type f ! -name omarchy.json -print)" ] ;;
      12) start=$(date +%s); source_entry ${sleepy}; elapsed=$(( $(date +%s) - start ))
          [ "$elapsed" -le 40 ] && [ ! -e "$marker" ] &&
            grep -Fq 't3 theme set omarchy --base-dir ' "$T3_CALLS" ;;
    esac
  '';
in
pkgs.runCommand "nixarchy-t3code-theme"
  {
    nativeBuildInputs = [
      pkgs.bash
      pkgs.coreutils
      pkgs.diffutils
      pkgs.findutils
      pkgs.gettext
      pkgs.gnugrep
      pkgs.gnused
      pkgs.jq
    ];
  }
  ''
    set -eu -o pipefail
    failures=0
    for n in 1 2 3 4 5 6 6b 7 8 9 10 11 12; do
      case "$n" in
        1) name='fresh home' ;;
        2) name='second run' ;;
        3) name='user theme kept' ;;
        4) name='cleared theme stays clear' ;;
        5) name='missing source' ;;
        6) name='stale palette' ;;
        6b) name='failed publisher' ;;
        7) name='malformed settings' ;;
        8) name='blocked profile' ;;
        9) name='missing marker parent' ;;
        10) name='profile path with space' ;;
        11) name='dry run' ;;
        12) name='hung T3 Code' ;;
      esac
      if timeout 120 bash ${cases} "$n" > "$TMPDIR/case-$n.log" 2>&1; then
        echo "PASS  $n $name"
      else
        echo "FAIL  $n $name: $(tail -1 "$TMPDIR/case-$n.log")" >&2
        cat "$TMPDIR/case-$n.log" >&2
        failures=$((failures + 1))
      fi
    done
    [ "$failures" -eq 0 ]
    touch "$out"
  ''
