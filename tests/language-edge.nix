{ pkgs, omarchy }:
# Setup > Language on NixOS (#1289, edge carry): the patched omarchy-language
# run for real against stubs. A locale the system has not built is recorded
# with nixarchy-language-select and the switch stops before LANG or the
# language file changes; a built one switches as upstream does.
pkgs.runCommand "nixarchy-language-edge"
  {
    nativeBuildInputs = [
      pkgs.coreutils
      pkgs.gnugrep
      pkgs.jq
    ];
  }
  ''
    fails=0
    bad() { echo "  FAILED  $1"; fails=$((fails + 1)); }
    export OMARCHY_PATH=${omarchy}/share/omarchy
    export XDG_CONFIG_HOME=$PWD/cfg CALLS=$PWD/calls
    lang=${omarchy}/share/omarchy/bin/omarchy-language
    env_file=$XDG_CONFIG_HOME/uwsm/env.d/50-omarchy-language

    mkdir -p stub
    printf '%s\n' '#!/bin/sh' 'printf "%s\n" C C.utf8 $BUILT' > stub/locale
    printf '%s\n' '#!/bin/sh' 'echo "select $*" >> "$CALLS"' > stub/nixarchy-language-select
    printf '%s\n' '#!/bin/sh' 'echo "notify $*" >> "$CALLS"' > stub/omarchy-notification-send
    printf '%s\n' '#!/bin/sh' 'echo "$*"' > stub/omarchy-i18n
    printf '%s\n' '#!/bin/sh' 'exit 0' > stub/dbus-update-activation-environment
    chmod +x stub/*
    export PATH=$PWD/stub:$PATH

    # da_DK is not built: recorded, refused, nothing switched.
    : > "$CALLS"
    rc=0; BUILT=en_US.utf8 "$lang" da >out 2>err || rc=$?
    test "$rc" -ne 0 || bad 'a missing locale exited 0'
    grep -qx 'select da' "$CALLS" || bad 'nixarchy-language-select was not called with da'
    grep -q '^notify ' "$CALLS" || bad 'no notification for the menu'
    grep -q 'apply it' err || bad 'stderr does not say to apply'
    test ! -e "$env_file" || bad "LANG was written: $(cat "$env_file")"
    test ! -e "$XDG_CONFIG_HOME/omarchy/language" || bad 'the language file was written'

    # da_DK is built: switches as upstream, records nothing.
    : > "$CALLS"
    rc=0; BUILT=da_DK.utf8 "$lang" da >out 2>err || rc=$?
    test "$rc" -eq 0 || bad "a built locale exited $rc: $(cat err)"
    ! grep -q '^select' "$CALLS" || bad 'a built locale was recorded again'
    grep -qx 'export LANG=da_DK.UTF-8' "$env_file" || bad 'LANG was not set to da_DK.UTF-8'
    test "$(cat "$XDG_CONFIG_HOME/omarchy/language")" = da || bad 'the language file is not da'

    # The generator is a refusal that names the writer.
    rc=0; ${omarchy}/share/omarchy/bin/omarchy-locale-generate da 2>err || rc=$?
    test "$rc" -ne 0 || bad 'omarchy-locale-generate exited 0'
    grep -q nixarchy-language-select err || bad 'omarchy-locale-generate does not name the writer'

    test "$fails" -eq 0
    echo "language-edge: every case passed"
    touch $out
  ''
