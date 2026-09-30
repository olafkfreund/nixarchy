{ pkgs, omarchy }:
# #1070: `omarchy menu close` must ask the enabled menu to dismiss() over
# `shell call` before falling back to upstream's `shell hide`, because hide
# reaches nixarchy-menu's close() and that starts dictation. D2: `shell call`
# answers "unknown" with exit 0 when the target has no such method, so the
# patch matches the REPLY, never the exit status.
pkgs.runCommand "nixarchy-menu-close"
  {
    nativeBuildInputs = [
      pkgs.bash
      pkgs.coreutils
      pkgs.gnugrep
    ];
  }
  ''
    menu=${omarchy}/share/omarchy/bin/omarchy-menu
    [ -f "$menu" ] || { echo "omarchy-menu is missing: $menu" >&2; exit 1; }

    stubs=$TMPDIR/stubs && mkdir -p "$stubs"
    export LOG=$TMPDIR/log

    # printf, not a heredoc: a heredoc reindents this whole Nix string (AGENTS.md 5).
    # $2 is the sub-verb ("call" or "hide"); a stub call answers $STUB_REPLY at
    # $STUB_STATUS, a stub hide always succeeds. Not named REPLY: bash reserves it.
    printf '%s\n' \
      "#!${pkgs.bash}/bin/bash" \
      'echo "$*" >> "$LOG"' \
      'case $2 in' \
      '  call) echo "$STUB_REPLY"; exit ''${STUB_STATUS:-0} ;;' \
      '  hide) exit 0 ;;' \
      'esac' > "$stubs/omarchy-shell"
    chmod +x "$stubs/omarchy-shell"
    export PATH=$stubs:$PATH

    ran=0
    fail() { echo "FAIL: $1" >&2; exit 1; }

    check_case() {
      name=$1 reply=$2 status=$3; shift 3
      : > "$LOG"
      STUB_REPLY="$reply" STUB_STATUS="$status" "$menu" close || true
      mapfile -t lines < "$LOG"
      want=("$@")
      [ "''${#lines[@]}" = "''${#want[@]}" ] || fail "$name: ''${#lines[@]} log line(s), wanted ''${#want[@]}: $(printf '%s|' "''${lines[@]}")"
      for i in "''${!want[@]}"; do
        [ "''${lines[$i]}" = "''${want[$i]}" ] || fail "$name: line $((i + 1)) was [''${lines[$i]}], wanted [''${want[$i]}]"
      done
      ran=$((ran + 1))
    }

    check_case "nixarchy-menu loaded" ok 0 \
      "shell call omarchy.menu dismiss {}"
    check_case "stock menu, no dismiss" unknown 0 \
      "shell call omarchy.menu dismiss {}" "shell hide omarchy.menu"
    check_case "shell not answering" "" 1 \
      "shell call omarchy.menu dismiss {}" "shell hide omarchy.menu"

    [ "$ran" = 3 ] || fail "only $ran of 3 cases ran"
    echo "omarchy-menu close dismisses first and falls back to hide (#1070)"
    touch $out
  ''
