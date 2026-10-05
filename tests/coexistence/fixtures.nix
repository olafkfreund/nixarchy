# Plain NixOS modules a user might carry alongside nixarchy, with no
# programs.nixarchy.* of their own. checks.coexistence (tests/coexistence/
# default.nix) runs nixarchy's reference config through each and checks it
# still works, per AGENTS.md#14. See #1162 -> #1163 for the worked example of
# what a coexistence bug looks like without one of these.
{
  # The commonest pattern: add a package to the merged graphics-drivers env.
  # Use nixarchy's selected package: its Mesa follows Hyprland's own nixpkgs,
  # not necessarily this configuration's pkgs.mesa.
  graphics-own-mesa =
    { config, ... }:
    {
      hardware.graphics.extraPackages = [ config.hardware.graphics.package ];
    };

  # p620's original pattern: 32-bit drivers added the same way.
  graphics-32bit =
    { config, ... }:
    {
      hardware.graphics.enable32Bit = true;
      hardware.graphics.extraPackages32 = [ config.hardware.graphics.package32 ];
    };

  # The documented escape hatch from #1163: replace nixarchy's package
  # outright rather than add beside it.
  graphics-own-package =
    { pkgs, ... }:
    {
      hardware.graphics.package = pkgs.mesa;
    };

  # Rusticl: mesa.opencl shares pname "mesa" with the main output but ships
  # no egl_vendor.d file, so it must not collide (#1165's review).
  graphics-opencl =
    { pkgs, ... }:
    {
      hardware.graphics.extraPackages = [ pkgs.mesa.opencl ];
    };

  # nixarchy adds ffmpeg to environment.systemPackages via the omarchy
  # package's runtimeDeps (pkgs/omarchy/default.nix). A user who installs
  # ffmpeg-full of their own must get THEIR bin/ffmpeg, not nixarchy's.
  systempkg-own-ffmpeg =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.ffmpeg-full ];
    };
}
