{
  pkgs,
  omarchy,
  omarchySrc,
}:
# #953: `omarchy restart shell` could leave ZERO shells. Upstream's kill loop is
# `while timeout 5 quickshell kill ...`; a plugin-heavy shell takes ~14 s to
# tear down (up to ~30 s mid hot-reload), so `timeout` gave up, the relaunch
# ran beside the dying shell, the new one exited "already running", and then
# the old one finished exiting. p620 sat with no shell and no bar for 17 min.
#
# omarchy-restart-shell is upstream's and unwrapped, so PATH stubs reach it
# (tests/AGENTS.md#a-path-stub-loses-to-runtimeinputs...). The stubs model one
# quickshell config whose old instance dies at a scripted time; `quickshell
# kill` blocks until then, like the real one. `list` prints a block copied from
# a real `quickshell list`, so the patch is matched against the real label.
#
# Case 2 runs UPSTREAM's unpatched script through the same harness: it must end
# with zero shells. That is the proof the harness reproduces the bug, and the
# signal to retire the patch if upstream ever stops losing this race.
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
    patched=${omarchy}/share/omarchy/bin/omarchy-restart-shell
    upstream=${omarchySrc}/bin/omarchy-restart-shell
    [ -f "$patched" ] && [ -f "$upstream" ] || { echo "restart script missing ($patched, $upstream)" >&2; exit 1; }

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
    chmod +x "$stubs"/*
    export PATH=$stubs:$PATH HYPRLAND_INSTANCE_SIGNATURE=test XDG_RUNTIME_DIR=$TMPDIR

    now() { date +%s%3N; }
    # run_case NAME SCRIPT OLD_DEATH_MS|never NEW_READY_MS [EXIT_TIMEOUT]
    run_case() {
      rm -rf "$STATE" && mkdir -p "$STATE"
      if [ "$3" = never ]; then echo never > "$STATE/old-death"; else echo $(( $(now) + $3 )) > "$STATE/old-death"; fi
      echo "$4" > "$STATE/new-ready-delay"
      start=$(now)
      OMARCHY_SHELL_EXIT_TIMEOUT=''${5:-60} bash "$2" > "$STATE/out" 2> "$STATE/err" && rc=0 || rc=$?
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

    # 1. A slow teardown (7 s > `timeout 5`), and a new shell that answers after
    #    3 s -- longer than upstream's readiness poll lasts against these stubs
    #    (20 x 0.1 s), so part 2 of the patch is exercised as well.
    run_case slow-patched "$patched" 7000 3000
    [ "$shells" = 1 ] || fail "slow teardown: the patched restart ended with $shells shells"
    [ "$rc" = 0 ] || fail "slow teardown: one shell came up, but the restart reported failure (exit $rc)"
    grep -q already-running "$STATE/launches" && fail "slow teardown: the patched restart launched beside the dying shell"
    ran=$((ran + 1))

    # 2. The negative control: upstream's script, same harness, must lose.
    run_case slow-upstream "$upstream" 7000 3000
    [ "$shells" = 0 ] && grep -q already-running "$STATE/launches" \
      || fail "upstream's script no longer ends with zero shells here: the harness cannot see #953, or upstream fixed it and the patch can go"
    ran=$((ran + 1))

    # 3. A wedged old shell: bounded, reported, and no second launch.
    run_case wedged-patched "$patched" never 0 6
    [ "$rc" != 0 ] && grep -q "did not exit within 6s" "$STATE/err" || fail "a wedged shell was not reported"
    [ ! -e "$STATE/launches" ] || fail "a wedged shell still got a second one launched beside it"
    ran=$((ran + 1))

    # 4. A fast teardown stays fast.
    run_case fast-patched "$patched" 500 0
    [ "$shells" = 1 ] || fail "fast teardown: the patched restart ended with $shells shells"
    [ "$rc" = 0 ] || fail "fast teardown: the restart reported failure (exit $rc)"
    (( elapsed < 4000 )) || fail "fast teardown took ''${elapsed} ms"
    ran=$((ran + 1))

    [ "$ran" = 4 ] || fail "only $ran of 4 cases ran"
    echo "omarchy-restart-shell ends with exactly one shell in all four cases (#953)"
    touch $out
  ''
