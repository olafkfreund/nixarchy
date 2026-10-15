{
  pkgs,
  doctor,
  omarchy,
}:
# The doctor's Omarchy-channel line (#1278), against fixture flakes.
#
# The line is asked of `nixarchy-channel omarchy --current` rather than parsed
# from flake.nix a second time, so what this proves is that the doctor reports
# each of the four answers the command can give -- and says nothing, rather
# than something wrong, on a machine where the command is not installed.
#
# The fixtures are the real installer template with its placeholders filled, and
# the dev/edge ones are made by the command itself, so the doctor is reading
# exactly what a user's flake would hold.
let
  template = builtins.readFile ../installer/template/flake.nix;
  filled =
    builtins.replaceStrings
      [ "@nixpkgs_url@" "@nixarchy_url@" ]
      [ "github:NixOS/nixpkgs/nixos-unstable" "github:olafkfreund/nixarchy/release" ]
      template;
in
pkgs.runCommand "nixarchy-doctor-channel" { nativeBuildInputs = [ pkgs.gnugrep ]; } ''
  export HOME=$PWD/home USER=tester
  mkdir -p "$HOME"
  bindir=${omarchy}/share/omarchy/bin
  ch=$bindir/nixarchy-channel

  mk() { mkdir -p "$1"; cat > "$1/flake.nix" < ${pkgs.writeText "flake.nix" filled}; }
  co=$PWD/checkout
  mkdir -p "$co/.git" "$co/bin" "$co/default" "$co/shell"
  echo 'ref: refs/heads/main' > "$co/.git/HEAD"
  # The switch re-locks, which needs a network; a stub that succeeds stands in.
  mkdir -p lock-ok
  printf '#!/bin/sh\nexit 0\n' > lock-ok/nix
  chmod +x lock-ok/nix
  export PATH=$PWD/lock-ok:$PATH

  mk stable
  mk edge
  echo y | NIXARCHY_FLAKE=$PWD/edge $ch omarchy edge >/dev/null 2>&1 || true
  mk dev
  echo y | NIXARCHY_FLAKE=$PWD/dev $ch omarchy dev "$co" >/dev/null 2>&1 || true
  mk custom
  sed -i 's|github:olafkfreund/nixarchy/release|github:someone/their-fork|' custom/flake.nix

  # With the Omarchy tree on PATH, as it is on a machine that runs nixarchy.
  run() { ( export NIXARCHY_FLAKE=$PWD/$1; PATH=$bindir:$PATH ${doctor}/bin/nixarchy-doctor 2>&1 ) || true; }
  # Without it, as on a machine the doctor is run on before nixarchy is there.
  run_bare() { ( export NIXARCHY_FLAKE=$PWD/$1; ${doctor}/bin/nixarchy-doctor 2>&1 ) || true; }

  fails=0
  want() {
    if <<<"$2" grep -q -- "$3"; then echo "  ok      $1"
    else echo "  FAILED  $1: no /$3/ in the output"; fails=$((fails + 1)); fi
  }
  wantnot() {
    if <<<"$2" grep -q -- "$3"; then echo "  FAILED  $1: /$3/ present and should not be"; fails=$((fails + 1))
    else echo "  ok      $1"; fi
  }

  o=$(run stable)
  # An empty output makes every `want` fail alike, which reads as every rule
  # being wrong. Say which it is.
  <<<"$o" grep -q 'Updates' || { echo "the doctor printed no Updates section:"; echo "$o"; exit 1; }
  want    "stable is reported"            "$o" 'omarchy-channel: stable'
  o=$(run edge)
  want    "edge is reported"              "$o" 'omarchy-channel: edge'
  o=$(run dev)
  want    "dev is reported"               "$o" 'omarchy-channel: dev'
  want    "and names the checkout"        "$o" "your checkout at $co"
  o=$(run custom)
  want    "custom is reported"            "$o" 'omarchy-channel: custom'
  o=$(run_bare stable)
  wantnot "no line where the command is absent" "$o" 'omarchy-channel'

  echo
  if [ "$fails" -gt 0 ]; then echo "$fails failed"; exit 1; fi
  echo "doctor-channel: all assertions hold"
  touch $out
''
