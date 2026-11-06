{ pkgs, omarchySrc }:
pkgs.runCommand "nixarchy-default-agent-routes" { } ''
  set -euo pipefail
  script=${../pkgs/omarchy/nix-bin/omarchy-default-agent}
  menu=${omarchySrc}/default/omarchy/omarchy-menu.jsonc
  tools=${pkgs.coreutils}/bin
  grep_bin=${pkgs.gnugrep}/bin/grep
  sed_bin=${pkgs.gnused}/bin/sed
  real_home=$HOME
  log=$TMPDIR/log
  out_file=$TMPDIR/output
  failures=$TMPDIR/failures
  : > "$failures"
  export log agent_file WANT PKG_ADD_RC
  PKG_ADD_RC=0

  fail() { printf 'default-agent-routes: %s\n' "$*" >> "$failures"; }
  has() { "$grep_bin" -Fq -- "$2" "$1" || fail "$3: missing $2"; }
  lacks() { if "$grep_bin" -Fq -- "$2" "$1"; then fail "$3: unexpectedly found $2"; fi; }
  lacks_line() { if "$grep_bin" -Fxq -- "$2" "$1"; then fail "$3: unexpectedly found $2"; fi; }
  empty() { [ ! -s "$1" ] || fail "$2: unexpected call $(head -n 1 "$1")"; }

  mkdir -p "$TMPDIR/stubs" "$TMPDIR/mise-bin"
  printf '%s\n' '#!${pkgs.bash}/bin/bash' 'printf "pkg-add %s\n" "$*" >> "$log"' 'exit "$PKG_ADD_RC"' > "$TMPDIR/stubs/nixarchy-pkg-add"
  printf '%s\n' '#!${pkgs.bash}/bin/bash' 'printf "apply %s\n" "$(cat "$agent_file")" >> "$log"' > "$TMPDIR/stubs/nixarchy-apply"
  printf '%s\n' '#!${pkgs.bash}/bin/bash' 'printf "launched %s\n" "$(command -v "$WANT")" >> "$log"' 'exit 0' > "$TMPDIR/stubs/omarchy-agent"
  printf '%s\n' '#!${pkgs.bash}/bin/bash' 'printf "launcher %s\n" "$*" >> "$log"' > "$TMPDIR/stubs/omarchy-launch-floating-terminal-with-presentation"
  printf '%s\n' '#!${pkgs.bash}/bin/bash' 'echo mise >> "$log"' > "$TMPDIR/mise-bin/mise"
  chmod +x "$TMPDIR"/stubs/* "$TMPDIR/mise-bin/mise"

  make_agent() {
    mkdir -p "$1"
    printf '%s\n' '#!${pkgs.bash}/bin/bash' 'exit 0' > "$1/$2"
    chmod +x "$1/$2"
  }

  run_case() {
    local id=$1 mode=$2 dirs=$3 source_script=$script prior=-
    [ "$#" -lt 4 ] || source_script=$4
    [ "$#" -lt 5 ] || prior=$5
    export HOME=$TMPDIR/home XDG_DATA_HOME=$TMPDIR/home/data
    export XDG_STATE_HOME=$TMPDIR/home/state XDG_CONFIG_HOME=$TMPDIR/home/config
    export XDG_CACHE_HOME=$TMPDIR/home/cache WANT=$id
    agent_file=$HOME/.config/omarchy/defaults/agent
    rm -rf "$HOME"
    mkdir -p "$HOME" "$XDG_DATA_HOME" "$XDG_STATE_HOME" "$XDG_CONFIG_HOME" "$XDG_CACHE_HOME"
    if [ "$prior" != - ]; then
      mkdir -p "$(dirname "$agent_file")"
      printf '%s\n' "$prior" > "$agent_file"
    fi
    : > "$log"
    export PATH=$dirs:$TMPDIR/stubs:$tools
    rc=0
    if [ "$mode" = plain ]; then
      ${pkgs.bash}/bin/bash "$source_script" "$id" > "$out_file" 2>&1 </dev/null || rc=$?
    else
      ${pkgs.bash}/bin/bash "$source_script" --install "$id" > "$out_file" 2>&1 </dev/null || rc=$?
    fi
  }

  row_text=$("$grep_bin" -oE '"setup\.default\.agent\.[a-z0-9-]+"' "$menu" |
    "$sed_bin" 's/^"setup\.default\.agent\.//;s/"$//' | sort -u) || fail "cannot read menu rows"
  mapfile -t rows <<< "$row_text"
  [ "''${#rows[@]}" -ge 20 ] || fail "menu yielded fewer than 20 agent rows"
  [ "''${#rows[@]}" -eq 24 ] || fail "expected 24 menu rows, got ''${#rows[@]}"

  for id in "''${rows[@]}"; do
    if PATH=$tools command -v "$id" >/dev/null 2>&1; then fail "$id: present on fixture PATH"; fi
  done

  for id in "''${rows[@]}"; do
    run_case "$id" --install "$TMPDIR/mise-bin"
    if [ "$rc" -eq 0 ]; then
      has "$log" 'pkg-add ' "$id route"
      has "$log" 'apply ' "$id route"
    elif [ "$rc" -eq 1 ]; then
      has "$out_file" 'nixarchy does not install it' "$id route"
      empty "$log" "$id decline"
    else
      fail "$id route: exited $rc"
    fi
    lacks "$out_file" 'No way to install' "$id route"
    lacks_line "$log" 'mise' "$id route"
  done

  for pair in pi:pi-coding-agent omp:omp kilo:kilo cursor-agent:cursor-cli muse:muse-code; do
    IFS=: read -r id attr <<< "$pair"
    run_case "$id" --install "$TMPDIR/mise-bin"
    [ "$rc" -eq 0 ] || fail "$id attr: exited $rc"
    # Whole line: "pkg-add kilo" is a prefix of the retired kilocode-cli.
    "$grep_bin" -Fxq -- "pkg-add $attr" "$log" || fail "$id attr: missing pkg-add $attr"
    has "$log" "apply $id" "$id attr"
  done

  for pair in kimi:kimi-code mcode:minimax-code freebuff:freebuff commandcode:command-code ori:ori hermes:hermes-agent; do
    IFS=: read -r id attr <<< "$pair"
    for prior in claude -; do
      run_case "$id" --install "$TMPDIR/mise-bin" "$script" "$prior"
      [ "$rc" -eq 1 ] || fail "$id decline with $prior: exited $rc"
      has "$out_file" "$attr" "$id decline"
      empty "$log" "$id decline"
      if [ "$prior" = - ]; then
        [ ! -e "$agent_file" ] || fail "$id decline: created a default"
        has "$out_file" 'No default agent is set.' "$id decline"
      else
        [ "$(cat "$agent_file")" = claude ] || fail "$id decline: changed the default"
        has "$out_file" 'Your default agent is unchanged: claude.' "$id decline"
      fi
    done
  done
  run_case commandcode --install "$TMPDIR/mise-bin"
  has "$out_file" 'Command Code is unfree' 'commandcode note'
  for id in ori kimi; do
    run_case "$id" --install "$TMPDIR/mise-bin"
    lacks "$out_file" 'unfree' "$id note"
  done

  for id in "''${rows[@]}"; do
    for mode in --install plain; do
      run_case "$id" "$mode" "$TMPDIR/mise-bin"
      lacks_line "$log" 'mise' "$id $mode"
    done
  done
  "$sed_bin" -e '/^[[:space:]]*#/d' \
    -e '/^    \*\/mise\/shims | \*\/mise\/installs\/\* | \*\/mise\/command-wrappers\/\*) stale=true ;;$/d' \
    -e '/^if \[\[ \$stale == true \]\] && ! PATH=\$live_path command -v mise \&>\/dev\/null; then$/d' \
    "$script" > "$TMPDIR/no-mise-exceptions"
  if "$grep_bin" -Eq '(^|[^[:alnum:]_])mise([^[:alnum:]_]|$)' "$TMPDIR/no-mise-exceptions"; then
    fail "mise appears outside the two PATH-filter exceptions"
  fi

  "$sed_bin" '/pi) *echo pi-coding-agent/d' "$script" > "$TMPDIR/no-pi"
  cmp -s "$script" "$TMPDIR/no-pi" && fail "pi break did not land"
  run_case pi --install "$TMPDIR/mise-bin" "$TMPDIR/no-pi"
  [ "$rc" -eq 1 ] || fail "unknown route: exited $rc"
  has "$out_file" 'No way to install Pi is known.' 'unknown route'

  for dir in "$TMPDIR/old/mise/shims" "$TMPDIR/old/mise/installs/x/bin" "$TMPDIR/old/mise/command-wrappers/bin"; do
    make_agent "$dir" kimi
    make_agent "$dir" pi
    run_case kimi --install "$dir"
    [ "$rc" -eq 1 ] || fail "$dir: kimi shim was launched"
    has "$out_file" 'nixarchy does not install it' "$dir kimi"
    run_case pi --install "$dir"
    has "$log" 'pkg-add pi-coding-agent' "$dir pi"
  done

  make_agent "$TMPDIR/real/bin" kimi
  run_case kimi --install "$TMPDIR/old/mise/shims:$TMPDIR/real/bin"
  has "$log" "launched $TMPDIR/real/bin/kimi" 'real agent after shim'
  lacks "$log" 'pkg-add' 'real agent after shim'

  run_case kimi --install "$TMPDIR/old/mise/shims:$TMPDIR/real/bin:$TMPDIR/mise-bin"
  has "$log" "launched $TMPDIR/old/mise/shims/kimi" 'live mise outside shim'
  lacks_line "$log" 'mise' 'live mise outside shim'

  mkdir -p "$TMPDIR/old/mise/installs/mise/1/bin"
  cp "$TMPDIR/mise-bin/mise" "$TMPDIR/old/mise/installs/mise/1/bin/mise"
  run_case kimi --install "$TMPDIR/old/mise/shims:$TMPDIR/old/mise/installs/mise/1/bin"
  [ "$rc" -eq 1 ] || fail "mise inside installs vouched for a shim"
  has "$out_file" 'nixarchy does not install it' 'mise inside installs'

  for id in "''${rows[@]}"; do
    run_case "$id" plain "$TMPDIR/mise-bin"
    [ "$rc" -eq 0 ] || fail "$id terminal: exited $rc"
    has "$log" "launcher omarchy-default-agent --install $id" "$id terminal"
    lacks "$log" 'pkg-add' "$id terminal"
    lacks "$log" 'apply' "$id terminal"
    [ ! -e "$agent_file" ] || fail "$id terminal: recorded a default"
  done
  run_case kimi plain "$TMPDIR/real/bin"
  has "$log" "launched $TMPDIR/real/bin/kimi" 'present agent'
  lacks "$log" 'launcher' 'present agent'
  [ "$(cat "$agent_file")" = kimi ] || fail "present agent was not recorded"

  PKG_ADD_RC=1
  run_case pi --install "$TMPDIR/mise-bin" "$script" claude
  [ "$rc" -eq 1 ] || fail "failed pkg-add: exited $rc"
  [ "$(cat "$agent_file")" = claude ] || fail "failed pkg-add: changed default"
  lacks "$log" 'apply' 'failed pkg-add'
  PKG_ADD_RC=0
  run_case pi --install "$TMPDIR/mise-bin" "$script" claude
  [ "$rc" -eq 0 ] || fail "successful pkg-add: exited $rc"
  has "$log" 'apply pi' 'record before apply'

  [ ! -e "$real_home" ] || fail "wrote outside fixture: $real_home"
  if [ -s "$failures" ]; then
    cat "$failures" >&2
    exit 1
  fi
  touch $out
''
