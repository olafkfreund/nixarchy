{ pkgs, ... }:
# Home Manager directory links survive quattro's user-file scripts (#1304, #1760).
let
  shipped = pkgs.nixarchy-omarchy or pkgs.omarchy;
  isEdge = pkgs.lib.hasPrefix "edge-" shipped.version;
  migrations = shipped.passthru.userMigrations;
  header = "<!-- Your instructions for every coding agent. Omarchy links this file into each agent harness (Claude Code, Codex, Pi, OpenCode, and the rest), so what you write here applies to all of them. -->";

  claudeDir = pkgs.writeTextDir "CLAUDE.md" "${header}\n";
  agentsDir = pkgs.writeTextDir "AGENTS.md" "${header}\n";
  emptyAgentsDir = pkgs.runCommand "nixarchy-empty-agents-dir" { } "mkdir -p $out";
  hyprDir = pkgs.writeTextDir "bindings.lua" "  o.bind(\"SUPER + CTRL + X\", \"Toggle dictation\", \"omarchy-dictation toggle\")\n";
  qtengineDir = pkgs.writeTextDir "config.json" ''{"theme":{"iconTheme":"Yaru-blue"}}'';
  configDir = pkgs.writeTextDir "mimeapps.list" "[Default Applications]\ntext/plain=kate.desktop\n";
