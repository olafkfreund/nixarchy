{ pkgs, config }:
# Nothing in hardware.graphics may carry a newer glibc than
# programs.hyprland.package: Hyprland loads these drivers into its own process,
# and one built against a newer glibc fails to load (#1154, #1158).
#
# Checked: package and package32 (always; both are lazy and cheap, so the
# 32-bit branch runs even with enable32Bit off), and every extraPackages(32)
# entry that has a C toolchain, which is how a machine's own `mesa` can bring
# the mismatch back. The comparison is done in Nix; the shell only prints.
#
# No permanent negative control: both sides are moving inputs that agree
# today. §1 was proved on #1154's lock (2.44 against 2.42); see #1162.
let
  g = config.hardware.graphics;
  libcOf = p: p.stdenv.cc.libc.version or null;
  compositor = libcOf config.programs.hyprland.package;

  drivers = [
    {
      name = "package";
      libc = libcOf g.package;
    }
    {
      name = "package32";
      libc = libcOf g.package32;
    }
  ]
  ++ map (p: {
    name = "extraPackages: ${p.name or "?"}";
    libc = libcOf p;
  }) g.extraPackages
  ++ map (p: {
    name = "extraPackages32: ${p.name or "?"}";
    libc = libcOf p;
  }) g.extraPackages32;

  checked = builtins.filter (d: d.libc != null) drivers;
  newer = builtins.filter (d: builtins.compareVersions d.libc compositor == 1) checked;

  lines = map (d: "${d.name}: glibc ${d.libc}") checked;
  verdict =
    if newer == [ ] then
      "ok"
    else
      "FAIL: newer glibc than programs.hyprland.package (${compositor}) in: "
      + pkgs.lib.concatMapStringsSep ", " (d: "${d.name} (${d.libc})") newer
      + " (#1158)";
in
pkgs.runCommand "nixarchy-graphics-glibc" { } ''
  echo "compositor glibc: ${compositor}"
  ${pkgs.lib.concatMapStringsSep "\n" (l: "echo ${pkgs.lib.escapeShellArg l}") lines}

  verdict=${pkgs.lib.escapeShellArg verdict}
  if [ "$verdict" != "ok" ]; then
    echo "$verdict" >&2
    exit 1
  fi

  echo "hardware.graphics' drivers share the compositor's glibc"
  touch $out
''
