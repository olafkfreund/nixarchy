{ inputs, pkgs }:
let
  testLib = import ./lib.nix { inherit inputs; };
  bin = name: "${testLib.vmPackage "nixarchy-${name}"}/bin/nixarchy-${name}";
  configWith =
    {
      nixarchy ? { },
      useGlobalPkgs ? true,
    }:
    (inputs.nixpkgs.lib.nixosSystem {
      system = pkgs.stdenv.hostPlatform.system;
      modules = [
        inputs.self.nixosModules.nixarchy
        inputs.home-manager.nixosModules.home-manager
        {
          programs.nixarchy = {
            enable = true;
          }
          // nixarchy;
          home-manager.useGlobalPkgs = useGlobalPkgs;
        }
        {
          users.users.someone = {
            isNormalUser = true;
            home = "/home/someone";
          };
          home-manager.users.someone.home.stateVersion = "25.05";
          boot.loader.grub.device = "/dev/sda";
          fileSystems."/" = {
            device = "/dev/sda1";
            fsType = "ext4";
          };
          system.stateVersion = "25.05";
        }
      ];
    }).config;
  unfreeOff = configWith { nixarchy.allowUnfree = false; };
  noScope = configWith { useGlobalPkgs = false; };
  variantBin =
    config: name:
    let
      pname = "nixarchy-${name}";
      package = pkgs.lib.findFirst (
        p: (p.pname or p.name or "") == pname
      ) (throw "${pname} missing from fixture") config.environment.systemPackages;
    in
    "${package}/bin/${pname}";
