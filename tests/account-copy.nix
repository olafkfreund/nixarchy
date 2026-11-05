{ pkgs, omarchy }:
# #1616: the sandbox has no envfs, so the unedited receiver here IS a destination
# without it. Running it at all means rewriting the interpreters, which skips what
# could break, so the working case is in checks.session.
pkgs.runCommand "nixarchy-account-copy"
  {
    nativeBuildInputs = [
      pkgs.bash
      pkgs.coreutils
      pkgs.findutils
      pkgs.gnugrep
      pkgs.gnused
      pkgs.python3
    ];
  }
  ''
    fails=0
    bad() { echo "  FAILED  $1"; fails=$((fails + 1)); }
    # HOME alone is not isolation: the account state reads XDG_STATE_HOME first.
    as_home() {
      h=$1; shift
      env HOME="$h" XDG_CONFIG_HOME="$h/.config" XDG_DATA_HOME="$h/.local/share" \
        XDG_STATE_HOME="$h/.local/state" XDG_CACHE_HOME="$h/.cache" "$@"
    }
    empty() { test -z "$(find "$1" -type f)"; }

    export OMARCHY_PATH=${omarchy}/share/omarchy
    mkdir -p stub src a b c
    for n in omarchy-notification-send omarchy-agent-usage-update omarchy-i18n; do
      printf '%s\n' '#!/bin/sh' 'exit 0' > stub/$n
    done
    chmod +x stub/*
    export PATH=$PWD/stub:${omarchy}/share/omarchy/bin:$PATH

    # A login made through the shipped state commands, on the sending side.
    pending=$(as_home "$PWD/src" omarchy-agent-account-state begin claude work)
    printf '%s\n' '{"oauthAccount":{"accountUuid":"u-1616","emailAddress":"copy@example.org"}}' > "$pending/.claude.json"
    printf '%s\n' '{"claudeAiOauth":{"rateLimitTier":"","subscriptionType":"fake-1616"}}' > "$pending/.credentials.json"
    as_home "$PWD/src" omarchy-agent-account-state register claude work "$pending" >/dev/null
    as_home "$PWD/src" omarchy-agent-account-transfer bundle claude > bundle.json
    cmd=$(as_home "$PWD/src" omarchy-agent-account-transfer receiver-command)

    # Before any rewrite: with a broken export, an empty command exits 0 with 0
    # files on every leg, and a changed path makes the rewrite do nothing.
    [[ $cmd == */bin/bash* ]] || bad 'the receiver does not name /bin/bash'
    [[ $cmd == */usr/bin/python3* ]] || bad 'the receiver does not name /usr/bin/python3'
    rewritten=$(printf '%s\n' "$cmd" | sed -e 's#/bin/bash#bash#' -e 's#/usr/bin/python3#python3#')

    # Leg A: no envfs. A builder with /bin/bash would be testing something else.
    test ! -e /bin/bash || bad 'leg A: this builder has /bin/bash, so it has no no-envfs case'
    rc=0; as_home "$PWD/a" sh -c "$cmd" < bundle.json > a.out 2> a.err || rc=$?
    test "$rc" -eq 127 || bad "leg A: exit $rc, wanted 127: $(cat a.err)"
    grep -qF /bin/bash a.err || bad "leg A: stderr does not name /bin/bash: $(cat a.err)"
    empty a || bad 'leg A: a file was written'

    # Leg B: the receiver is installed and OMARCHY_PATH is not set.
    rc=0; as_home "$PWD/b" env -u OMARCHY_PATH sh -c "$rewritten" < bundle.json > b.out 2> b.err || rc=$?
    test "$rc" -eq 1 || bad "leg B: exit $rc, wanted 1: $(cat b.err)"
    grep -qF 'destination account backend is unavailable' b.err || bad "leg B: wrong reason: $(cat b.err)"
    empty b || bad 'leg B: a file was written'

    # Leg C, the control: without it, B could be failing on a bad fixture.
    rc=0; as_home "$PWD/c" sh -c "$rewritten" < bundle.json > c.out 2> c.err || rc=$?
    test "$rc" -eq 0 || bad "leg C: exit $rc, wanted 0: $(cat c.err)"
    grep -qF 'Claude: copied' c.out || bad "leg C: no copy reported: $(cat c.out)"
    accounts=c/.local/state/omarchy/agents/accounts
    grep -qF fake-1616 "$accounts/claude/work/.credentials.json" || bad 'leg C: the credential did not arrive'
    for f in claude.json claude/work/.credentials.json claude/work/.claude.json; do
      mode=$(stat -c %a "$accounts/$f") || mode=missing
      test "$mode" = 600 || bad "leg C: $f has mode $mode, wanted 600"
    done

    test "$fails" -eq 0
    echo "account-copy: every leg passed"
    touch $out
  ''
