{ pkgs, ... }:
pkgs.runCommand "nixarchy-stall-watch"
  {
    nativeBuildInputs = with pkgs; [
      bash
      coreutils
      procps
      util-linux
      iproute2
      gnugrep
      gawk
      findutils
      python3
    ];
  }
  ''
    cp ${../.github/scripts/stall-watch.sh} stall-watch.sh
    chmod +x stall-watch.sh
    patchShebangs stall-watch.sh
    fail() { echo "FAIL: $*" >&2; exit 1; }
    run() {
      local name=$1 seconds=$2 rc=0
      shift 2
      # The outer timeout bounds a case whose kill broke: it fails in a minute, not ten.
      SECONDS=0
      GITHUB_STEP_SUMMARY=$PWD/$name.summary timeout -k 5 60 bash ./stall-watch.sh run "$seconds" "$name.log" -- "$@" > "$name.out" 2>&1 || rc=$?
      echo "$rc" > "$name.rc"
      echo "$SECONDS" > "$name.secs"
    }

    printf '%s\n' '#!${pkgs.bash}/bin/bash' 'echo $$ > a.pid' 'exec sleep 600' > a.sh
    chmod +x a.sh
    run A 2 ./a.sh
    grep -qF '== process forest ==' A.out || fail "A: no '== process forest ==' in output"
    grep -qF 'sleep 600' A.out || fail "A: no sleep 600 in output"
    [ "$(cat A.rc)" = 124 ] || fail "A: exit $(cat A.rc), wanted 124"
    grep -qF '== process forest ==' A.summary || fail "A: no '== process forest ==' in summary"
    ! kill -0 "$(cat a.pid)" 2>/dev/null || fail 'A: sleep 600 still running'
    [ "$(cat A.secs)" -lt 30 ] || fail "A: took $(cat A.secs) s, so the group was not killed at the deadline"

    run B 30 true
    [ "$(cat B.rc)" = 0 ] || fail "B: exit $(cat B.rc), wanted 0"
    ! grep -qF '== process forest ==' B.out || fail 'B: unexpected snapshot'

    run C 30 sh -c 'exit 3'
    [ "$(cat C.rc)" = 3 ] || fail "C: exit $(cat C.rc), wanted 3"
    ! grep -qF '== process forest ==' C.out || fail 'C: unexpected snapshot'

    path_with_ss=$PATH
    export PATH='${
      pkgs.lib.makeBinPath (
        with pkgs;
        [
          bash
          coreutils
          procps
          util-linux
          gnugrep
          gawk
          findutils
        ]
      )
    }'
    run D 2 sleep 600
    export PATH=$path_with_ss
    [ "$(cat D.rc)" = 124 ] || fail "D: exit $(cat D.rc), wanted 124"
    grep -qF '== process forest ==' D.out || fail 'D: no process forest'
    grep -qF '== disk/mem ==' D.out || fail 'D: no disk/mem'

    [ -r /proc/locks ] || fail 'F: /proc/locks unreadable'
    flock -F f.lock sleep 600 &
    holder=$!
    for i in 1 2 3 4 5 6 7 8 9 10; do
      flock -n f.lock true || break
      sleep 0.1
    done
    printf '%s\n' '#!${pkgs.bash}/bin/bash' 'echo $$ > f.pid' 'exec flock -F f.lock sleep 600' > f.sh
    chmod +x f.sh
    run F 2 ./f.sh
    kill "$holder" 2>/dev/null || true
    wait "$holder" 2>/dev/null || true
    [ "$(cat F.rc)" = 124 ] || fail "F: exit $(cat F.rc), wanted 124"
    sed -n '/== \/proc\/locks ==/,/== sockets ==/p' F.out > f.locks
    grep -F -- '->' f.locks > f.waiters || true
    grep -qF "$(cat f.pid)" f.waiters || fail "F: no '->' waiter line in /proc/locks section"

    printf '%s\n' \
      'import socket, time' \
      's = socket.socket()' \
      's.bind(("127.0.0.1", 0))' \
      's.listen(2)' \
      'a = socket.create_connection(s.getsockname())' \
      'b = socket.create_connection(s.getsockname())' \
      'x, _ = s.accept()' \
      'y, _ = s.accept()' \
      'a.sendall(b"x" * 4096)' \
      'x.recv(4096)' \
      'open("g.ready", "w").close()' \
      'time.sleep(600)' > g.py
    python3 -I g.py &
    listener=$!
    for i in 1 2 3 4 5 6 7 8 9 10; do
      [ -f g.ready ] && break
      sleep 0.1
    done
    run G 2 sleep 600
    kill "$listener" 2>/dev/null || true
    wait "$listener" 2>/dev/null || true
    [ "$(cat G.rc)" = 124 ] || fail "G: exit $(cat G.rc), wanted 124"
    sed -n '/== sockets ==/,/== nix fds ==/p' G.out > g.sockets
    grep -Eq 'bytes_received:[1-9][0-9]*' g.sockets || fail 'G: sockets do not differ'
    [ "$(grep -c ESTAB g.sockets)" -ge 4 ] || fail 'G: sockets do not differ'

    sed -n '/name: Verify the generated menu defaults and app template/,/name: Failure digest/p' ${../.github/workflows/build.yml} > i.step
    grep -qF 'stall-watch.sh run' i.step || fail 'I: step 28 does not call stall-watch.sh'
    sed -n '/^    steps:/,/name: The gate did not succeed/p' ${../.github/workflows/build.yml} > i.start
    grep -qF 'JOB_T0=$(date +%s)' i.start || fail 'I: no JOB_T0 step'

    t0=$(( $(date +%s) - 3297 ))
    SECONDS=0
    rc=0
    JOB_T0=$t0 GITHUB_STEP_SUMMARY=$PWD/J.summary timeout -k 5 60 bash ./stall-watch.sh run 600 J.log -- sleep 600 > J.out 2>&1 || rc=$?
    [ "$rc" = 124 ] && [ "$SECONDS" -lt 20 ] && grep -qF '::error title=omarchy-stall::' J.out && grep -Eq '^deadline: [0-3]s;' J.out \
      || fail 'J: deadline not capped by job budget'

    touch "$out"
  ''
