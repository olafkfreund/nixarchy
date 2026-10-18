{
  pkgs,
  omarchy,
}:
# #953: `omarchy restart shell` could leave ZERO shells, because upstream's kill
# loop gave up (`timeout 5`) on a slow teardown and the relaunch lost the race
# with the dying shell. nixarchy carried a patch for it; v4.0.5 waits for the
# old shell itself (`timeout 30`, then up to 30 s on `quickshell list`, then a
# 60 s readiness deadline), so the patch retired and this guards upstream's wait.
#
# omarchy-restart-shell is upstream's and unwrapped, so PATH stubs reach it
# (tests/AGENTS.md#a-path-stub-loses-to-runtimeinputs...). The stubs model one
# quickshell config whose old instance dies at a scripted time; `quickshell
# kill` blocks until then, like the real one. `list` prints a block copied from
# a real `quickshell list`.
pkgs.runCommand "nixarchy-shell-restart-race"
  {
    nativeBuildInputs = [
      pkgs.bash
      pkgs.coreutils
      pkgs.gnugrep
      pkgs.gnused
      pkgs.jq
    ];
  }
  ''
    # Keep this harness focused on teardown timing. Replace only the absolute
    # IPC dependency with our readiness stub; real IPC is checked separately.
    shipped=$TMPDIR/restart
    sed 's|${omarchy}/bin/omarchy-shell|omarchy-shell|g' \
      ${omarchy}/share/omarchy/bin/omarchy-restart-shell > "$shipped"
    [ -s "$shipped" ] || { echo "restart script missing ($shipped)" >&2; exit 1; }

    export STATE=$TMPDIR/state TREE=$TMPDIR/tree
    mkdir -p "$TREE/shell" && touch "$TREE/shell/shell.qml"
    stubs=$TMPDIR/stubs && mkdir -p "$stubs"

    # printf, not heredocs: a heredoc reindents this whole Nix string (AGENTS.md 5).
    printf '%s\n' \
      'now() { date +%s%3N; }' \
      'alive_old() {' \
      '  local d; d=$(cat "$STATE/old-death" 2>/dev/null) || return 1' \
      '  [ "$d" = never ] && return 0' \
      '  (( $(now) < d ))' \
      '}' > "$stubs/lib.sh"

    printf '%s\n' "#!${pkgs.bash}/bin/bash" '. "$(dirname "$0")/lib.sh"' \
      'case $1 in' \
      '  list)' \
      '    if alive_old || [ -e "$STATE/new-alive" ]; then' \
      '      printf "%s\n" "Instance jds91v5i4mt:" "  Process ID: 2136295" \' \
      '        "  Shell ID: 68a24b042f999b383a647267bc7fc360" \' \
      '        "  Config path: $TREE/shell/shell.qml" \' \
      '        "  Display connection: wayland/wayland-1" \' \
      '        "  Launch time: 2026-09-29 12:20:19 (running for 1 hours, 42 minutes, 24 seconds)" ""' \
      '    fi ;;' \
      '  kill)' \
      '    alive_old || exit 1' \
      '    while alive_old; do sleep 0.05; done ;;' \
      'esac' > "$stubs/quickshell"

    printf '%s\n' "#!${pkgs.bash}/bin/bash" '. "$(dirname "$0")/lib.sh"' \
      '[ "$1" = dispatch ] || exit 0' \
      'echo "launch $(now)" >> "$STATE/launches"' \
      'if alive_old; then echo already-running >> "$STATE/launches"' \
      'else echo $(( $(now) + $(cat "$STATE/new-ready-delay") )) > "$STATE/new-alive"; fi' > "$stubs/hyprctl"

    printf '%s\n' "#!${pkgs.bash}/bin/bash" '. "$(dirname "$0")/lib.sh"' \
      '[ "$1 $2" = "shell ping" ] || exit 1' \
      '[ -e "$STATE/new-alive" ] && (( $(now) >= $(cat "$STATE/new-alive") ))' > "$stubs/omarchy-shell"

    printf '%s\n' "#!${pkgs.bash}/bin/bash" \
      'if [ "$2" = show-environment ]; then echo "OMARCHY_PATH=$TREE"; fi' > "$stubs/systemctl"
    printf '%s\n' "#!${pkgs.bash}/bin/bash" 'exit 1' > "$stubs/omarchy-hyprland-session-locked"
    # Isolate the teardown race: no registered live instance, so the restart
    # uses its existing recovery fallback. Real discovery is tested separately.
    printf '%s\n' "#!${pkgs.bash}/bin/bash" "echo '[]'" > "$stubs/qs"
    export OMARCHY_PATH=$TREE WAYLAND_DISPLAY=wayland-test
    chmod +x "$stubs"/*
    export PATH=$stubs:$PATH HYPRLAND_INSTANCE_SIGNATURE=test XDG_RUNTIME_DIR=$TMPDIR

    now() { date +%s%3N; }
    # run_case NAME SCRIPT OLD_DEATH_MS|never NEW_READY_MS
    run_case() {
      rm -rf "$STATE" && mkdir -p "$STATE"
      if [ "$3" = never ]; then echo never > "$STATE/old-death"; else echo $(( $(now) + $3 )) > "$STATE/old-death"; fi
      echo "$4" > "$STATE/new-ready-delay"
      start=$(now)
      bash "$2" > "$STATE/out" 2> "$STATE/err" && rc=0 || rc=$?
      elapsed=$(( $(now) - start ))
      # The final state: let a dying old shell finish before counting.
      if [ "$3" != never ]; then while (( $(now) < $(cat "$STATE/old-death") )); do sleep 0.05; done; fi
      shells=0
      if [ "$3" = never ]; then shells=$((shells + 1)); fi
      [ -e "$STATE/new-alive" ] && shells=$((shells + 1))
      echo "$1: exit $rc, $shells shell(s), ''${elapsed} ms; stderr: $(tr '\n' ' ' < "$STATE/err")"
    }
    ran=0
    fail() { echo "FAIL: $1" >&2; exit 1; }

    # 1. A slow teardown (7 s, past the old `timeout 5`), and a new shell that
    #    answers after 3 s.
    run_case slow-shipped "$shipped" 7000 3000
    [ "$shells" = 1 ] || fail "slow teardown: the restart ended with $shells shells"
    [ "$rc" = 0 ] || fail "slow teardown: one shell came up, but the restart reported failure (exit $rc)"
    ran=$((ran + 1))

    # 2. A fast teardown stays fast.
    run_case fast-shipped "$shipped" 500 0
    [ "$shells" = 1 ] || fail "fast teardown: the restart ended with $shells shells"
    [ "$rc" = 0 ] || fail "fast teardown: the restart reported failure (exit $rc)"
    (( elapsed < 4000 )) || fail "fast teardown took ''${elapsed} ms"
    ran=$((ran + 1))

    [ "$ran" = 2 ] || fail "only $ran of 2 cases ran"
    echo "omarchy-restart-shell ends with exactly one shell in both cases (#953)"
    touch $out
  ''