in
pkgs.runCommand "nixarchy-home-selection"
  {
    nativeBuildInputs = with pkgs; [
      bash
      coreutils
      gnugrep
      gnused
      nix
      util-linux
    ];
  }
  ''
    set +e
    fails=0
    bad() { echo "FAILED $1: $2"; fails=$((fails + 1)); }
    export HOME=$PWD/user XDG_CONFIG_HOME=$PWD/user/.config XDG_STATE_HOME=$PWD/user/.local/state
    export NIX_STATE_DIR=$PWD/nix-state NIX_LOG_DIR=$PWD/nix-state
    mkdir -p "$XDG_CONFIG_HOME/nixarchy" "$XDG_STATE_HOME" "$NIX_STATE_DIR"
    homefile=$XDG_CONFIG_HOME/nixarchy/home.nix
    appsfile=$XDG_CONFIG_HOME/nixarchy/apps.nix
    pkgadd=${bin "pkg-add"}
    pkgremove=${bin "pkg-remove"}
    optremove=${bin "opt-remove"}
    apply=${bin "apply"}
    offadd=${variantBin unfreeOff "pkg-add"}
    noscopeadd=${variantBin noScope "pkg-add"}
    noscoperemove=${variantBin noScope "pkg-remove"}
    noscopeoptremove=${variantBin noScope "opt-remove"}

    reset_files() {
      printf '%s\n' '{ pkgs, pkgsOther, ... }:' '{' '  home.packages = with pkgs; [  #@pkgs-begin' '  ];  #@pkgs-end' '}' > "$homefile"
      printf '%s\n' '{ pkgs, ... }:' '{' '  environment.systemPackages = with pkgs; [  #@pkgs-begin' '  ];  #@pkgs-end' '}' > "$appsfile"
    }
    reset_files
    cp "$appsfile" apps.before
    "$pkgadd" --home hello >case1.out 2>&1
    rc=$?
    [ "$rc" -eq 0 ] && grep -qF 'hello  #@pkg hello' "$homefile" && cmp -s apps.before "$appsfile" || bad 1 "rc=$rc $(cat case1.out)"

    reset_files
    cp "$homefile" home.before
    "$pkgadd" hello >case2.out 2>&1
    rc=$?
    [ "$rc" -eq 0 ] && grep -qF 'hello  #@pkg hello' "$appsfile" && cmp -s home.before "$homefile" || bad 2 "rc=$rc $(cat case2.out)"

    reset_files
    cp "$homefile" home.before; cp "$appsfile" apps.before
    "$pkgadd" --home firefox >case3.out 2>&1
    rc=$?
    [ "$rc" -ne 0 ] && grep -q 'curated' case3.out && cmp -s home.before "$homefile" && cmp -s apps.before "$appsfile" || bad 3 "rc=$rc $(cat case3.out)"

    mkdir -p stub
    printf '%s\n' '#!${pkgs.bash}/bin/bash' 'echo called >> "$SEARCH_CALLS"' >stub/nixarchy-search
    chmod +x stub/nixarchy-search
    export SEARCH_CALLS=$PWD/search.calls
    for args in '--home' '--home no-such-package-1809'; do
      reset_files
      cp "$homefile" home.before; cp "$appsfile" apps.before
      rm -f "$SEARCH_CALLS"
      PATH=$PWD/stub:$PATH script -qec "$pkgadd $args" /dev/null </dev/null >case4.out 2>&1
      rc=$?
      if [ "$args" = --home ]; then expected='usage: nixarchy-pkg-add'; else expected='nixpkgs has no package matching:'; fi
      [ "$rc" -eq 1 ] && grep -qF "$expected" case4.out && [ ! -e "$SEARCH_CALLS" ] && cmp -s home.before "$homefile" && cmp -s apps.before "$appsfile" || bad 4 "$args: rc=$rc $(cat case4.out)"
    done

    reset_files
    cp "$appsfile" apps.before
    "$offadd" --home discord >case5.out 2>&1
    rc=$?
    [ "$rc" -eq 0 ] && grep -qF '#@pkg discord' "$homefile" && ! grep -qF '#@unfree-allow' "$homefile" && ! grep -qF '#@unfree-allow' "$appsfile" && cmp -s apps.before "$appsfile" && grep -qF 'allow it in the system configuration' case5.out || bad 5 "rc=$rc $(cat case5.out)"

    reset_files
    sed -i '/#@pkgs-end/i\    hello  #@pkg hello' "$homefile"
    sed -i '/^}$/i\  a.b = 1;  #@opt a.b' "$homefile"
    cp "$appsfile" apps.before
    "$pkgremove" --home hello >case6pkg.out 2>&1
    pkg_rc=$?
    "$optremove" --home a.b >case6opt.out 2>&1
    opt_rc=$?
    [ "$pkg_rc" -eq 0 ] && [ "$opt_rc" -eq 0 ] && ! grep -qF '#@pkg hello' "$homefile" && ! grep -qF '#@opt a.b' "$homefile" && cmp -s apps.before "$appsfile" || bad 6 "pkg=$pkg_rc opt=$opt_rc $(cat case6pkg.out case6opt.out)"

    reset_files
    cp "$homefile" home.before; cp "$appsfile" apps.before
    for command in "$noscopeadd --home hello" "$noscoperemove --home hello" "$noscopeoptremove --home a.b"; do
      $command >case7.out 2>&1
      rc=$?
      [ "$rc" -eq 1 ] && grep -qF 'home-manager.useGlobalPkgs = true' case7.out && cmp -s home.before "$homefile" && cmp -s apps.before "$appsfile" || bad 7 "$command: rc=$rc $(cat case7.out)"
    done

    nh() { :; }
    nixarchy-branch-guard() { :; }
    export -f nh nixarchy-branch-guard
    mkdir -p flake
    printf '%s\n' '{ outputs = _: { }; }' >flake/flake.nix
    reset_files
    rm "$homefile"
    NIXARCHY_FLAKE=$PWD/flake "$apply" --yes --no-preview >case8plain.out 2>&1
    rc=$?
    generated=flake/nixarchy-apps.nix
    printf '%s\n' \
      '# Generated by nixarchy-apply. Do not edit -- your files' \
      '# are ~/.config/nixarchy/{apps,services,advanced,flatsnap}.nix and' \
      '# this is regenerated from them on every apply.' \
      '{' '  imports = [ ./nixarchy/apps.nix ];' '}' >plain.expected
    [ "$rc" -eq 0 ] && cmp -s plain.expected "$generated" || bad 8 "without home: rc=$rc $(cat case8plain.out)"
    reset_files
    NIXARCHY_FLAKE=$PWD/flake "$apply" --yes --no-preview >case8home.out 2>&1
    rc=$?
    user=$(id -un)
    [ "$rc" -eq 0 ] && cmp -s "$homefile" flake/nixarchy/home.nix && grep -qF '{ config, options, lib, ... }:' "$generated" && grep -qF 'configuredElsewhere = lib.any' "$generated" && grep -qF 'd.file != __curPos.file' "$generated" && grep -qF "home-manager.users.\"$user\".imports" "$generated" && grep -qF './nixarchy/home.nix' "$generated" && grep -qF 'config.home-manager.useGlobalPkgs' "$generated" && grep -qF "config.users.users.\"$user\".isNormalUser" "$generated" && grep -qF 'assertion = configuredElsewhere' "$generated" || bad 8 "with home: rc=$rc $(cat case8home.out)"

    cp "$generated" generated.before
    cp flake/nixarchy/home.nix copied.before
    cp flake/nixarchy/apps.nix copied-apps.before
    printf '%s\n' '  # source changed after the last apply' >>"$appsfile"
    NIXARCHY_FLAKE=$PWD/flake "$apply" --yes --no-preview --expect-sha256 home=$(printf %064d 0) >case9.out 2>&1
    rc=$?
    [ "$rc" -eq 4 ] && grep -qF 'Nothing was copied and nothing was built' case9.out && cmp -s generated.before "$generated" && cmp -s copied.before flake/nixarchy/home.nix && cmp -s copied-apps.before flake/nixarchy/apps.nix || bad 9 "rc=$rc $(cat case9.out)"

    sed -n '/^select_home_src() {/,/^}/p' "$apply" >select-home-function
    [ -s select-home-function ] || bad 10 'select_home_src extraction empty'
    source select-home-function
    pinned=$PWD/pinned
    srcdir=$XDG_CONFIG_HOME/nixarchy
    mkdir -p "$pinned"
    printf '%s\n' pinned >"$pinned/home.nix"
    rm -f "$srcdir/home.nix"
    selected=$(select_home_src)
    [ "$selected" = "$pinned/home.nix" ] || bad 10 "pinned selection: $selected"
    rm "$pinned/home.nix"
    selected=$(select_home_src)
    [ -z "$selected" ] || bad 10 "missing selection: $selected"
    [ "$(grep -cF '$srcdir/home.nix' "$apply")" -eq 1 ] || bad 10 'live source is tested outside select_home_src'

    sed -n '/^valid_user() {/,/^}/p' "$apply" >valid-user-function
    [ -s valid-user-function ] || bad 11 'valid_user extraction empty'
    source valid-user-function
    for name in alice bob_2; do valid_user "$name" || bad 11 "rejected $name"; done
    for name in Alice 'a b' 'x"y' ""; do valid_user "$name" && bad 11 "accepted [$name]"; done

    [ "$fails" -eq 0 ] || { echo "$fails case(s) failed"; exit 1; }
    touch "$out"
  ''
