{ pkgs, omarchy }:
pkgs.runCommand "nixarchy-shell-session" { nativeBuildInputs = [ pkgs.python3 ]; } ''
  python3 ${./shell-session.py} ${omarchy}/share/omarchy/bin/nixarchy-shell-session
  touch "$out"
''
