# The chosen layout reaches the session. Imported by host.nix, and by
# tests/keyboard-boot.nix so that check runs this code rather than a copy.
{
  config,
  lib,
  pkgs,
  ...
}:
{
  # Upstream's session reads XKBLAYOUT here; NixOS writes only KEYMAP=. Not in modules/nixos.nix,
  # because a Mode A machine keeps its layout. Why: installer/AGENTS.md
  environment.etc."vconsole.conf" =
    let
      inherit (config.services.xserver) xkb;
    in
    lib.mkIf
      (
        config.console.enable && !config.i18n.imperativeLocale && (xkb.layout != "us" || xkb.variant != "")
      )
      {
        source = lib.mkOverride 90 (
          pkgs.writeText "vconsole.conf" ''
            KEYMAP=${config.console.keyMap}
            ${lib.optionalString (config.console.font != null) "FONT=${config.console.font}"}
            XKBLAYOUT=${xkb.layout}
            XKBVARIANT=${xkb.variant}
          ''
        );
      };

  services.xserver.xkb.options = lib.mkIf (lib.hasInfix "," config.services.xserver.xkb.layout) (
    lib.mkDefault "terminate:ctrl_alt_bksp,grp:alts_toggle"
  );
}