in
pkgs.runCommand "nixarchy-home-links-quattro"
  {
    nativeBuildInputs = [
      pkgs.bash
      pkgs.coreutils
      pkgs.diffutils
      pkgs.findutils
      pkgs.gawk
      pkgs.gnugrep
      pkgs.gnused
      pkgs.jq
      pkgs.xdg-utils
    ];
  }
  (
    if !isEdge then
      ''
        echo "SKIP home-links-quattro: edge pin only"
        touch "$out"
      ''
    else
      ''
        set -euo pipefail
        export LC_ALL=C

        export HOME=$TMPDIR/home
        export XDG_CONFIG_HOME=$HOME/.config
        export XDG_DATA_HOME=$HOME/.local/share
        export XDG_STATE_HOME=$HOME/.local/state
        export XDG_CACHE_HOME=$HOME/.cache
        export XDG_CONFIG_DIRS=$TMPDIR/xdg-config
        export XDG_DATA_DIRS=$TMPDIR/xdg-data
        export OMARCHY_PATH=${shipped}/share/omarchy

        mkdir -p "$TMPDIR/bin" "$XDG_CONFIG_DIRS" "$XDG_DATA_DIRS/applications"
        export PATH=$TMPDIR/bin:$PATH

        printf '%s\n' '[Desktop Entry]' 'Type=Application' 'Name=Chromium' 'Exec=chromium %U' > "$XDG_DATA_DIRS/applications/chromium-browser.desktop"
        printf '%s\n' '[Desktop Entry]' 'Type=Application' 'Name=Firefox' 'Exec=firefox %u' > "$XDG_DATA_DIRS/applications/firefox.desktop"
        printf '%s\n' '[MIME Cache]' 'x-scheme-handler/http=firefox.desktop;chromium-browser.desktop;' > "$XDG_DATA_DIRS/applications/mimeinfo.cache"
        cp --no-preserve=mode "${shipped}/share/applications/omarchy-HEY.desktop" "$XDG_DATA_DIRS/applications/omarchy-HEY.desktop"

        for command in omarchy-notification-send omarchy-launch-config-editor chromium firefox; do
          printf '%s\n' '#!${pkgs.bash}/bin/bash' 'exit 0' > "$TMPDIR/bin/$command"
        done
        printf '%s\n' '#!${pkgs.bash}/bin/bash' 'echo backed-up' > "$TMPDIR/bin/omarchy-i18n"
        printf '%s\n' '#!${pkgs.bash}/bin/bash' 'echo dark' > "$TMPDIR/bin/omarchy-theme-color"
        chmod +x "$TMPDIR/bin/"*

        fails=()
        fail() {
          echo "FAILED $1: $2" >&2
          fails+=("$1: $2")
        }

        reset_home() {
          rm -rf "$HOME"
          mkdir -p "$XDG_CONFIG_HOME" "$XDG_DATA_HOME" "$XDG_STATE_HOME" "$XDG_CACHE_HOME"
        }

        snapshot() {
          find "$HOME" -printf '%y %p %l\n' | sort
          find -L "$HOME" -printf '%y %p %l\n' | sort
          find -L "$HOME" -type f -print0 | sort -z | xargs -0 -r sha256sum
        }

        run_unchanged() {
          local name=$1
          shift
          snapshot > "$TMPDIR/before"
          local rc=0
          "$@" > "$TMPDIR/$name.out" 2> "$TMPDIR/$name.err" || rc=$?
          snapshot > "$TMPDIR/after"
          if (( rc != 0 )); then
            fail "$name" "exited $rc"
          fi
          if ! diff -u "$TMPDIR/before" "$TMPDIR/after" > "$TMPDIR/$name.diff"; then
            cat "$TMPDIR/$name.diff" >&2
            fail "$name" "home snapshot changed"
          fi
        }

        # 1. ~/.claude a link to a store dir holding CLAUDE.md.
        reset_home
        mkdir -p "$HOME/.agents"
        printf '%s\n' '${header}' > "$HOME/.agents/AGENTS.md"
        ln -s ${claudeDir} "$HOME/.claude"
        run_unchanged "claude-dir" bash "$OMARCHY_PATH/bin/omarchy-agent-instructions" claude

        # 2. ~/.agents a link to a store dir holding AGENTS.md (header only), plus a regular ~/.codex/AGENTS.md.
        reset_home
        ln -s ${agentsDir} "$HOME/.agents"
        mkdir -p "$HOME/.codex"
        printf 'my rules\n' > "$HOME/.codex/AGENTS.md"
        rc=0
        bash "$OMARCHY_PATH/bin/omarchy-agent-instructions" codex > "$TMPDIR/agents-dir.out" 2> "$TMPDIR/agents-dir.err" || rc=$?
        (( rc == 0 )) || fail "agents-dir" "exited $rc"
        [[ -L $HOME/.agents && $(readlink "$HOME/.agents") == "${agentsDir}" ]] || fail "agents-dir" "~/.agents link changed"
        [[ -L $HOME/.codex/AGENTS.md && $(readlink "$HOME/.codex/AGENTS.md") == "$HOME/.agents/AGENTS.md" ]] || fail "agents-dir" "~/.codex/AGENTS.md not linked"
        [[ -f $HOME/.codex/AGENTS.md.bak && $(<"$HOME/.codex/AGENTS.md.bak") == "my rules" ]] || fail "agents-dir" "~/.codex/AGENTS.md.bak wrong or missing"

        reset_home
        ln -s ${emptyAgentsDir} "$HOME/.agents"
        mkdir -p "$HOME/.codex"
        printf 'my rules\n' > "$HOME/.codex/AGENTS.md"
        run_unchanged "agents-dir-missing-shared" bash "$OMARCHY_PATH/bin/omarchy-agent-instructions" codex
        grep -qxF '~/.agents/AGENTS.md is managed elsewhere and does not exist; no harness was linked' "$TMPDIR/agents-dir-missing-shared.err" || fail "agents-dir-missing-shared" "missing explanation"

        # 3. XDG_CONFIG_HOME/hypr a link to a store dir holding bindings.lua with the legacy line.
        reset_home
        ln -s ${hyprDir} "$XDG_CONFIG_HOME/hypr"
        run_unchanged "hypr-dir-1794387387" bash "${migrations}/scripts/1794387387.sh"

        # 4. XDG_CONFIG_HOME/qtengine a link to a store dir holding config.json (Yaru-blue).
        reset_home
        ln -s ${qtengineDir} "$XDG_CONFIG_HOME/qtengine"
        run_unchanged "qtengine-dir-set-qt" bash "$OMARCHY_PATH/bin/omarchy-theme-set-qt"

        reset_home
        ln -s ${qtengineDir} "$XDG_CONFIG_HOME/qtengine"
        run_unchanged "qtengine-dir-1794397144" env DBUS_SESSION_BUS_ADDRESS=stub bash "${migrations}/scripts/1794397144.sh"

        # 5. XDG_CONFIG_HOME itself a link to a store dir holding mimeapps.list (text/plain line).
        reset_home
        rmdir "$XDG_CONFIG_HOME"
        ln -s ${configDir} "$XDG_CONFIG_HOME"
        run_unchanged "config-dir-editor-unless-chosen" bash "$OMARCHY_PATH/bin/omarchy-cmd-editor-mimetypes" --unless-chosen

        reset_home
        rmdir "$XDG_CONFIG_HOME"
        ln -s ${configDir} "$XDG_CONFIG_HOME"
        run_unchanged "config-dir-editor-explicit" bash "$OMARCHY_PATH/bin/omarchy-cmd-editor-mimetypes"

        # 6. Same store-linked XDG_CONFIG_HOME with no browser line: extracted browser lines of omarchy-provision-user.
        awk '/^\. .*nixarchy-store-owned\.sh$/ { copying=1 } copying { print; if (/^[[:space:]]*xdg-mime default omarchy-HEY\.desktop/) mailto=1; else if (mailto && /^[[:space:]]*fi$/) exit }' "$OMARCHY_PATH/bin/omarchy-provision-user" > "$TMPDIR/provision-block"
        grep -q 'xdg-mime default omarchy-HEY.desktop' "$TMPDIR/provision-block" || fail "config-dir-provision-browser" "patched block missing"
        reset_home
        rmdir "$XDG_CONFIG_HOME"
        ln -s ${configDir} "$XDG_CONFIG_HOME"
        run_unchanged "config-dir-provision-browser" env BROWSER= XDG_CURRENT_DESKTOP= bash "$TMPDIR/provision-block"

        # Positive control: regular ~/.claude with no CLAUDE.md must produce a snapshot diff.
        reset_home
        mkdir -p "$HOME/.agents" "$HOME/.claude"
        printf '%s\n' '${header}' > "$HOME/.agents/AGENTS.md"
        snapshot > "$TMPDIR/before"
        rc=0
        bash "$OMARCHY_PATH/bin/omarchy-agent-instructions" claude > "$TMPDIR/pos.out" 2> "$TMPDIR/pos.err" || rc=$?
        snapshot > "$TMPDIR/after"
        (( rc == 0 )) || fail "snapshot-blind" "positive control exited $rc"
        if diff -u "$TMPDIR/before" "$TMPDIR/after" > "$TMPDIR/pos.diff"; then
          fail "snapshot-blind" "snapshot diff was empty"
        elif ! grep -q 'CLAUDE\.md' "$TMPDIR/pos.diff"; then
          fail "snapshot-blind" "CLAUDE.md did not appear in diff"
        fi

        if (( ''${#fails[@]} > 0 )); then
          exit 1
        fi
        touch "$out"
      ''
  )
