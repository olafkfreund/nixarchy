{ pkgs, ... }:
let
  holder = builtins.toFile "argv-holder.c" ''
    #include <stdio.h>
    int main(void) {
      puts("ready");
      fflush(stdout);
      return getchar() == EOF;
    }
  '';
in
pkgs.runCommand "nixarchy-switch-indicator"
  {
    nativeBuildInputs = [
      pkgs.stdenv.cc
      pkgs.procps
      pkgs.python3
    ];
  }
  ''
    cc -x c ${holder} -o argv-holder
    python3 ${./switch-indicator.py} ${../pkgs/omarchy/switch-indicator.qml} ./argv-holder
    touch "$out"
  ''
