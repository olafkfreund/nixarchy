{ pkgs, verify }:
# The PACKAGED nixarchy-verify, run to its summary on a machine with nothing.
#
# writeShellApplication adds errexit, so an unguarded `x=$(failing probe)`
# aborts the whole run silently (#1416): no summary, exit 1. The exit code
# cannot tell that from a run with a real failure row, so this asserts the
# summary line. `bash pkgs/verify.sh` would not do: the errexit is in the
# wrapper. Undeclared commands are PATH stubs; declared ones (systemctl is
# one) are exported functions, which beat the wrapper's PATH.
pkgs.runCommand "nixarchy-verify-runs"
  {
    nativeBuildInputs = [
      pkgs.bash
      pkgs.coreutils
      pkgs.gnugrep
    ];
  }
  ''
    set -euo pipefail
    export HOME=$TMPDIR/home XDG_RUNTIME_DIR=$TMPDIR/run WAYLAND_DISPLAY=wayland-1
    mkdir -p "$HOME" "$XDG_RUNTIME_DIR/ai-mirror" "$TMPDIR/stubs"
    for c in ai-mirror omarchy-shell hyprctl nixarchy-version; do
      printf '#!${pkgs.bash}/bin/bash\nexit 0\n' > "$TMPDIR/stubs/$c"
      chmod +x "$TMPDIR/stubs/$c"
    done
    # No "owner" key: the shape #1416 was reported with.
    printf '%s' '{"generation":3}' > "$XDG_RUNTIME_DIR/ai-mirror/state.json"
    systemctl() { case "$*" in *is-active*omarchy-voice*) return 0 ;; esac; return 1; }
    export -f systemctl
    export PATH=$TMPDIR/stubs:$PATH

    # Not the exit code: ✗ rows exit 1 as well.
    rc=0
    ${verify}/bin/nixarchy-verify > "$TMPDIR/log" 2>&1 || rc=$?
    if ! grep -Eq '[0-9]+ passed, [0-9]+ failed, [0-9]+ worth a look' "$TMPDIR/log"; then
      echo "FAIL: nixarchy-verify exited $rc without reaching its summary"
      tail -20 "$TMPDIR/log"
      exit 1
    fi
    echo "reached the summary (exit $rc)"
    touch $out
  ''
