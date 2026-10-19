{ pkgs, omarchy }:
# #1370: nixpkgs wraps kitty, so the running process is .kitty-wrapped and
# `pgrep -x kitty` finds nothing. Stand-in processes are named by file name
# (comm; copies of bash blocked on a fifo, since coreutils dispatches on argv0), SIGUSR1/2 kill them, and `kitten` must survive: it shares
# the prefix but is not a terminal.
pkgs.runCommand "nixarchy-restart-terminal-wrapped"
  {
    nativeBuildInputs = [
      pkgs.procps
      pkgs.coreutils
    ];
  }
  ''
    mkfifo hold
    for n in .kitty-wrapped .ghostty-wrapped kitten; do
      cp ${pkgs.bash}/bin/bash ./$n
    done
    ./.kitty-wrapped -c 'read -t 1000 <>hold' & kitty=$!
    ./.ghostty-wrapped -c 'read -t 1000 <>hold' & ghostty=$!
    ./kitten -c 'read -t 1000 <>hold' & kitten=$!

    HOME=$TMPDIR bash ${omarchy}/share/omarchy/bin/omarchy-restart-terminal || true

    for i in $(seq 50); do
      if ! kill -0 $kitty 2>/dev/null && ! kill -0 $ghostty 2>/dev/null; then break; fi
      sleep 0.1
    done

    fail=0
    if kill -0 $kitty 2>/dev/null; then echo ".kitty-wrapped did not get SIGUSR1" >&2; fail=1; fi
    if kill -0 $ghostty 2>/dev/null; then echo ".ghostty-wrapped did not get SIGUSR2" >&2; fail=1; fi
    if ! kill -0 $kitten 2>/dev/null; then echo "kitten was signalled but is not a terminal" >&2; fail=1; fi

    kill $kitty $ghostty $kitten 2>/dev/null || true
    wait 2>/dev/null || true
    [ "$fail" = 0 ] || exit 1
    touch "$out"
  ''
