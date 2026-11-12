{ pkgs, ... }:
let
  shipped = pkgs.nixarchy-omarchy or pkgs.omarchy;
  isEdge = pkgs.lib.hasPrefix "edge-" shipped.version;
  header = "<!-- Your instructions for every coding agent. Omarchy links this file into each agent harness (Claude Code, Codex, Pi, OpenCode, and the rest), so what you write here applies to all of them. -->";
  storeHeader = pkgs.writeText "agent-instructions-header" "${header}\n";
  storeOther = pkgs.writeText "agent-instructions-other" "other rules\n";
  storeBindings = pkgs.writeText "agent-instructions-bindings" "  o.bind(\"SUPER + CTRL + X\", \"Toggle dictation\", \"omarchy-dictation toggle\")\n";
  storeDir = pkgs.runCommand "agent-instructions-empty-dir" { } "mkdir -p $out";
  migrations = shipped.passthru.userMigrations;
in
pkgs.runCommand "nixarchy-agent-instructions"
  {
    nativeBuildInputs = [
      pkgs.bash
      pkgs.coreutils
      pkgs.gnugrep
      pkgs.gnused
    ];
    package = "${shipped}/share/omarchy";
    migration = "${migrations}/scripts/1794387387.sh";
  }
  ''
    set -euo pipefail
    ${
      if isEdge then
        ''
          root=$PWD
          export HOME=$root/home XDG_CONFIG_HOME=$root/home/.config
          mkdir -p "$root/bin"
          export PATH=$root/bin:$PATH LOG=$root/calls
          instructions=$package/bin/omarchy-agent-instructions
          default_agent=$package/bin/omarchy-default-agent
          fail() { echo "FAILED $1" >&2; exit 1; }
          reset_home() { rm -rf "$HOME"; mkdir -p "$HOME/.agents" "$XDG_CONFIG_HOME"; }
          printf '%s\n' '#!${pkgs.bash}/bin/bash' 'printf "editor %s\n" "$1" >> "$LOG"' > "$root/bin/omarchy-launch-config-editor"
          printf '%s\n' '#!${pkgs.bash}/bin/bash' 'exit 0' > "$root/bin/omarchy-notification-send"
          printf '%s\n' '#!${pkgs.bash}/bin/bash' 'echo backed-up' > "$root/bin/omarchy-i18n"
          printf '%s\n' '#!${pkgs.bash}/bin/bash' 'echo "$PATH"' > "$root/bin/omarchy-agent-real-path"
          chmod +x "$root/bin"/*

          for fixture in ${storeHeader} ${storeOther}; do
            reset_home
            ln -s ${storeHeader} "$HOME/.agents/AGENTS.md"
            mkdir -p "$HOME/.claude"
            ln -s "$fixture" "$HOME/.claude/CLAUDE.md"
            bash "$instructions" claude >out 2>err || fail "HM Claude $(basename "$fixture") status"
            [[ -L $HOME/.claude/CLAUDE.md && $(readlink "$HOME/.claude/CLAUDE.md") == "$fixture" ]] || fail "HM Claude $(basename "$fixture") link"
            [[ $(readlink "$HOME/.agents/AGENTS.md") == ${storeHeader} ]] || fail "HM Claude $(basename "$fixture") shared link"
          done

          reset_home
          ln -s ${storeHeader} "$HOME/.agents/AGENTS.md"
          mkdir -p "$HOME/.codex"
          printf 'my rules\n' > "$HOME/.codex/AGENTS.md"
          bash "$instructions" codex >out 2>err || fail 'HM shared status'
          [[ $(readlink "$HOME/.agents/AGENTS.md") == ${storeHeader} ]] || fail 'HM shared link'
          [[ -L $HOME/.codex/AGENTS.md && $(readlink "$HOME/.codex/AGENTS.md") == "$HOME/.agents/AGENTS.md" ]] || fail 'HM Codex link'
          [[ $(cat "$HOME/.codex/AGENTS.md.bak") == 'my rules' ]] || fail 'HM Codex backup'

          reset_home
          ln -s ${storeHeader} "$HOME/.agents/AGENTS.md"
          mkdir -p "$HOME/.codex"
          cp ${storeHeader} "$HOME/.codex/AGENTS.md"
          bash "$instructions" codex >out 2>err || fail 'HM identical Codex status'
          [[ -L $HOME/.codex/AGENTS.md && $(readlink "$HOME/.codex/AGENTS.md") == "$HOME/.agents/AGENTS.md" ]] || fail 'HM identical Codex link'
          [[ ! -e $HOME/.codex/AGENTS.md.bak ]] || fail 'HM identical Codex backup'

          reset_home
          ln -s ${storeHeader} "$HOME/.agents/AGENTS.md"
          ln -s ${storeDir} "$XDG_CONFIG_HOME/opencode"
          bash "$instructions" opencode >out 2>err || fail 'HM OpenCode directory status'
          [[ -L $XDG_CONFIG_HOME/opencode && $(readlink "$XDG_CONFIG_HOME/opencode") == ${storeDir} ]] || fail 'HM OpenCode directory link'

          reset_home
          ln -s ${storeHeader} "$HOME/.agents/AGENTS.md"
          rm -f "$LOG"
          bash "$instructions" --edit >out 2>err || fail 'HM edit status'
          [[ ! -e $LOG ]] || fail 'HM edit called editor'
          grep -qF 'Home Manager' err || fail 'HM edit message'

          reset_home
          rm -rf "$HOME/.agents"
          ln -s ${storeDir} "$HOME/.agents"
          mkdir -p "$HOME/.codex"
          printf 'my rules\n' > "$HOME/.codex/AGENTS.md"
          rm -f "$LOG"
          bash "$instructions" --edit >out 2>err || fail 'HM missing edit status'
          [[ $(cat "$HOME/.codex/AGENTS.md") == 'my rules' ]] || fail 'HM missing edit Codex content'
          [[ ! -e $HOME/.codex/AGENTS.md.bak && ! -L $HOME/.codex/AGENTS.md.bak ]] || fail 'HM missing edit Codex backup'
          [[ ! -e $LOG ]] || fail 'HM missing edit called editor'
          grep -qF 'Home Manager' err || fail 'HM missing edit message'

          reset_home
          mkdir -p "$TMPDIR/dotfiles"
          ln -s "$TMPDIR/dotfiles/AGENTS.md" "$HOME/.agents/AGENTS.md"
          mkdir -p "$HOME/.codex"
          printf 'my rules\n' > "$HOME/.codex/AGENTS.md"
          rm -f "$LOG"
          bash "$instructions" --edit >out 2>err || fail 'dangling dotfiles edit status'
          grep -qxF "editor $HOME/.agents/AGENTS.md" "$LOG" || fail 'dangling dotfiles editor path'
          [[ $(cat "$HOME/.codex/AGENTS.md") == 'my rules' ]] || fail 'dangling dotfiles Codex content'
          [[ ! -e $HOME/.codex/AGENTS.md.bak && ! -L $HOME/.codex/AGENTS.md.bak ]] || fail 'dangling dotfiles Codex backup'

          reset_home
          bash "$instructions" claude >out 2>err || fail 'regular home status'
          [[ $(cat "$HOME/.agents/AGENTS.md") == '${header}' ]] || fail 'regular home header'
          [[ -L $HOME/.claude/CLAUDE.md && $(readlink "$HOME/.claude/CLAUDE.md") == "$HOME/.agents/AGENTS.md" ]] || fail 'regular home Claude link'

          reset_home
          mkdir -p "$HOME/.config/omarchy/defaults"
          echo codex > "$HOME/.config/omarchy/defaults/agent"
          printf '%s\n' '#!${pkgs.bash}/bin/bash' 'exit 0' > "$root/bin/codex"
          printf '%s\n' '#!${pkgs.bash}/bin/bash' 'echo "instructions $*" >> "$LOG"' > "$root/bin/omarchy-agent-instructions"
          printf '%s\n' '#!${pkgs.bash}/bin/bash' 'echo agent >> "$LOG"' > "$root/bin/omarchy-agent"
          chmod +x "$root/bin/codex" "$root/bin/omarchy-agent-instructions" "$root/bin/omarchy-agent"
          rm -f "$LOG"
          bash "$default_agent" codex >out 2>err || fail 'default agent setter status'
          grep -qxF 'instructions codex' "$LOG" || fail 'default agent instructions call'
          grep -qxF 'agent' "$LOG" || fail 'default agent launch'

          reset_home
          bindings=$HOME/.config/hypr/bindings.lua
          mkdir -p "$(dirname "$bindings")"
          cp ${storeBindings} "$bindings"
          bash "$migration" >out 2>err || fail 'dictation regular status'
          grep -qxF '  o.rebind("SUPER + CTRL + X", "Toggle dictation", "omarchy-dictation toggle")' "$bindings" || fail 'dictation regular rebind'
          rm "$bindings"
          ln -s ${storeBindings} "$bindings"
          bash "$migration" >out 2>err || fail 'dictation store status'
          [[ -L $bindings && $(readlink "$bindings") == ${storeBindings} ]] || fail 'dictation store link'
          grep -qxF '  o.bind("SUPER + CTRL + X", "Toggle dictation", "omarchy-dictation toggle")' "$bindings" || fail 'dictation store content'
        ''
      else
        "echo 'SKIP agent-instructions: edge-only command and migrations on this pin'"
    }
    touch "$out"
  ''
