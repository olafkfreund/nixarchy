{ pkgs, omarchy }:
# #707: upstream's first login writes mise launchers into ~/.local/bin, ahead of
# the Nix profiles on PATH, so a Nix-installed codex never ran. Two halves:
# omarchy-mise-install writes no launcher for a command Nix provides, and
# omarchy-mise-unshadow removes the ones written before that. A runCommand: both
# are file operations against PATH, and checks.session installs no agents, so a
# VM would pass without the fix.
pkgs.runCommand "nixarchy-mise-launchers" { } ''
  export HOME=$PWD/home USER=tester
  mkdir -p "$HOME/.local/bin" nixbin other
  fails=0
  ok() { echo "  ok      $1"; }
  bad() { echo "  FAILED  $1"; fails=$((fails + 1)); }
  exe() { printf '#!${pkgs.runtimeShell}\nexit 0\n' > "$1"; chmod +x "$1"; }
  base=$PATH:${omarchy}/bin

  # (a) Nix provides codex: no launcher.
  exe nixbin/codex
  PATH=$HOME/.local/bin:$PWD/nixbin:$base omarchy-mise-install codex >/dev/null
  [ ! -e "$HOME/.local/bin/codex" ] && ok "(a) a Nix codex gets no mise launcher" ||
    bad "(a) a Nix codex gets no mise launcher: omarchy-mise-install wrote one"

  # (b) Nothing provides hunk: upstream's launcher, unchanged.
  PATH=$HOME/.local/bin:$base omarchy-mise-install aqua:modem-dev/hunk hunk >/dev/null
  grep -q '^exec mise x ' "$HOME/.local/bin/hunk" 2>/dev/null && ok "(b) a tool Nix lacks still gets its launcher" ||
    bad "(b) a tool Nix lacks still gets its launcher"

  # (c)-(e): the cleanup for launchers written before the guard existed.
  PATH=$HOME/.local/bin:$base omarchy-mise-install gemini >/dev/null
  exe nixbin/gemini
  printf '#!/bin/sh\nexec mise x claude\n' > "$HOME/.local/bin/claude"
  exe nixbin/claude
  PATH=$base omarchy-mise-unshadow "$PWD/other" "$PWD/nixbin" >/dev/null
  [ ! -e "$HOME/.local/bin/gemini" ] && ok "(c) a launcher shadowing a Nix command is removed" ||
    bad "(c) a launcher shadowing a Nix command is removed"
  [ -e "$HOME/.local/bin/hunk" ] && ok "(d) a launcher with no Nix twin is kept" ||
    bad "(d) a launcher with no Nix twin is kept"
  [ -e "$HOME/.local/bin/claude" ] && ok "(e) a user's own script of the same name is kept" ||
    bad "(e) a user's own script of the same name is kept"

  [ "$fails" -eq 0 ] || exit 1
  touch $out
''
