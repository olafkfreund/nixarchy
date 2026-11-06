{ pkgs }:
pkgs.runCommand "nixarchy-agent-no-node" { nativeBuildInputs = [ pkgs.coreutils ]; } ''
  export HOME=$TMPDIR/home
  mkdir -p "$HOME"
  for prog in ${pkgs.pi-coding-agent}/bin/pi ${pkgs.omp}/bin/omp; do
    if ! timeout 120 env -i HOME="$HOME" PATH=/nonexistent "$prog" --version > ver 2>&1 || [ ! -s ver ]; then
      echo "FAIL: $prog needs something not on an empty PATH:" >&2
      cat ver >&2
      exit 1
    fi
  done
  touch $out
''
