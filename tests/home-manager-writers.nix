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
    touch "$out"
  ''
