{ inputs, pkgs }:
let
  home =
    (inputs.home-manager.lib.homeManagerConfiguration {
      inherit pkgs;
      extraSpecialArgs.osConfig.programs.nixarchy = {
        mcp = true;
        localAi = {
          enable = true;
          agents = [
            "opencode"
            "pi"
          ];
          model = "test-model";
          contextWindow = 4096;
          resolved.endpoint = "http://127.0.0.1:11434";
        };
      };
      modules = [
        inputs.self.homeManagerModules.nixarchy
        {
          home = {
            username = "tester";
            homeDirectory = "/build/home";
            stateVersion = "25.05";
          };
          programs.nixarchy.enable = true;
        }
      ];
    }).config;
  script = name: pkgs.writeText "activation-${name}.sh" home.home.activation.${name}.data;
  merge = script "nixarchyMcpClaude";
  append = script "nixarchyMcpCodex";
  opencode = script "nixarchyOpencodeProvider";
  pi = script "nixarchyPiProvider";
in
pkgs.runCommand "home-writers-dry-run" { nativeBuildInputs = [ pkgs.jq ]; } ''
  export HOME=/build/home XDG_CONFIG_HOME=/build/home/.config TMPDIR=$PWD/tmp
  mkdir -p "$HOME/.codex" "$HOME/.config/opencode" "$HOME/.pi/agent" "$TMPDIR"
  printf '%s\n' '{"keep":1}' > "$HOME/.claude.json"
  printf '%s\n' '[mine]' 'value = 1' > "$HOME/.codex/config.toml"
  printf '%s\n' '{"keep":2}' > "$HOME/.config/opencode/opencode.json"
  printf '%s\n' '{"keep":3}' > "$HOME/.pi/agent/models.json"
  for f in "$HOME/.claude.json" "$HOME/.codex/config.toml" \
           "$HOME/.config/opencode/opencode.json" "$HOME/.pi/agent/models.json"; do
    cp "$f" "$f.before"
  done

  source ${inputs.home-manager}/lib/bash/home-manager.sh
  export DRY_RUN=1
  { source ${merge}; source ${append}; source ${opencode}; source ${pi}; } > dry.out 2>&1
  for f in "$HOME/.claude.json" "$HOME/.codex/config.toml" \
           "$HOME/.config/opencode/opencode.json" "$HOME/.pi/agent/models.json"; do
    cmp "$f.before" "$f" || { echo "FAIL: dry run changed $f" >&2; exit 1; }
  done
  [ -z "$(find "$TMPDIR" -mindepth 1 -print -quit)" ] || { echo 'FAIL: dry run created a temp file' >&2; exit 1; }
  [ "$(grep -c 'nixarchy: would ' dry.out)" -eq 4 ] || { echo 'FAIL: dry run did not name four skipped writes' >&2; exit 1; }
  echo 'Home Manager dry run left all four writer destinations unchanged'

  unset DRY_RUN
  source ${merge} > live.out 2>&1
  jq -e '.keep == 1 and .mcpServers.nixos' "$HOME/.claude.json" >/dev/null || { echo 'FAIL: live JSON merge lost existing data' >&2; exit 1; }
  source ${append} >> live.out 2>&1
  grep -F '[mcp_servers.nixos]' "$HOME/.codex/config.toml" >/dev/null || { echo 'FAIL: live TOML append missing' >&2; exit 1; }
  printf '%s\n' 'invalid json' > "$HOME/.claude.json"
  source ${merge} > malformed.out 2>&1
  grep -F 'could not merge' malformed.out >/dev/null || { echo 'FAIL: malformed JSON was not diagnosed' >&2; exit 1; }
  [ "$(cat "$HOME/.claude.json")" = 'invalid json' ] || { echo 'FAIL: malformed JSON was changed' >&2; exit 1; }
  echo 'Home Manager live merge and non-fatal malformed input passed'
  touch "$out"
''
