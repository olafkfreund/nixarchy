{ inputs, pkgs }:
let
  lib = inputs.nixpkgs.lib;
  system = pkgs.stdenv.hostPlatform.system;
  configWith =
    enabled:
    (lib.nixosSystem {
      inherit system;
      modules = [
        inputs.self.nixosModules.nixarchy
        {
          programs.nixarchy.enable = true;
          programs.nixarchy.apps.retroarch.enable = enabled;
          boot.loader.grub.device = "nodev";
          fileSystems."/" = {
            device = "/dev/null";
            fsType = "ext4";
          };
          system.stateVersion = "25.05";
        }
      ];
    }).config;
  on = configWith true;
  off = configWith false;
  resourceNames = [
    "retroarch-with-cores"
    "libretro-core-info"
    "libretro-shaders-slang"
    "retroarch-joypad-autoconfig"
  ];
  resources = builtins.filter (
    p: builtins.elem (lib.getName p) resourceNames
  ) on.environment.systemPackages;
  profile = pkgs.buildEnv {
    name = "retroarch-module-profile";
    paths = resources;
    pathsToLink = on.environment.pathsToLink;
    ignoreCollisions = true;
  };
  shareLinks = [
    "/share/retroarch/cores"
    "/share/libretro"
  ];
in
pkgs.runCommand "nixarchy-retroarch-paths"
  {
    nativeBuildInputs = with pkgs; [
      bash
      coreutils
      gnugrep
      gnused
    ];
    onNames = lib.concatStringsSep " " (map lib.getName resources);
    onLinks = lib.concatStringsSep " " on.environment.pathsToLink;
    offNames = lib.concatStringsSep " " (map lib.getName off.environment.systemPackages);
    offLinks = lib.concatStringsSep " " off.environment.pathsToLink;
  }
  ''
    fail() { echo "FAIL: $1" >&2; exit 1; }
    for name in ${lib.concatStringsSep " " resourceNames}; do
      [[ " $onNames " == *" $name "* ]] || fail "enabled module omitted $name"
      [[ " $offNames " != *" $name "* ]] || fail "disabled module still has $name"
    done
    for path in ${lib.concatStringsSep " " shareLinks}; do
      [[ " $onLinks " == *" $path "* ]] || fail "enabled module omitted profile link $path"
      [[ " $offLinks " != *" $path "* ]] || fail "disabled module still has profile link $path"
    done

    profile=${profile}
    test -f "$profile/lib/retroarch/cores/bsnes_libretro.so" || fail "profile has no bsnes core"
    test -f "$profile/share/retroarch/cores/bsnes_libretro.info" || fail "profile has no bsnes core info"
    test -f "$profile/share/libretro/shaders/shaders_slang/crt/crt-royale.slangp" || fail "profile has no CRT Royale preset"
    test -f "$profile/share/libretro/autoconfig/udev/8BitDo_M30.cfg" || fail "profile has no joypad profile"

    installer=${
      inputs.self.packages.${system}.omarchy
    }/share/omarchy/bin/omarchy-install-gaming-retroarch
    test -f "$installer" || fail "patched RetroArch installer is missing"
    mkdir -p home/.config/retroarch/config stubs
    export HOME=$PWD/home
    CFG=$HOME/.config/retroarch/retroarch.cfg
    printf '%s\n' \
      'libretro_directory = "/nix/store/stale/cores"' \
      'libretro_info_path = "/nix/store/stale/info"' \
      'video_shader_dir = "/nix/store/stale/shaders"' \
      'joypad_autoconfig_dir = "/nix/store/stale/autoconfig"' > "$CFG"
    printf '%s\n' '#reference "/nix/store/stale/shader.slangp"' > "$HOME/.config/retroarch/config/global.slangp"
    printf '%s\n' '#!${pkgs.bash}/bin/bash' 'exit 0' > stubs/omarchy-pkg-add
    cp stubs/omarchy-pkg-add stubs/setsid
    chmod +x stubs/*
    export PATH=$PWD/stubs:$PATH
    cp "$CFG" before.cfg
    cp "$HOME/.config/retroarch/config/global.slangp" before.slangp
    if refusal=$("$installer" 2>&1); then
      fail "installer accepted missing system-profile cores"
    fi
    [[ $refusal == *"RetroArch resources are not in the system profile"* ]] || fail "installer refused without the recovery instruction"
    cmp before.cfg "$CFG" || fail "installer changed retroarch.cfg without system-profile cores"
    cmp before.slangp "$HOME/.config/retroarch/config/global.slangp" || fail "installer changed the shader preset without system-profile cores"
    echo "RetroArch installer refuses missing profile without changing config"

    sed "s|test -d /run/current-system/sw/lib/retroarch/cores|test -d $profile/lib/retroarch/cores|" "$installer" > installer-with-profile
    chmod +x installer-with-profile
    ./installer-with-profile >/dev/null

    expect_key() {
      key=$1 value=$2
      got=$(grep "^$key = " "$CFG" || true)
      [ "$got" = "$key = \"$value\"" ] || fail "$key was [$got], expected [$value]"
    }
    expect_key libretro_directory /run/current-system/sw/lib/retroarch/cores
    expect_key libretro_info_path /run/current-system/sw/share/retroarch/cores
    expect_key video_shader_dir /run/current-system/sw/share/libretro/shaders/shaders_slang
    expect_key joypad_autoconfig_dir /run/current-system/sw/share/libretro/autoconfig
    preset=$HOME/.config/retroarch/config/global.slangp
    want='#reference "/run/current-system/sw/share/libretro/shaders/shaders_slang/crt/crt-royale.slangp"'
    [ "$(cat "$preset")" = "$want" ] || fail "global shader preset stayed stale"
    if grep -Fq '/nix/store/' "$CFG" "$preset"; then
      fail "RetroArch config retains a Nix store path"
    fi
    echo "RetroArch module profile and installer paths are stable"
    touch "$out"
  ''
