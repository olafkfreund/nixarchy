# nixpkgs wraps kitty (and may wrap ghostty); match their wrapped process names.
if grep -q 'if pgrep -x kitty' $out/share/omarchy/bin/omarchy-restart-terminal; then
  substituteInPlace $out/share/omarchy/bin/omarchy-restart-terminal \
    --replace-fail 'if pgrep -x kitty >/dev/null; then' "if pgrep -x '[.]?kitty(-wrapped)?' >/dev/null; then" \
    --replace-fail '  killall -SIGUSR1 kitty >/dev/null' "  pkill -USR1 -x '[.]?kitty(-wrapped)?' >/dev/null" \
    --replace-fail 'if pgrep -x ghostty >/dev/null; then' "if pgrep -x '[.]?ghostty(-wrapped?)?' >/dev/null; then" \
    --replace-fail '  killall -SIGUSR2 ghostty' "  pkill -USR2 -x '[.]?ghostty(-wrapped?)?'"
else
  substituteInPlace $out/share/omarchy/bin/omarchy-restart-terminal \
    --replace-fail 'pkill -SIGUSR1 -x kitty' "pkill -SIGUSR1 -x '[.]?kitty(-wrapped)?'" \
    --replace-fail 'pkill -SIGUSR2 -x ghostty' "pkill -SIGUSR2 -x '[.]?ghostty(-wrapped?)?'"
fi
