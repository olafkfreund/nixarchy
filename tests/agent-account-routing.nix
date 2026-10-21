{ pkgs, omarchy }:
# Edge carry (#1386): mise [wrappers] route a typed claude through the account
# `omarchy agent account use` selected, and the exec never mise-installs an
# agent. The wrappers file is copied only when data/etc-overlay.nix says it is
# installed, so reverting that row is what makes case 1 fail.
let
  installed =
    (import ../data/etc-overlay.nix)."mise/conf.d/omarchy-agent-accounts.toml".class == "installed";
in
pkgs.runCommand "nixarchy-agent-account-routing"
  {
    nativeBuildInputs = [
      pkgs.bash
      pkgs.coreutils
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
    export MISE_SYSTEM_CONFIG_DIR=$PWD/mise-system
    mkdir -p "$HOME" "$MISE_SYSTEM_CONFIG_DIR/conf.d"
    ${pkgs.lib.optionalString installed ''
      cp ${omarchy}/share/omarchy/etc/mise/conf.d/omarchy-agent-accounts.toml "$MISE_SYSTEM_CONFIG_DIR/conf.d/"
    ''}
    # Stands in for home.activation.nixarchyAgentWrappers, which builds the dispatch links.
    mise reshim

    # no claude here: case 4 runs with only this on PATH
    mkdir -p stub withclaude
    for n in omarchy-notification-send omarchy-agent-usage-update omarchy-i18n; do
      printf '%s\n' '#!/bin/sh' 'exit 0' > stub/$n
    done
    printf '%s\n' '#!/bin/sh' 'echo claude' > stub/omarchy-default-agent
    printf '%s\n' '#!/bin/sh' 'echo "CFG=''${CLAUDE_CONFIG_DIR-unset} PIN=''${OMARCHY_AGENT_CLAUDE_HOME-unset}"' > withclaude/claude
    chmod +x stub/* withclaude/*
    base=$PWD/stub:${omarchy}/share/omarchy/bin:$PATH
    export PATH=$base:$PWD/withclaude

    # What an activated interactive shell does before the user types a command.
    run_in_shell() {
      bash -c 'eval "$(mise hook-env -s bash)"; "$@"' sh "$@"
    }

    # Case 2: no accounts, implicit Main. Pinned to empty, CLAUDE_CONFIG_DIR untouched.
    got=$(run_in_shell claude 2>err) || bad "case 2: claude exited $?: $(cat err)"
    test "$got" = "CFG=unset PIN=" || bad "case 2: got '$got', wanted 'CFG=unset PIN='"

    # Case 1: an account made through the shipped state commands, then selected.
    mkdir -p "$HOME/.claude"
    pending=$(omarchy-agent-account-state begin claude work)
    printf '%s\n' '{"oauthAccount":{"accountUuid":"u-1","emailAddress":"work@example.org"}}' > "$pending/.claude.json"
    printf '%s\n' '{"claudeAiOauth":{"rateLimitTier":"","subscriptionType":"pro"}}' > "$pending/.credentials.json"
    omarchy-agent-account-state register claude work "$pending" >/dev/null || bad 'case 1: register failed'
    omarchy-agent-account-use claude work >/dev/null || bad 'case 1: use failed'
    want=$(omarchy-agent-account-home claude)
    test -n "$want" || bad 'case 1: the selected account has no home'
    got=$(run_in_shell claude 2>err) || bad "case 1: claude exited $?: $(cat err)"
    test "$got" = "CFG=$want PIN=$want" || bad "case 1: got '$got', wanted 'CFG=$want PIN=$want'"

    # Case 5: the launcher follows the account with no wrapper involved.
    got=$(env -u CLAUDE_CONFIG_DIR -u OMARCHY_AGENT_CLAUDE_HOME omarchy-agent --inline 2>err) \
      || bad "case 5: omarchy-agent exited $?: $(cat err)"
    test "$got" = "CFG=$want PIN=$want" || bad "case 5: got '$got'"

    # Case 3: the user's own wrapper wins over the system one.
    mkdir -p "$MISE_CONFIG_DIR"
    printf '%s\n' '[wrappers.claude]' 'command = "echo"' 'args = ["USER"]' > "$MISE_CONFIG_DIR/config.toml"
    got=$(run_in_shell claude 2>err) || bad "case 3: claude exited $?: $(cat err)"
    test "$got" = USER || bad "case 3: got '$got', wanted USER"
    rm "$MISE_CONFIG_DIR/config.toml"

    # Case 4: no claude on PATH. Refuse, and download nothing.
    rc=0; PATH=$base omarchy-agent-account-exec claude >out 2>err || rc=$?
    test "$rc" -eq 127 || bad "case 4: exit $rc, wanted 127"
    grep -q 'omarchy default agent claude' err || bad "case 4: stderr does not name the fix: $(cat err)"
    test ! -e "$MISE_DATA_DIR/installs" || bad 'case 4: mise installed something'

    test "$fails" -eq 0
    echo "agent-account-routing: every case passed"
    touch $out
  ''
