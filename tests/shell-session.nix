{ pkgs, omarchy }:
pkgs.runCommand "nixarchy-shell-session"
  {
    nativeBuildInputs = [
      pkgs.bash
      pkgs.coreutils
      pkgs.jq
      pkgs.gnugrep
    ];
  }
  ''
    export TEST_BASH=${pkgs.bash}/bin/bash TEST_SLEEP=${pkgs.coreutils}/bin/sleep
    bash ${./shell-session.sh} ${omarchy}/share/omarchy/bin/nixarchy-shell-session
    touch "$out"
  ''
