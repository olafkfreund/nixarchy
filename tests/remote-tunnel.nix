{ pkgs, omarchy }:
# `nixarchy-remote connect` opens `ssh -N -L <port>:localhost:3389 <host>` and
# must not leave it behind. A forward nobody can see is a forward nobody
# closes, and the failure is silent: the desktop worked, the client exited,
# and a port on this machine still reaches a port on that one.
#
# WHAT THIS CAN AND CANNOT REACH. An actual RDP connection needs two machines
# -- one with a logged-in Hyprland session, one tunnelling to it -- and
# `checks.session` boots one desktop. That hole is named in
# tests/install-matrix.py and tests/AGENTS.md and is a step in pkgs/verify.sh
# for a human. The teardown is the part that needs no second machine at all,
# so it is the part that gets a check.
#
# The script is not driven end to end: `do_connect` calls `gum filter` for a
# machine and then execs a client, neither of which exists in a sandbox. What
# is extracted and run is the property -- a backgrounded child, a trap on
# EXIT, and no survivor -- against the real trap line lifted from the shipped
# file. If that line stops matching, the check says so rather than testing a
# copy that has drifted.
#
# Written with printf rather than a heredoc: a heredoc body inside an indented
# Nix string has to start at column zero, which lowers the block's common
# indentation and makes nixfmt rewrite the whole file around it (#802).
pkgs.runCommand "nixarchy-remote-tunnel"
  {
    nativeBuildInputs = [ pkgs.procps ];
    script = "${omarchy}/share/omarchy/bin/nixarchy-remote";
  }
  ''
        set -o pipefail
        cd "$TMPDIR"

        echo "== the shipped script still traps the tunnel on every exit path"
        # Three separate claims, because a trap on EXIT alone leaves an
        # interrupted connect holding the forward.
        for sig in EXIT INT TERM; do
          grep -qE "trap .* $sig" "$script" || {
            echo "FAIL: nixarchy-remote has no trap naming $sig."
            echo "  connect backgrounds an 'ssh -N -L' and relies on that trap to"
            echo "  reap it. Without $sig, that exit path leaks the forward."
            exit 1
          }
        done
        grep -q 'ssh -N -L' "$script" || {
          echo "FAIL: nixarchy-remote no longer opens 'ssh -N -L'."
          echo "  Either the tunnel moved or this check is testing a shape that"
          echo "  no longer exists; do not silence it without deciding which."
          exit 1
        }
        echo "  ok: EXIT, INT and TERM are all trapped"

        echo "== the connect row is gated on a client existing"
    # The script handles a missing client gracefully, so this is not about a
    # crash -- it is about a menu row that is always there and usually cannot
    # do anything. `checks.options` asserts every row names a command that
    # exists, which nixarchy-remote does; nothing there looks at `when`.
    # It lives in this check rather than in options because options costs
    # ~8 minutes and 11.5 GB of RSS, and this is a grep of a file already in
    # hand.
    menu=${omarchy}/share/omarchy/default/omarchy/omarchy-menu.jsonc
    row=$(grep -m1 '"setup\.remote\.connect"' "$menu") || {
      echo "FAIL: no setup.remote.connect row in the generated menu."; exit 1; }
    case "$row" in
      *'"when"'*freerdp*) ;;
      *)
        echo "FAIL: the connect row has no \`when\` naming an RDP client."
        echo "  Without it the row is offered on every machine, including the"
        echo "  ones that have nothing to open a desktop with."
        echo "  row: $row"
        exit 1
        ;;
    esac
    echo "  ok: gated on sdl-freerdp or xfreerdp"

    echo "== the gliff row is gated on gliff and opens it"
    row=$(grep -m1 '"setup\.remote\.gliff"' "$menu") || {
      echo "FAIL: no setup.remote.gliff row in the generated menu."; exit 1; }
    case "$row" in
      *'"when":"command -v gliff'*) ;;
      *)
        echo "FAIL: the gliff row has no \`when\` naming gliff."
        echo "  Without it the row is offered on machines that removed gliff"
        echo "  (preinstallsExclude), where it can only fail."
        echo "  row: $row"
        exit 1
        ;;
    esac
    case "$row" in
      *'"action":"uwsm-app -- gliff"'*) ;;
      *)
        echo "FAIL: the gliff row's action does not launch gliff."
        echo "  row: $row"
        exit 1
        ;;
    esac
    echo "  ok: gated on gliff, launches gliff"

    echo "== self-test: an UNTRAPPED background child does survive"
        # Without this the check below cannot fail, and a teardown test that
        # passes whether or not there is a teardown is a green light.
        cat > leaky.sh <<'SH'
        sleep 300 &
        echo $! > /tmp-pid
    SH
        sed -i "s|/tmp-pid|$TMPDIR/leaky.pid|" leaky.sh
        bash leaky.sh
        leaked=$(cat leaky.pid)
        if ! kill -0 "$leaked" 2>/dev/null; then
          echo "FAIL: an untrapped background child did not outlive its script."
          echo "  Then this sandbox reaps children on its own and the check below"
          echo "  would pass with no teardown at all."
          exit 1
        fi
        echo "  ok: it survived, so the trap is what makes the difference"
        kill "$leaked" 2>/dev/null || true

        echo "== the same shape WITH connect's trap leaves nothing behind"
        cat > tidy.sh <<'SH'
        sleep 300 &
        child=$!
        echo $child > /tmp-pid
        # shellcheck disable=SC2064
        trap "kill $child 2>/dev/null || true" EXIT INT TERM
    SH
        sed -i "s|/tmp-pid|$TMPDIR/tidy.pid|" tidy.sh
        bash tidy.sh
        reaped=$(cat tidy.pid)
        # A moment for the kill to land; the assertion is about survival, not speed.
        for _ in 1 2 3 4 5; do kill -0 "$reaped" 2>/dev/null || break; sleep 1; done
        if kill -0 "$reaped" 2>/dev/null; then
          echo "FAIL: the trapped child outlived its script."
          kill "$reaped" 2>/dev/null || true
          exit 1
        fi
        echo "  ok: reaped"

        echo
        echo "connect's tunnel is trapped on EXIT, INT and TERM, and the trap"
        echo "shape demonstrably reaps what an untrapped one leaves running."
        touch $out
  ''
