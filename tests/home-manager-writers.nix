{ inputs, pkgs }:
let
  home =
    (inputs.home-manager.lib.homeManagerConfiguration {
      inherit pkgs;
      extraSpecialArgs.osConfig.programs.nixarchy = {
        languageServer = true;
        nixdSettings = { };
        apps.zed.enable = true;
        apps.helix.enable = true;
        localAi = {
          enable = true;
          agents = [
            "opencode"
            "pi"
          ];
          model = "fixture-model";
          contextWindow = 32768;
          resolved.endpoint = "http://127.0.0.1:11434/v1";
        };
      };
      modules = [
        inputs.self.homeManagerModules.nixarchy
        {
          home = {
            username = "someone";
            homeDirectory = "/build/hm-writers-home";
            stateVersion = "25.05";
          };
          programs.nixarchy.enable = true;
        }
      ];
    }).config;
  zed = pkgs.writeText "nixarchy-zed-activation" home.home.activation.nixarchyNixdZed.data;
  helix = pkgs.writeText "nixarchy-helix-activation" home.home.activation.nixarchyNixdHelix.data;
  opencode = pkgs.writeText "nixarchy-opencode-provider-activation" home.home.activation.nixarchyOpencodeProvider.data;
  pi = pkgs.writeText "nixarchy-pi-provider-activation" home.home.activation.nixarchyPiProvider.data;
in
pkgs.runCommand "nixarchy-home-manager-writers"
  {
    nativeBuildInputs = [
      pkgs.coreutils
      pkgs.gnugrep
      pkgs.jq
    ];
  }
  ''
    set -eu
    home=/build/hm-writers-home
    export HOME=$home
    zed_settings=$home/.config/zed/settings.json
    helix_settings=$home/.config/helix/languages.toml
    mkdir -p "$(dirname "$zed_settings")" "$(dirname "$helix_settings")"
    run() { "$@"; }
    fail() { echo "FAIL: $1" >&2; exit 1; }

    printf '{"existing":true}\n' > "$zed_settings"
    . ${zed}
    jq -e '.existing == true and .lsp.nixd.initialization_options != null' "$zed_settings" >/dev/null || fail "plain JSON did not merge nixd"
    echo "Home Manager writer merged plain JSON"

    printf '{\n  // keep this comment\n  "existing": true,\n}\n' > "$zed_settings"
    cp "$zed_settings" before-jsonc
    . ${zed} > jsonc.log 2>&1 || fail "JSONC stopped activation"
    cmp -s before-jsonc "$zed_settings" || fail "JSONC settings changed"
    grep -Fq 'not plain JSON' jsonc.log || fail "JSONC skip lacked a reason"
    grep -Fq 'manually' jsonc.log || fail "JSONC skip lacked manual guidance"
    echo "Home Manager writer left JSONC intact with guidance"

    printf '{"managed":true}\n' > "$home/zed-target"
    rm "$zed_settings"
    ln -s "$home/zed-target" "$zed_settings"
    link_inode=$(stat -c %i "$zed_settings")
    target_inode=$(stat -c %i "$home/zed-target")
    . ${zed} > zed-link.log 2>&1 || fail "Zed symlink stopped activation"
    test -L "$zed_settings" && test "$(stat -c %i "$zed_settings")" = "$link_inode" || fail "Zed settings symlink was replaced"
    test "$(stat -c %i "$home/zed-target")" = "$target_inode" && grep -Fxq '{"managed":true}' "$home/zed-target" || fail "Zed symlink target changed"
    grep -Fq 'Home Manager' zed-link.log || fail "Zed symlink skip lacked guidance"
    echo "Home Manager writer preserved JSON symlink and target"

    printf '[editor]\nline-number = "relative"\n' > "$helix_settings"
    . ${helix}
    grep -Fq '[language-server.nixd]' "$helix_settings" || fail "plain TOML did not append nixd"
    grep -Fq 'line-number = "relative"' "$helix_settings" || fail "plain TOML lost an existing setting"
    echo "Home Manager writer appended plain TOML"

    printf 'target\n' > "$home/helix-target"
    cp "$home/helix-target" before-helix-target
    rm "$helix_settings"
    ln -s "$home/helix-target" "$helix_settings"
    link_inode=$(stat -c %i "$helix_settings")
    target_inode=$(stat -c %i "$home/helix-target")
    . ${helix} > helix-link.log 2>&1 || fail "Helix symlink stopped activation"
    test -L "$helix_settings" && test "$(stat -c %i "$helix_settings")" = "$link_inode" || fail "Helix settings symlink was replaced"
    test "$(stat -c %i "$home/helix-target")" = "$target_inode" && cmp -s before-helix-target "$home/helix-target" || fail "Helix symlink target changed"
    grep -Fq 'Home Manager' helix-link.log || fail "Helix symlink skip lacked guidance"
    echo "Home Manager writer preserved TOML symlink and target"

    opencode_settings=$home/.config/opencode/opencode.json
    pi_settings=$home/.pi/agent/models.json
    mkdir -p "$(dirname "$opencode_settings")" "$(dirname "$pi_settings")"
    printf '{"existing":true}\n' > "$opencode_settings"
    . ${opencode}
    jq -e '.existing == true and .provider.ollama.models."fixture-model" != null' "$opencode_settings" >/dev/null || fail "plain opencode JSON did not merge the local model"
    printf '{"existing":true}\n' > "$pi_settings"
    . ${pi}
    jq -e '.existing == true and .providers.ollama.models[0].id == "fixture-model"' "$pi_settings" >/dev/null || fail "plain pi JSON did not merge the local model"
    echo "Home Manager writer merged both local-model providers"

    printf '{"managed":true}\n' > "$home/opencode-target"
    cp "$home/opencode-target" before-opencode-target
    rm "$opencode_settings"
    ln -s "$home/opencode-target" "$opencode_settings"
    link_inode=$(stat -c %i "$opencode_settings")
    . ${opencode} > opencode-link.log 2>&1 || fail "opencode symlink stopped activation"
    test -L "$opencode_settings" && test "$(stat -c %i "$opencode_settings")" = "$link_inode" || fail "opencode provider symlink was replaced"
    cmp -s before-opencode-target "$home/opencode-target" || fail "opencode provider target changed"
    grep -Fq 'Home Manager' opencode-link.log || fail "opencode symlink skip lacked guidance"
    echo "Home Manager writer preserved opencode provider symlink and target"

    printf '{"managed":true}\n' > "$home/pi-target"
    cp "$home/pi-target" before-pi-target
    rm "$pi_settings"
    ln -s "$home/pi-target" "$pi_settings"
    link_inode=$(stat -c %i "$pi_settings")
    . ${pi} > pi-link.log 2>&1 || fail "pi symlink stopped activation"
    test -L "$pi_settings" && test "$(stat -c %i "$pi_settings")" = "$link_inode" || fail "pi provider symlink was replaced"
    cmp -s before-pi-target "$home/pi-target" || fail "pi provider target changed"
    grep -Fq 'Home Manager' pi-link.log || fail "pi symlink skip lacked guidance"
    echo "Home Manager writer preserved pi provider symlink and target"
    touch "$out"
  ''
