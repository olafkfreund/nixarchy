{ pkgs, ... }:
# #1285: the splash positions every sprite once, at start, so a display that
# appears later (a Thunderbolt dock's DisplayPort tunnel) left it centred on
# the first one. Every position now lives in layout(), which refresh_callback()
# re-runs when the window size changes. This holds that structure: a position
# statement added at top level, or the guard removed, is invisible to every VM
# check, because no guest ever has a display appear late. See
# tests/plymouth-layout.py, and tests/AGENTS.md for what only hardware shows.
pkgs.runCommand "nixarchy-plymouth-layout" { nativeBuildInputs = [ pkgs.python3 ]; } ''
  python3 ${./plymouth-layout.py} ${../pkgs/omarchy/nixarchy-plymouth.script}
  touch $out
''
