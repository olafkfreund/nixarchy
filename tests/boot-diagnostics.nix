{ pkgs }:
pkgs.runCommand "nixarchy-boot-diagnostics" { nativeBuildInputs = [ pkgs.python3Minimal ]; } ''
  python3 ${./.}/boot-diagnostics.py
  touch "$out"
''
