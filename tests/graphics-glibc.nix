{ pkgs, config }:
# hardware.graphics.package (and package32, when enable32Bit is on) must not
# carry a newer glibc than programs.hyprland.package: Hyprland loads the
# drivers into its own process, and a driver built against a newer glibc than
# the compositor fails to load into it (#1154, #1158).
#
# The comparison is computed in Nix -- compareVersions on two strings -- so
# the shell only prints what was found and exits. No negative control on
# purpose: both sides are moving inputs (our nixpkgs, Hyprland's nixpkgs), and
# they happen to agree today. §1 of this repo's own rule was proved instead on
# #1154's lock, by hand, where the two genuinely disagree (2.44 vs 2.42) --
# see the PR for that output.
let
  compositor = config.programs.hyprland.package.stdenv.cc.libc.version;
  drivers = config.hardware.graphics.package.stdenv.cc.libc.version;
  drivers32 =
    if config.hardware.graphics.enable32Bit then
      config.hardware.graphics.package32.stdenv.cc.libc.version
    else
      null;

  newer = a: b: builtins.compareVersions a b == 1;

  verdict =
    if newer drivers compositor then
      "FAIL: hardware.graphics.package glibc ${drivers} is newer than programs.hyprland.package glibc ${compositor} (#1158)"
    else if drivers32 != null && newer drivers32 compositor then
      "FAIL: hardware.graphics.package32 glibc ${drivers32} is newer than programs.hyprland.package glibc ${compositor} (#1158)"
    else
      "ok";
in
pkgs.runCommand "nixarchy-graphics-glibc" { } ''
  echo "compositor glibc: ${compositor}"
  echo "drivers glibc:    ${drivers}"
  echo "drivers32 glibc:  ${if drivers32 == null then "n/a (enable32Bit is off)" else drivers32}"

  verdict=${pkgs.lib.escapeShellArg verdict}
  if [ "$verdict" != "ok" ]; then
    echo "$verdict" >&2
    exit 1
  fi

  echo "hardware.graphics' drivers share the compositor's glibc"
  touch $out
''
