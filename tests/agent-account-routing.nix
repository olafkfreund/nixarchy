{ pkgs, omarchy }:
# Typed agents and their children route through the Nix dispatch directory;
# missing CLIs refuse without asking mise to install them.
pkgs.runCommand "nixarchy-agent-account-routing"
  {
    nativeBuildInputs = [
      pkgs.bash
      pkgs.coreutils
      pkgs.diffutils
      pkgs.gnugrep
      pkgs.jq
      pkgs.mise
      pkgs.python3
    ];
  }
  ''
        fails=0
        bad() { echo "  FAILED  $1"; fails=$((fails + 1)); }
        export OMARCHY_PATH=${omarchy}/share/omarchy
        export HOME=$PWD/home XDG_CONFIG_HOME=$PWD/home/.config XDG_DATA_HOME=$PWD/home/.local/share
        export XDG_STATE_HOME=$PWD/home/.local/state XDG_CACHE_HOME=$PWD/home/.cache
        export MISE_DATA_DIR=$PWD/mise-data MISE_CONFIG_DIR=$PWD/mise-config
        export MISE_STATE_DIR=$PWD/mise-state MISE_CACHE_DIR=$PWD/mise-cache
        export MISE_SYSTEM_CONFIG_DIR=$PWD/mise-system MISE_OFFLINE=1
        mkdir -p "$HOME" "$MISE_SYSTEM_CONFIG_DIR/conf.d"

        D=${omarchy}/share/omarchy/agent-dispatch
        mkdir -p stub withclaude withcodex user
        for n in omarchy-agent-usage-update omarchy-i18n omarchy-launch-floating-terminal-with-presentation omarchy-launch-tui; do
          printf '%s\n' '#!/bin/sh' 'exit 0' > stub/$n
        done
        printf '%s\n' '#!/bin/sh' 'printf "%s\n" "$*" >> "$PWD/notifications"' > stub/omarchy-notification-send
        printf '%s\n' '#!/bin/sh' 'echo claude' > stub/omarchy-default-agent
        printf '%s\n' '#!/bin/sh' 'printf "%s\n" "$*" >> "$PWD/mise-calls"' > stub/mise
        printf '%s\n' '#!/bin/sh' 'if [ "''${1:-}" = --spawn-codex ]; then codex; exit; fi' \
          'if [ "''${1:-}" = auth ] && [ "''${2:-}" = login ]; then printf "CFG=%s PIN=%s\n" "''${CLAUDE_CONFIG_DIR-unset}" "''${OMARCHY_AGENT_CLAUDE_HOME-unset}" > "$PWD/login"; exit; fi' \
          'echo "CFG=''${CLAUDE_CONFIG_DIR-unset} PIN=''${OMARCHY_AGENT_CLAUDE_HOME-unset}"' > withclaude/claude
        printf '%s\n' '#!/bin/sh' 'if [ "''${OMARCHY_TEST_CHILD:-}" = 1 ]; then echo "PIN=''${OMARCHY_AGENT_CODEX_HOME-unset}"; else OMARCHY_TEST_CHILD=1 codex; fi' > withcodex/codex
        printf '%s\n' '#!/bin/sh' 'echo USER' > user/claude
        chmod +x stub/* withclaude/* withcodex/* user/*
        base=$PWD/stub:${omarchy}/share/omarchy/bin:$PATH
        export PATH=$D:$base:$PWD/withclaude

        # Case 2: no accounts, implicit Main.
        got=$(claude 2>err) || bad "case 2: claude exited $?: $(cat err)"
        test "$got" = "CFG=unset PIN=" || bad "case 2: got '$got'"

        # Case 1: the selected account pins the typed command and its children.
        mkdir -p "$HOME/.claude"
        pending=$(omarchy-agent-account-state begin claude work)
        printf '%s\n' '{"oauthAccount":{"accountUuid":"u-1","emailAddress":"work@example.org"}}' > "$pending/.claude.json"
        printf '%s\n' '{"claudeAiOauth":{"rateLimitTier":"","subscriptionType":"pro"}}' > "$pending/.credentials.json"
        omarchy-agent-account-state register claude work "$pending" >/dev/null || bad 'case 1: register failed'
        omarchy-agent-account-use claude work >/dev/null || bad 'case 1: use failed'
        want=$(omarchy-agent-account-home claude)
        test -n "$want" || bad 'case 1: the selected account has no home'
        got=$(claude 2>err) || bad "case 1: claude exited $?: $(cat err)"
        test "$got" = "CFG=$want PIN=$want" || bad "case 1: got '$got'"

        # Case 5: the launcher follows the selected account.
        got=$(env -u CLAUDE_CONFIG_DIR -u OMARCHY_AGENT_CLAUDE_HOME omarchy-agent --inline 2>err) \
          || bad "case 5: omarchy-agent exited $?: $(cat err)"
        test "$got" = "CFG=$want PIN=$want" || bad "case 5: got '$got'"

        # Case 3: a person's own rc can put their command ahead of dispatch.
        got=$(PATH=$base:$PWD/withclaude bash -c 'source "$OMARCHY_PATH/default/bash/rc"; PATH="$PWD/user:$PATH"; claude' 2>err) \
          || bad "case 3: shell exited $?: $(cat err)"
        test "$got" = USER || bad "case 3: got '$got'"

        # Case 4: an absent CLI refuses; no mise fallback is called.
        : > mise-calls
        rc=0; PATH=$D:$base omarchy-agent-account-exec claude >out 2>err || rc=$?
        test "$rc" -eq 127 || bad "case 4: exit $rc, wanted 127"
        grep -q 'omarchy default agent claude' err || bad "case 4: stderr does not name the fix: $(cat err)"
        test ! -s mise-calls || bad 'case 4: mise was called'

        # Case 6: a child typing another provider is dispatched too.
        got=$(PATH=$D:$base:$PWD/withclaude:$PWD/withcodex claude --spawn-codex 2>err) \
          || bad "case 6: child exited $?: $(cat err)"
        test "$got" = 'PIN=' || bad "case 6: got '$got'"

        # Case 7: old and current generations cannot recurse into dispatch.
        mkdir -p old/agent-dispatch
        printf '%s\n' '#!/bin/sh' 'exit 88' > old/agent-dispatch/claude
        chmod +x old/agent-dispatch/claude
        got=$(PATH=$PWD/old/agent-dispatch:$D:$base:$PWD/withclaude timeout 10 "$D/claude" 2>err) \
          || bad "case 7: dispatch exited $?: $(cat err)"
        test "$got" = "CFG=$want PIN=$want" || bad "case 7: got '$got'"

        # Case 8: stale mise command wrappers still lose to dispatch after config removal.
        export D MISE_BIN=${pkgs.mise}/bin/mise
        cp ${omarchy}/share/omarchy/etc/mise/conf.d/omarchy-agent-accounts.toml "$MISE_SYSTEM_CONFIG_DIR/conf.d/"
        ${pkgs.mise}/bin/mise reshim || bad 'case 8: reshim failed'
        rm "$MISE_SYSTEM_CONFIG_DIR/conf.d/omarchy-agent-accounts.toml"
        got=$(PATH=$base:$PWD/withclaude bash -c 'eval "$(''${MISE_BIN} activate bash)"; PATH="$D:$PATH"; claude' 2>err) \
          || bad "case 8: shell exited $?: $(cat err)"
        test "$got" = "CFG=$want PIN=$want" || bad "case 8: got '$got'"

        # Case 9: account-add refuses a missing CLI, including its events mode.
        rc=0; PATH=$D:$base omarchy-agent-account-add --events claude >out 2>err || rc=$?
        test "$rc" -eq 1 || bad "case 9: exit $rc, wanted 1"
        grep -q 'omarchy default agent claude' out || bad 'case 9: missing fix in events output'
        test ! -s mise-calls || bad 'case 9: mise was called'

        # Case 10: the full-path default-agent command must not mistake dispatch for an installed CLI.
        rc=0; PATH=$D:$base "${omarchy}/share/omarchy/bin/omarchy-default-agent" claude >out 2>err || rc=$?
        test "$rc" -ne 0 || bad 'case 10: absent CLI was accepted'
        test ! -f "$HOME/.config/omarchy/defaults/agent" || bad 'case 10: absent CLI was recorded'

        # Case 11: a primary login clears the selected account's home first.
        rm -f login
        PATH=$D:$base:$PWD/withclaude omarchy-agent-account-add claude >out 2>err || true
        test -f login || bad 'case 11: login did not reach the CLI'
        grep -q '^CFG=unset PIN=$' login || bad "case 11: login inherited a pin: $(cat login)"

        # Case 12: the launcher carries dispatch even if its caller did not.
        printf '%s\n' codex > "$HOME/.config/omarchy/defaults/agent"
        got=$(PATH=$base:$PWD/withcodex omarchy-agent --inline 2>err) \
          || bad "case 12: launcher exited $?: $(cat err)"
        test "$got" = 'PIN=' || bad "case 12: got '$got'"

        # Case 13: the usage probe ignores dispatch, but accepts a real binary.
        mkdir -p empty-codex
        CODEX_HOME=$PWD/empty-codex PATH=$D:$base python3 -c '
    import importlib.machinery, importlib.util
    loader = importlib.machinery.SourceFileLoader("usage", "${omarchy}/share/omarchy/bin/omarchy-agent-usage-codex")
    spec = importlib.util.spec_from_loader(loader.name, loader)
    usage = importlib.util.module_from_spec(spec)
    loader.exec_module(usage)
    assert usage.find_codex_binary() is None
    assert not usage.codex_in_use({})
    ' || bad 'case 13: dispatch counted as a real binary'
        CODEX_HOME=$PWD/empty-codex PATH=$D:$base:$PWD/withcodex python3 -c '
    import importlib.machinery, importlib.util, os
    loader = importlib.machinery.SourceFileLoader("usage", "${omarchy}/share/omarchy/bin/omarchy-agent-usage-codex")
    spec = importlib.util.spec_from_loader(loader.name, loader)
    usage = importlib.util.module_from_spec(spec)
    loader.exec_module(usage)
    assert usage.find_codex_binary() == os.path.join(os.getcwd(), "withcodex", "codex")
    ' || bad 'case 13: real codex was not found'

        # Case 14: a recorded but absent agent reports itself in a notification.
        printf '%s\n' grok > "$HOME/.config/omarchy/defaults/agent"
        : > notifications
        rc=0; PATH=$D:$base omarchy-agent --inline >out 2>err || rc=$?
        test "$rc" -eq 1 || bad "case 14: exit $rc, wanted 1"
        grep -q grok notifications || bad 'case 14: notification did not name grok'

        test "$fails" -eq 0
        echo "agent-account-routing: every case passed"
        touch $out
  ''
