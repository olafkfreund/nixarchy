{ pkgs, self }:
let
  needsKey =
    d:
    let
      walk =
        x:
        if builtins.isAttrs x then
          if (x.type or null) == "derivation" then
            false
          else
            ((x.type or null) == "luks" && (x.passwordFile or null) == "/tmp/nixarchy-luks.key")
            || builtins.any (name: builtins.match "^_.*" name == null && walk (builtins.getAttr name x)) (
              builtins.attrNames x
            )
        else if builtins.isList x then
          builtins.any walk x
        else
          false;
    in
    walk d;
in
assert needsKey self.nixosConfigurations.reference.config.disko.devices;
assert !(needsKey self.nixosConfigurations.reference-unencrypted.config.disko.devices);
pkgs.runCommand "nixarchy-installer-layout-eval" { } ''
  echo 'ok evaluated encrypted reference needs the temporary LUKS key'
  echo 'ok evaluated plain reference does not need the temporary LUKS key'
  touch "$out"
''
